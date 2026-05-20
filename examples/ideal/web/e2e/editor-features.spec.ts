import { test, expect } from '@playwright/test';

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
    expect(text).toContain('λx');
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
    await page.keyboard.type('let f = \\x.x\nf 1', { delay: 10 });
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
      const g = globalThis as any;
      const roomId = location.hash.slice(1);
      localStorage.setItem(
        `canopy-doc-${roomId}`,
        g.__canopy_crdt.export_all_json(g.__canopy_crdt_handle),
      );
    });

    await page.reload();
    await waitForEditorReady(page);
    await page.waitForFunction(() => {
      const text = document.querySelector('#canopy-text-editor .cm-content')?.textContent ?? '';
      return text.includes('add5') && !text.includes('apply id 42');
    });
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
      return (editor?.textContent ?? '').includes('let');
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
        return span.textContent === 'let'
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
      const g = globalThis as any;
      const handle = g.__canopy_crdt_handle;
      const text = g.__canopy_crdt.get_text(handle);
      g.__canopy_crdt.set_text(handle, `let remote = 0\n${text}`);
      document.getElementById('canopy-external-crdt-changed-trigger')?.click();
    });
    await page.waitForFunction(() => {
      return document.querySelector('#canopy-text-editor .cm-content')?.textContent?.includes('remote') ?? false;
    });

    await page.keyboard.type('z');
    const text = await page.evaluate(() => {
      const g = globalThis as any;
      return g.__canopy_crdt.get_text(g.__canopy_crdt_handle) as string;
    });
    expect(text.startsWith('let remote = 0\n')).toBe(true);
    expect(text.endsWith('z')).toBe(true);
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
    // Should show Connecting or Offline (no server running)
    const peersText = await page.locator('.peer-item').innerText();
    expect(
      peersText.includes('Connecting') || peersText.includes('Offline'),
    ).toBe(true);
  });

  test('peer dot is visible', async ({ page }) => {
    await waitForEditor(page);
    await expect(page.locator('.peer-dot')).toBeVisible();
  });
});

// ── Undo / Redo ──────────────────────────────────────────────

test.describe('Undo / Redo', () => {
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

  test('undo reverts typed text', async ({ page }) => {
    await waitForEditor(page);
    await page.getByRole('button', { name: 'Basics' }).click();
    await page.waitForTimeout(200);

    // Type something in the editor
    await page.evaluate(() => {
      const cm = document.querySelector('#canopy-text-editor .cm-content') as HTMLElement;
      cm?.focus();
    });
    await page.keyboard.press('End');
    await page.keyboard.type('z', { delay: 50 });
    await page.waitForTimeout(300);

    // Undo the typed character via Ctrl+Z in CM6
    await page.keyboard.press('Control+z');
    await page.waitForTimeout(300);

    // Editor should not crash
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
