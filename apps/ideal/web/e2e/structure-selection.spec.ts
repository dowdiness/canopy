import { test, expect, type Page } from '@playwright/test';

function inspectorLabel(page: Page) {
  return page.getByLabel('Node inspector').locator('.inspector-row')
    .filter({ has: page.getByText('Label', { exact: true }) }).locator('.inspector-value');
}

async function expectSelectedLeaf(page: Page, value: string) {
  await expect(page.locator('canopy-editor .ProseMirror-selectednode .structure-value')).toHaveText(value);
  await expect(inspectorLabel(page)).toHaveText(value);
}

test('Drop and history keep the same selection and Delete edits that target', async ({ page }) => {
  test.setTimeout(60000);
  const room = `selection-${Date.now()}`;
  await page.goto(`/#${room}`);
  const cm = page.locator('#canopy-text-editor .cm-content');
  await cm.click();
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.insertText('let x = 1\nlet y = 2\nx + y');
  await expect.poll(() => page.evaluate(key => localStorage.getItem(key), `canopy-doc-${room}`)).not.toBeNull();
  // Fresh history: the setup edit must not join the Drop's undo group.
  await page.reload();
  await expect(cm).toContainText('let y = 2', { timeout: 20000 });
  await page.getByRole('button', { name: 'Structure', exact: true }).click();
  await page.locator('canopy-editor .structure-int_literal').nth(1).click();
  await expectSelectedLeaf(page, '2');

  // Exercise the real drag handlers, including their view-owned attributes.
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
  const firstDefinition = page.locator('canopy-editor .structure-let_def > .structure-header .structure-label').first();
  await expect(firstDefinition).toHaveText('y');
  await expectSelectedLeaf(page, '2');
  for (const [operation, firstName] of [['Undo', 'x'], ['Redo', 'y']]) {
    const button = page.getByRole('button', { name: operation, exact: true });
    await button.click();
    await expect(firstDefinition).toHaveText(firstName);
    await expectSelectedLeaf(page, '2');
    await expect(button).toBeFocused();
  }
  // Focus without clicking: a fresh click could hide stale selection.
  await page.locator('canopy-editor .ProseMirror').focus();
  await page.keyboard.press('Backspace');
  await expectSelectedLeaf(page, '0');
  await expect(page.locator('canopy-editor .structure-int_literal').first().locator('.structure-value')).toHaveText('0');
});

for (const origin of ['Structure click', 'Text outline'] as const) {
  test(`mount restores ${origin} selection without taking focus`, async ({ page }) => {
    await page.goto('/');
    const structure = page.getByRole('button', { name: 'Structure', exact: true });
    if (origin === 'Structure click') {
      await structure.click();
      await page.locator('canopy-editor .structure-int_literal').click();
      await expectSelectedLeaf(page, '42');
      await page.getByRole('button', { name: 'Text', exact: true }).click();
    } else {
      await page.getByRole('treeitem', { name: '42', exact: true }).click();
    }
    await expect(inspectorLabel(page)).toHaveText('42');
    await structure.click();
    await expectSelectedLeaf(page, '42');
    await expect(structure).toBeFocused();
  });
}

test('malformed selection detail is ignored, but explicit deselection is delivered', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Structure', exact: true }).click();
  await page.locator('canopy-editor .structure-int_literal').click();
  await expectSelectedLeaf(page, '42');
  await page.locator('canopy-editor').evaluate(async host => {
    for (const detail of [{ other: '42' }, { nodeId: null }, { nodeId: 'not-an-id' }]) {
      host.dispatchEvent(new CustomEvent('node-selected', { detail, bubbles: true }));
    }
    await new Promise<void>(resolve => requestAnimationFrame(() => resolve()));
  });
  await expectSelectedLeaf(page, '42');
  await page.locator('canopy-editor').evaluate(host => {
    host.dispatchEvent(new CustomEvent('node-selected', { detail: { nodeId: '' }, bubbles: true }));
  });
  await expect(page.getByLabel('Node inspector')).toContainText('Click a node');
  // Inactive reports are tested at the application transition, not again here.
});

test('only a changed selection identity is reported, without focus or scroll', async ({ page }) => {
  await page.goto('/');
  const result = await page.evaluate(async () => {
    const { createStructureModeSession } = await import('/src/structure-runtime.ts');
    const host = document.body.appendChild(document.createElement('div'));
    const parent = host.appendChild(document.createElement('div'));
    const outside = document.body.appendChild(document.createElement('button'));
    const reported: string[] = [];
    host.addEventListener('node-selected', event => {
      event.stopPropagation(); // This session is independent of the application.
      reported.push((event as CustomEvent).detail.nodeId);
    });
    const original = { node_id: 1, kind: ['Int', 1], children: [], start: 0, end: 1 };
    const replacement = JSON.stringify({ ...original, node_id: 2, kind: ['Int', 2] });
    const session = createStructureModeSession(parent, host, JSON.stringify(original));
    try {
      outside.focus();
      const scroll = window.scrollY;
      // Content changed, but the selected identity is still 1: no new report.
      session.reconcile(JSON.stringify({ ...original, kind: ['Int', 2] }));
      session.reconcile(replacement); // ID 1 disappeared; PM selects ID 2.
      session.reconcile(replacement);
      session.reconcile('null');
      return {
        value: parent.querySelector('.ProseMirror-selectednode .structure-value')?.textContent,
        reported,
        focusKept: document.activeElement === outside,
        scrollKept: window.scrollY === scroll,
      };
    } finally {
      session.destroy();
      host.remove();
      outside.remove();
    }
  });
  expect(result.value).toBe('2');
  expect(result.reported).toEqual(['1', '2']);
  expect(result.focusKept).toBe(true);
  expect(result.scrollKept).toBe(true);
});
