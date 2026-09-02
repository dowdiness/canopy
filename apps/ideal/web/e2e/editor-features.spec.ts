import { test, expect } from '@playwright/test';
import { dispatchExternalCrdtChanged } from './support/dom-events';

// ── Helpers ──────────────────────────────────────────────────

/** Wait for the Rabbita app to mount and the editor to be ready. */
async function waitForEditor(
  page: import('@playwright/test').Page,
  path = '/',
) {
  await page.goto(path);
  await waitForEditorReady(page);
}

async function waitForEditorReady(page: import('@playwright/test').Page) {
  await expect(page).toHaveTitle('Canopy Editor');
  await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
  // Wait for the binding-owned CM6 editor to mount.
  await page.waitForFunction(() => {
    return document.querySelector('#canopy-text-editor .cm-editor') !== null;
  }, { timeout: 10000 });
}

/** Get the outline panel text content. */
async function getOutlineText(page: import('@playwright/test').Page) {
  return page.getByLabel('AST outline').innerText();
}

/** Type text into the binding-owned CM6 editor. */
async function typeInEditor(page: import('@playwright/test').Page, text: string) {
  await page.evaluate(() => {
    const cm = document.querySelector('#canopy-text-editor .cm-content') as HTMLElement;
    cm?.focus();
  });
  await page.keyboard.type(text, { delay: 20 });
}

// ── Example Buttons ──────────────────────────────────────────

test.describe('Example Buttons', () => {
  test('Basics example updates outline', async ({ page }) => {
    await waitForEditor(page);
    await page.getByRole('button', { name: 'Basics' }).click();
    const text = await getOutlineText(page);
    expect(text).toContain('module [double, result]');
    expect(text).toContain('(x) =>');
  });

  test('Currying example updates outline', async ({ page }) => {
    await waitForEditor(page);
    await page.getByRole('button', { name: 'Currying' }).click();
    const text = await getOutlineText(page);
    expect(text).toContain('module [add, add5, sum]');
    expect(text).toContain('Plus');
  });

  test('Composition example updates outline', async ({ page }) => {
    await waitForEditor(page);
    await page.getByRole('button', { name: 'Composition' }).click();
    const text = await getOutlineText(page);
    expect(text).toContain('module [inc, twice, result]');
  });

  test('Conditional example shows if node', async ({ page }) => {
    await waitForEditor(page);
    await page.getByRole('button', { name: 'Conditional' }).click();
    const text = await getOutlineText(page);
    expect(text).toContain('if');
  });

  test('Pipeline example updates outline', async ({ page }) => {
    await waitForEditor(page);
    await page.getByRole('button', { name: 'Pipeline' }).click();
    const text = await getOutlineText(page);
    expect(text).toContain('module [compose, double, inc, f]');
  });

  test('switching examples updates CRDT state', async ({ page }) => {
    await waitForEditor(page);
    // Open bottom panel and switch to CRDT State tab
    await page.getByRole('button', { name: 'Panels' }).click();
    await page.getByRole('tab', { name: 'CRDT State' }).click();

    await page.getByRole('button', { name: 'Basics' }).click();
    await page.waitForTimeout(200);
    const len1 = await page.locator('.state-value').last().innerText();

    await page.getByRole('button', { name: 'Pipeline' }).click();
    await page.waitForTimeout(200);
    const len2 = await page.locator('.state-value').last().innerText();
    expect(Number(len1)).not.toEqual(Number(len2));
  });
});

// ── Outline Refresh ──────────────────────────────────────────

test.describe('Outline Refresh', () => {
  test('outline updates after typing (select-all + replace)', async ({ page }) => {
    await waitForEditor(page);
    // Select all and replace with new content
    await page.evaluate(() => {
      const cm = document.querySelector('#canopy-text-editor .cm-content') as HTMLElement;
      cm?.focus();
    });
    await page.keyboard.press('Control+a');
    await page.keyboard.type('let f = (x) => x\nf 1', { delay: 10 });
    // Wait for outline refresh
    await page.waitForTimeout(300);
    const text = await getOutlineText(page);
    expect(text).toContain('module [f]');
  });

  test('outline updates when switching examples rapidly', async ({ page }) => {
    await waitForEditor(page);
    await page.getByRole('button', { name: 'Currying' }).click();
    await page.getByRole('button', { name: 'Conditional' }).click();
    await page.getByRole('button', { name: 'Basics' }).click();
    // Wait for the last refresh to complete
    await page.waitForTimeout(500);
    const text = await getOutlineText(page);
    expect(text).toContain('module [double, result]');
  });
});

// ── Persistence ──────────────────────────────────────────────

test.describe('Persistence', () => {
  test('restores saved CRDT state into CM6 after reload', async ({ page }) => {
    const room = `restore-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    await waitForEditor(page, `/#${room}`);

    await page.getByRole('button', { name: 'Currying' }).click();
    await page.waitForFunction(() => {
      return document.querySelector('#canopy-text-editor .cm-content')?.textContent?.includes('add5') ?? false;
    });

    await page.evaluate(() => {
      const b = (globalThis as any).__canopy_bridge;
      const roomId = location.hash.slice(1);
      localStorage.setItem(
        `canopy-doc-${roomId}`,
        b.crdt!.export_all_json(b.crdtHandle!),
      );
    });

    await page.reload();
    await waitForEditorReady(page);
    await page.waitForFunction(() => {
      const text = document.querySelector('#canopy-text-editor .cm-content')?.textContent ?? '';
      return text.includes('add5') && !text.includes('apply id 42');
    });
  });

  test('rejects and removes stored text schema 1 state', async ({ page }) => {
    const room = `schema-1-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    const key = `canopy-doc-${room}`;
    await page.addInitScript(({ storageKey }) => {
      localStorage.setItem(
        storageKey,
        '{"schema":1,"format":"event-graph-walker/text-sync","operations":[],"heads":[]}',
      );
    }, { storageKey: key });

    await waitForEditor(page, `/#${room}`);
    expect(
      await page.evaluate((storageKey) => localStorage.getItem(storageKey), key),
    ).toBeNull();
    expect(
      await page.evaluate(() => {
        const bridge = (globalThis as any).__canopy_bridge;
        try {
          bridge.crdt.export_since_json(
            bridge.crdtHandle,
            '{"schema":1,"format":"event-graph-walker/text-version","entries":[]}',
          );
          return false;
        } catch {
          return true;
        }
      }),
    ).toBe(true);

    await page.getByRole('button', { name: 'Basics' }).click();
    await expect(page.locator('#canopy-text-editor .cm-content')).toContainText('double');
  });
});

// ── CodeMirror Rendering ─────────────────────────────────────

test.describe('CodeMirror Rendering', () => {
  test('CM6 mounts without CDN access', async ({ page }) => {
    await page.route('https://esm.sh/**', (route) => route.abort());
    await waitForEditor(page);
    await expect(page.locator('#canopy-text-editor .cm-editor')).toBeVisible();
  });

  test('CM6 renders source lines', async ({ page }) => {
    await waitForEditor(page);
    const hasSource = await page.evaluate(() => {
      const editor = document.querySelector('#canopy-text-editor .cm-editor');
      return /\b(?:fn|let)\b/.test(editor?.textContent ?? '');
    });
    expect(hasSource).toBe(true);
  });

  test('line numbers are visible', async ({ page }) => {
    await waitForEditor(page);
    const hasLineNumbers = await page.evaluate(() => {
      const gutters = document.querySelectorAll('#canopy-text-editor .cm-gutterElement');
      return (gutters?.length ?? 0) > 0;
    });
    expect(hasLineNumbers).toBe(true);
  });

  test('CM6 renders lambda syntax highlighting', async ({ page }) => {
    await waitForEditor(page);
    const hasKeywordHighlight = await page.evaluate(() => {
      const spans = Array.from(document.querySelectorAll('#canopy-text-editor .cm-line span'));
      return spans.some((span) => {
        return span.textContent === 'fn'
          && getComputedStyle(span as HTMLElement).color === 'rgb(199, 146, 234)';
      });
    });
    expect(hasKeywordHighlight).toBe(true);
  });
});

// ── External Sync ────────────────────────────────────────────

test.describe('External Sync', () => {
  test('preserves local cursor when CRDT text is refreshed', async ({ page }) => {
    await waitForEditor(page);
    await page.getByRole('button', { name: 'Basics' }).click();
    await page.waitForFunction(() => {
      return document.querySelector('#canopy-text-editor .cm-content')?.textContent?.includes('double') ?? false;
    });

    await page.evaluate(() => {
      const cm = document.querySelector('#canopy-text-editor .cm-content') as HTMLElement;
      cm?.focus();
    });
    await page.keyboard.press('Control+End');

    await page.evaluate(() => {
      const b = (globalThis as any).__canopy_bridge;
      const text = b.crdt!.get_text(b.crdtHandle!);
      b.crdt!.set_text(b.crdtHandle!, `let remote = 0\n${text}`);
    });
    await dispatchExternalCrdtChanged(page);
    await page.waitForFunction(() => {
      return document.querySelector('#canopy-text-editor .cm-content')?.textContent?.includes('remote') ?? false;
    });

    await page.keyboard.type('z');
    const text = await page.evaluate(() => {
      const b = (globalThis as any).__canopy_bridge;
      return b.crdt!.get_text(b.crdtHandle!) as string;
    });
    expect(text.startsWith('let remote = 0\n')).toBe(true);
    expect(text.endsWith('z')).toBe(true);
  });

  test('falls back when a remote CRDT update precedes a CodeMirror edit', async ({ page }) => {
    await waitForEditor(page);
    const source = 'let x = 1\nx';
    await page.evaluate((text) => {
      const b = (globalThis as any).__canopy_bridge;
      b.crdt!.set_text(b.crdtHandle!, text);
    }, source);
    await dispatchExternalCrdtChanged(page);
    await page.waitForFunction((text) => {
      const b = (globalThis as any).__canopy_bridge;
      const visible = document.querySelector('#canopy-text-editor .cm-content')?.textContent ?? '';
      return b?.crdt?.get_text(b.crdtHandle) === text && visible.includes('let x');
    }, source);

    const result = await page.evaluate((expectedSource) => {
      const b = (globalThis as any).__canopy_bridge;
      const root = document.querySelector('#canopy-text-editor .cm-editor');
      const EditorView = (globalThis as any).__canopy_codemirror?.EditorView;
      const view = EditorView?.findFromDOM(root);
      if (!b?.crdt || b.crdtHandle == null || !view) {
        throw new Error('CodeMirror or CRDT bridge is unavailable');
      }
      const primary = b.crdtHandle as number;
      const remote = b.crdt.create_editor_with_undo(`remote-${Date.now()}`, 500);
      const initial = b.crdt.export_all_json(primary);
      if (b.crdt.apply_sync_json(remote, initial) !== 'ok') {
        throw new Error('failed to seed remote editor');
      }
      if (!b.crdt.handle_text_intent_checked(remote, 0, 0, 'R', 1)) {
        throw new Error('failed to create remote edit');
      }
      const remoteState = b.crdt.export_all_json(remote);
      if (b.crdt.apply_sync_json(primary, remoteState) !== 'ok') {
        throw new Error('failed to apply remote edit');
      }
      const remoteText = b.crdt.get_text(primary);
      // The remote operation has advanced the CRDT while CodeMirror still
      // displays the pre-remote source. The local transaction must therefore
      // take the snapshot fallback rather than applying its stale range.
      view.dispatch({ changes: { from: 0, to: 0, insert: 'L' } });
      return {
        remoteHandle: remote,
        remoteText,
        expected: `L${expectedSource}`,
      };
    }, source);

    expect(result.remoteText).not.toBe(result.expected);
    expect(result.remoteText).toContain('R');
    await page.waitForFunction((expected) => {
      const b = (globalThis as any).__canopy_bridge;
      const root = document.querySelector('#canopy-text-editor .cm-editor');
      const EditorView = (globalThis as any).__canopy_codemirror?.EditorView;
      const view = EditorView?.findFromDOM(root);
      return b?.crdt?.get_text(b.crdtHandle) === expected &&
        view?.state.doc.toString() === expected;
    }, result.expected);

    const convergence = await page.evaluate(({ remoteHandle, expected }) => {
      const b = (globalThis as any).__canopy_bridge;
      const status = b.crdt.apply_sync_json(
        remoteHandle,
        b.crdt.export_all_json(b.crdtHandle),
      );
      const text = b.crdt.get_text(remoteHandle);
      b.crdt.try_destroy_editor?.(remoteHandle);
      return { status, text, expected };
    }, { remoteHandle: result.remoteHandle, expected: result.expected });
    expect(convergence.status).toBe('ok');
    expect(convergence.text).toBe(convergence.expected);
  });
});

// ── Panel Toggles ────────────────────────────────────────────

test.describe('Panel Toggles', () => {
  test('Outline button toggles outline panel', async ({ page }) => {
    await waitForEditor(page);
    const outlineBtn = page.getByRole('button', { name: 'Outline' });
    const outline = page.getByLabel('AST outline');

    // Initially visible
    await expect(outline).toBeVisible();
    await expect(outlineBtn).toHaveAttribute('aria-pressed', 'true');

    // Toggle off
    await outlineBtn.click();
    await expect(outlineBtn).toHaveAttribute('aria-pressed', 'false');

    // Toggle back on
    await outlineBtn.click();
    await expect(outlineBtn).toHaveAttribute('aria-pressed', 'true');
  });

  test('Inspector button toggles inspector panel', async ({ page }) => {
    await waitForEditor(page);
    const inspectorBtn = page.getByRole('button', { name: 'Inspector' });
    const inspector = page.getByLabel('Node inspector');

    await expect(inspector).toBeVisible();
    await inspectorBtn.click();
    await expect(inspectorBtn).toHaveAttribute('aria-pressed', 'false');
    await inspectorBtn.click();
    await expect(inspectorBtn).toHaveAttribute('aria-pressed', 'true');
  });

  test('Panels button toggles bottom panel', async ({ page }) => {
    await waitForEditor(page);
    const panelsBtn = page.getByRole('button', { name: 'Panels' });

    // Initially hidden
    await expect(panelsBtn).toHaveAttribute('aria-pressed', 'false');

    // Toggle on — bottom tabs should appear
    await panelsBtn.click();
    await expect(panelsBtn).toHaveAttribute('aria-pressed', 'true');
    await expect(page.getByRole('tab', { name: 'Problems' })).toBeVisible();
    await expect(page.getByRole('tab', { name: 'Graphviz' })).toBeVisible();

    // Toggle off
    await panelsBtn.click();
    await expect(panelsBtn).toHaveAttribute('aria-pressed', 'false');
  });
});

// ── Bottom Panel Tabs ────────────────────────────────────────

test.describe('Bottom Panel Tabs', () => {
  test.beforeEach(async ({ page }) => {
    await waitForEditor(page);
    await page.getByRole('button', { name: 'Panels' }).click();
  });

  test('Problems tab shows no problems for valid input', async ({ page }) => {
    await page.getByRole('tab', { name: 'Problems' }).click();
    await expect(page.locator('.no-problems')).toContainText('No problems');
  });

  test('CRDT State tab shows agent and text length', async ({ page }) => {
    await page.getByRole('tab', { name: 'CRDT State' }).click();
    await expect(page.locator('.state-label').first()).toContainText('Agent');
    await expect(page.locator('.state-label').nth(2)).toContainText('Text length');
  });

  test('Graphviz tab renders SVG diagram', async ({ page }) => {
    await page.getByRole('tab', { name: 'Graphviz' }).click();
    // Wait for after_render SVG injection
    await page.waitForTimeout(500);
    const hasSvg = await page.locator('#canopy-graphviz-container svg').count();
    expect(hasSvg).toBeGreaterThan(0);
  });

  test('Graphviz SVG updates when switching examples', async ({ page }) => {
    await page.getByRole('tab', { name: 'Graphviz' }).click();
    await page.waitForTimeout(500);

    await page.getByRole('button', { name: 'Currying' }).click();
    await page.waitForTimeout(500);
    const svgText1 = await page.locator('#canopy-graphviz-container').innerText();

    await page.getByRole('button', { name: 'Conditional' }).click();
    await page.waitForTimeout(500);
    const svgText2 = await page.locator('#canopy-graphviz-container').innerText();

    expect(svgText1).not.toEqual(svgText2);
  });
});

// ── Sync Status ──────────────────────────────────────────────

test.describe('Sync Status', () => {
  test('shows connection status in PEERS section', async ({ page }) => {
    await waitForEditor(page);
    // Full E2E starts the relay server; focused/local runs may skip it.
    const peersText = await page.locator('.peer-item').innerText();
    expect(peersText).toMatch(
      /^(?:You \(connected\)|Connecting\u2026|Offline \u2014 reconnecting\u2026)$/,
    );
  });

  test('peer dot is visible', async ({ page }) => {
    await waitForEditor(page);
    await expect(page.locator('.peer-dot')).toBeVisible();
  });
});

// ── Undo / Redo ──────────────────────────────────────────────

test.describe('Undo / Redo', () => {
  test('text shortcut undoes exactly one CRDT history group', async ({ page }) => {
    await waitForEditor(page);

    const before = await page.evaluate(() => {
      const testWindow = window as any;
      testWindow.__textUndoDomEvents = 0;
      testWindow.__textRedoDomEvents = 0;
      document.addEventListener('request-undo', () => {
        testWindow.__textUndoDomEvents += 1;
      });
      document.addEventListener('request-redo', () => {
        testWindow.__textRedoDomEvents += 1;
      });
      const bridge = testWindow.__canopy_bridge;
      return bridge.crdt.get_text(bridge.crdtHandle);
    });
    await page.evaluate(() => {
      const content = document.querySelector(
        '#canopy-text-editor .cm-content',
      ) as HTMLElement;
      content?.focus();
    });
    await page.keyboard.press('Control+End');
    await page.keyboard.type('x');
    await page.waitForTimeout(600);
    await page.keyboard.type('y');

    await page.waitForFunction((expected) => {
      const bridge = (window as any).__canopy_bridge;
      return bridge?.crdt?.get_text(bridge.crdtHandle) === expected;
    }, `${before}xy`);

    await page.keyboard.press('Control+z');

    await page.waitForFunction((expected) => {
      const bridge = (window as any).__canopy_bridge;
      return bridge?.crdt?.get_text(bridge.crdtHandle) === expected;
    }, `${before}x`);
    await page.waitForTimeout(100);
    const afterUndo = await page.evaluate(() => {
      const bridge = (window as any).__canopy_bridge;
      return bridge.crdt.get_text(bridge.crdtHandle);
    });
    expect(afterUndo).toBe(`${before}x`);
    expect(await page.evaluate(() => (window as any).__textUndoDomEvents)).toBe(0);

    await page.keyboard.press('Control+Shift+Z');
    await page.waitForFunction((expected) => {
      const bridge = (window as any).__canopy_bridge;
      return bridge?.crdt?.get_text(bridge.crdtHandle) === expected;
    }, `${before}xy`);
    expect(await page.evaluate(() => (window as any).__textRedoDomEvents)).toBe(0);

    await page.keyboard.press('Control+z');
    await page.waitForFunction((expected) => {
      const bridge = (window as any).__canopy_bridge;
      return bridge?.crdt?.get_text(bridge.crdtHandle) === expected;
    }, `${before}x`);
    await page.keyboard.press('Control+y');
    await page.waitForFunction((expected) => {
      const bridge = (window as any).__canopy_bridge;
      return bridge?.crdt?.get_text(bridge.crdtHandle) === expected;
    }, `${before}xy`);
    expect(await page.evaluate(() => (window as any).__textRedoDomEvents)).toBe(0);
  });

  test('undo button does not crash with no history', async ({ page }) => {
    await waitForEditor(page);
    // Clicking undo with no edit history should not error
    const errors: string[] = [];
    page.on('pageerror', (err) => errors.push(err.message));

    await page.getByRole('button', { name: 'Undo' }).click();
    await page.waitForTimeout(300);

    const realErrors = errors.filter(
      (e) => !e.includes('WebSocket') && !e.includes('ws://'),
    );
    expect(realErrors).toEqual([]);
  });

  test('undo and redo round-trip typed text through the CRDT', async ({ page }) => {
    await waitForEditor(page);

    const before = await page.evaluate(() => {
      const bridge = (window as any).__canopy_bridge;
      return bridge.crdt.get_text(bridge.crdtHandle);
    });
    await page.evaluate(() => {
      const cm = document.querySelector('#canopy-text-editor .cm-content') as HTMLElement;
      cm?.focus();
    });
    await page.keyboard.press('End');
    await page.keyboard.type('z', { delay: 50 });
    const after = await page.evaluate(() => {
      const bridge = (window as any).__canopy_bridge;
      return bridge.crdt.get_text(bridge.crdtHandle);
    });
    expect(after).not.toBe(before);

    await page.getByRole('button', { name: 'Undo' }).click();
    await page.waitForFunction((text) => {
      const bridge = (window as any).__canopy_bridge;
      return bridge?.crdt?.get_text(bridge.crdtHandle) === text;
    }, before);

    await page.getByRole('button', { name: 'Redo' }).click();
    await page.waitForFunction((text) => {
      const bridge = (window as any).__canopy_bridge;
      return bridge?.crdt?.get_text(bridge.crdtHandle) === text;
    }, after);
    await expect(page.getByLabel('Code editor')).toBeVisible();
  });
});

// ── Mode Switch ──────────────────────────────────────────────

test.describe('Mode Switch', () => {
  test('Text mode is active by default', async ({ page }) => {
    await waitForEditor(page);
    await expect(
      page.getByRole('button', { name: 'Text' }),
    ).toHaveAttribute('aria-pressed', 'true');
    await expect(
      page.getByRole('button', { name: 'Structure' }),
    ).toHaveAttribute('aria-pressed', 'false');
  });

  test('switching to Structure mode updates button state', async ({ page }) => {
    await waitForEditor(page);
    await page.getByRole('button', { name: 'Structure' }).click();
    await expect(
      page.getByRole('button', { name: 'Structure' }),
    ).toHaveAttribute('aria-pressed', 'true');
    await expect(
      page.getByRole('button', { name: 'Text' }),
    ).toHaveAttribute('aria-pressed', 'false');
  });

  test('switching back to Text mode restores editor', async ({ page }) => {
    await waitForEditor(page);
    await page.getByRole('button', { name: 'Structure' }).click();
    await page.getByRole('button', { name: 'Text' }).click();
    // CM6 should be present
    const hasCm = await page.evaluate(() => {
      return document.querySelector('#canopy-text-editor .cm-editor') !== null;
    });
    expect(hasCm).toBe(true);
  });
});

// ── No Console Errors ────────────────────────────────────────

test.describe('Error Free', () => {
  test('no JavaScript errors during normal usage', async ({ page }) => {
    const errors: string[] = [];
    page.on('pageerror', (err) => errors.push(err.message));

    await waitForEditor(page);
    // Exercise features
    await page.getByRole('button', { name: 'Currying' }).click();
    await page.getByRole('button', { name: 'Conditional' }).click();
    await page.getByRole('button', { name: 'Basics' }).click();
    await page.getByRole('button', { name: 'Panels' }).click();
    await page.getByRole('tab', { name: 'Graphviz' }).click();
    await page.waitForTimeout(500);

    // Filter out WebSocket connection errors (expected without relay server)
    const realErrors = errors.filter(
      (e) => !e.includes('WebSocket') && !e.includes('ws://'),
    );
    expect(realErrors).toEqual([]);
  });
});
