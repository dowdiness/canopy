import { test, expect } from '@playwright/test';

// Boundary matrix: surviving selected node after reorder; removed selected node;
// undo/redo without grouping a setup edit; incidental publication while unfocused.
// Visible selection, Inspector, and the following Delete must agree.
test('selection survives a definition exchange and isolated Undo/Redo', async ({ page }) => {
  test.setTimeout(60000);
  const room = `selection-${Date.now()}`;
  await page.goto(`/#${room}`);
  const cm = page.locator('#canopy-text-editor .cm-content');
  await cm.click();
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.insertText('let x = 1\nlet y = 2\nx + y');
  await expect.poll(() => page.evaluate(key => localStorage.getItem(key), `canopy-doc-${room}`)).not.toBeNull();
  // Restore gives this test a fresh history, excluding the setup edit.
  await page.reload();
  await expect(cm).toContainText('let y = 2', { timeout: 20000 });
  await page.getByRole('button', { name: 'Structure', exact: true }).click();
  await page.locator('canopy-editor .structure-int_literal').nth(1).click();
  const inspector = page.getByLabel('Node inspector');
  await expect(inspector.locator('.inspector-value').nth(1)).toHaveText('2');
  await page.evaluate(() => {
    const root = document.querySelector('canopy-editor')!.shadowRoot!;
    const [source, target] = root.querySelectorAll<HTMLElement>('.structure-let_def');
    const dataTransfer = new DataTransfer();
    source.draggable = true;
    source.dispatchEvent(new DragEvent('dragstart', { dataTransfer, bubbles: true }));
    const rect = target.querySelector('.structure-header')!.getBoundingClientRect();
    target.dispatchEvent(new DragEvent('drop', {
      dataTransfer, bubbles: true, cancelable: true, clientX: rect.x + 5, clientY: rect.y + 5,
    }));
    source.dispatchEvent(new DragEvent('dragend', { dataTransfer, bubbles: true }));
  });
  await expect(page.locator('canopy-editor .structure-let_def > .structure-header .structure-label').first()).toHaveText('y');
  const selected = page.locator('canopy-editor .ProseMirror-selectednode');
  await expect(selected).toHaveText('INT2');
  await expect(inspector.locator('.inspector-value').nth(1)).toHaveText('2');
  await page.getByRole('button', { name: 'Undo', exact: true }).click();
  await expect(page.locator('canopy-editor .structure-let_def > .structure-header .structure-label').first()).toHaveText('x');
  await expect(selected).toHaveText('INT2');
  await expect(inspector.locator('.inspector-value').nth(1)).toHaveText('2');
  await expect(page.getByRole('button', { name: 'Undo', exact: true })).toBeFocused();
  await page.getByRole('button', { name: 'Redo', exact: true }).click();
  await expect(page.locator('canopy-editor .structure-let_def > .structure-header .structure-label').first()).toHaveText('y');
  await expect(selected).toHaveText('INT2');
  await expect(inspector.locator('.inspector-value').nth(1)).toHaveText('2');
  await expect(page.getByRole('button', { name: 'Redo', exact: true })).toBeFocused();
  // Focus the editor without a new click that could repair a stale selection.
  await page.locator('canopy-editor .ProseMirror').focus();
  await page.keyboard.press('Backspace');
  await expect(page.locator('canopy-editor .structure-int_literal').first()).toHaveText('INT0');
  await expect(selected).toHaveText('INT0');
  await expect(inspector.locator('.inspector-value').nth(1)).toHaveText('0');
});

test('mode reactivation preserves the application selection without stealing focus', async ({ page }) => {
  await page.goto('/');
  const structure = page.getByRole('button', { name: 'Structure', exact: true });
  await structure.click();
  await page.locator('canopy-editor .structure-int_literal').click();
  const label = page.getByLabel('Node inspector').locator('.inspector-value').nth(1);
  await expect(label).toHaveText('42');
  await page.getByRole('button', { name: 'Text', exact: true }).click();
  await structure.click();
  await expect(page.locator('canopy-editor .ProseMirror-selectednode')).toHaveText('INT42');
  await expect(label).toHaveText('42');
  await expect(structure).toBeFocused();
  // A Text-mode outline selection does not write the host's imperative cache.
  // Reactivation must read the application's current declarative selection.
  await page.getByRole('button', { name: 'Text', exact: true }).click();
  await page.getByRole('treeitem', { name: 'x', exact: true }).first().click();
  await expect(label).toHaveText('x');
  await structure.click();
  await expect(page.locator('canopy-editor .ProseMirror-selectednode')).toHaveText('VARx');
  await expect(label).toHaveText('x');
  await expect(structure).toBeFocused();
});

test('malformed selection events do not clear the current selection', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Structure', exact: true }).click();
  await page.locator('canopy-editor .structure-int_literal').click();
  const label = page.getByLabel('Node inspector').locator('.inspector-value').nth(1);
  await expect(label).toHaveText('42');
  await page.locator('canopy-editor').evaluate(async host => {
    for (const detail of [{ other: '42' }, { nodeId: null }, { nodeId: 'not-an-id' }]) {
      host.dispatchEvent(new CustomEvent('node-selected', { detail, bubbles: true }));
    }
    await new Promise<void>(resolve => requestAnimationFrame(() => resolve()));
  });
  await expect(label).toHaveText('42');
  await page.getByRole('button', { name: 'Text', exact: true }).click();
  await page.locator('canopy-editor').evaluate(async host => {
    host.dispatchEvent(new CustomEvent('node-selected', { detail: { nodeId: '' }, bubbles: true }));
    await new Promise<void>(resolve => requestAnimationFrame(() => resolve()));
  });
  await expect(label).toHaveText('42');
});

test('snapshot selection follows identity without stealing outside focus and reports removal', async ({ page }) => {
  await page.goto('/');
  const result = await page.evaluate(async () => {
    const { createStructureModeSession } = await import('/src/structure-runtime.ts');
    const host = document.createElement('div');
    const parent = host.appendChild(document.createElement('div'));
    const outside = document.createElement('button');
    outside.textContent = 'Outside editor';
    // Isolate selection-driven scrolling from normal page-height/scroll-anchor
    // changes when replacing the fixture's root with a smaller document.
    host.style.cssText = 'position:fixed;top:0;left:0;width:300px;height:300px;overflow:auto';
    outside.style.cssText = 'position:fixed;top:0;left:320px';
    document.body.append(host, outside);
    const selectedIds: string[] = [];
    host.addEventListener('node-selected', event => {
      event.stopPropagation(); // Fixture events belong to this host, not the app.
      selectedIds.push((event as CustomEvent).detail.nodeId);
    });
    const left = { node_id: 2, kind: ['Int', 1], children: [], start: 0, end: 1 };
    const right = { ...left, node_id: 3, kind: ['Int', 2] };
    const root = { ...left, node_id: 1, kind: ['Bop', '+'], children: [left, right] };
    const session = createStructureModeSession(parent, host, JSON.stringify(root));
    try {
      session.setSelectedNode('3');
      outside.focus();
      const scrollBefore = window.scrollY;
      session.reconcile(JSON.stringify({ ...root, children: [right, left] }));
      const moved = parent.querySelector('.ProseMirror-selectednode')?.textContent;
      const movedId = selectedIds.at(-1);
      // Replace the entire root: selected ID 3 is absent, so PM chooses a
      // fallback. That actual target must be reported rather than retaining 3.
      session.reconcile(JSON.stringify(left));
      const removed = parent.querySelector('.ProseMirror-selectednode')?.textContent;
      const removedId = selectedIds.at(-1);
      const publications = selectedIds.length;
      session.reconcile(JSON.stringify(left));
      session.reconcile('null');
      return {
        moved, movedId, removed, removedId,
        sameValueSilent: publications === selectedIds.length,
        outsideFocused: document.activeElement === outside,
        scrollUnchanged: window.scrollY === scrollBefore,
      };
    } finally {
      session.destroy();
      host.remove();
      outside.remove();
    }
  });
  expect(result).toEqual({
    moved: 'INT2', movedId: '3', removed: 'INT1', removedId: '2',
    sameValueSilent: true, outsideFocused: true, scrollUnchanged: true,
  });
});
