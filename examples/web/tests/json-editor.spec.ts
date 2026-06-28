// JSON structural editor — foundation + ad-hoc invariant tests.
// Tests the editor's contract: parse → tree → toolbar → structural edits.
// Uses built-in example presets to avoid text-sync timing issues.

import { test, expect, type Page } from '@playwright/test';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Load an example preset and wait for tree nodes to render. */
async function loadExample(page: Page, name: string) {
  await page.locator(`.example-btn:has-text("${name}")`).click();
  await expect(page.locator('.node-row').first()).toBeVisible();
}

/** Count tree nodes currently rendered. */
async function treeNodeCount(page: Page): Promise<number> {
  return page.locator('.node-row').count();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

let pageErrors: Error[];

test.beforeEach(async ({ page }) => {
  pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error));
  await page.goto('/json.html');
  await expect(page.locator('.node-row').first()).toBeVisible();
});

test.describe('JSON Editor — Foundation', () => {

  test('page loads without errors', async () => {
    expect(pageErrors).toEqual([]);
  });

  test('editor and tree view visible', async ({ page }) => {
    await expect(page.locator('#json-input')).toBeVisible();
    await expect(page.locator('#tree-view')).toBeVisible();
  });

  test('default JSON renders tree', async ({ page }) => {
    const count = await treeNodeCount(page);
    expect(count).toBeGreaterThan(0);
  });

  test('example buttons populate editor and tree', async ({ page }) => {
    const examples = ['Simple', 'Object', 'Array', 'Nested'];
    for (const name of examples) {
      await loadExample(page, name);
      const text = await page.locator('#json-input').textContent();
      expect(text!.trim().length).toBeGreaterThan(0);
      const count = await treeNodeCount(page);
      expect(count).toBeGreaterThan(0);
    }
  });

  test('valid JSON shows no parse errors', async ({ page }) => {
    await loadExample(page, 'Object');
    expect(await page.locator('#parse-errors .error-item').count()).toBe(0);
  });

});

test.describe('JSON Editor — Ad-hoc', () => {

  test('tree node selection and toolbar state', async ({ page }) => {
    // Load Object example — root is an object
    await loadExample(page, 'Object');
    const firstNode = page.locator('.node-row').first();
    await firstNode.click();
    await expect(firstNode).toHaveClass(/selected/);

    // Object root: + Member should be enabled
    await expect(page.locator('#add-member-btn')).not.toBeDisabled();

    // Load Array example — root is an array
    await loadExample(page, 'Array');
    await page.locator('.node-row').first().click();
    await expect(page.locator('.node-row').first()).toHaveClass(/selected/);

    // Array root: + Element should be enabled
    await expect(page.locator('#add-element-btn')).not.toBeDisabled();
  });

  test('structural edit round-trips through text', async ({ page }) => {
    await loadExample(page, 'Array');
    const countBefore = await treeNodeCount(page);
    const textBefore = await page.locator('#json-input').textContent();

    // Select array root and add element
    await page.locator('.node-row').first().click();
    await page.locator('#add-element-btn').click();

    // Tree should have more nodes
    await expect(page.locator('.node-row')).toHaveCount(countBefore + 1, { timeout: 5000 });

    // Text should have changed
    const textAfter = await page.locator('#json-input').textContent();
    expect(textAfter).not.toBe(textBefore);
  });

  test('inline form lifecycle', async ({ page }) => {
    // Load Object example and select root
    await loadExample(page, 'Object');
    await page.locator('.node-row').first().click();

    // Click + Member — inline form appears
    await page.locator('#add-member-btn').click();
    await expect(page.locator('#toolbar-inline-form')).toBeVisible();

    // Fill key and submit
    const countBefore = await treeNodeCount(page);
    await page.locator('#toolbar-inline-input').fill('newkey');
    await page.locator('#toolbar-inline-submit').click();

    // Form hides, tree gains a member
    await expect(page.locator('#toolbar-inline-form')).not.toBeVisible();
    await expect(page.locator('.node-row')).toHaveCount(countBefore + 1, { timeout: 5000 });

    // Open form again, cancel with Escape
    await page.locator('.node-row').first().click();
    await page.locator('#add-member-btn').click();
    await expect(page.locator('#toolbar-inline-form')).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.locator('#toolbar-inline-form')).not.toBeVisible();

    // Node count unchanged after cancel
    await expect(page.locator('.node-row')).toHaveCount(countBefore + 1);
  });

  test('parse error lifecycle', async ({ page }) => {
    const editor = page.locator('#json-input');

    // Clear editor and type broken JSON
    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{bad');

    // Errors should appear
    await expect(page.locator('#parse-errors .error-item').first()).toBeVisible();

    // Fix the input
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{"ok": 1}');

    // Errors should clear
    await expect(page.locator('#parse-errors .error-item')).toHaveCount(0);
  });

  test('example switching resets state', async ({ page }) => {
    // Load Object, perform an edit
    await loadExample(page, 'Object');
    await page.locator('.node-row').first().click();
    await page.locator('#add-member-btn').click();
    await page.locator('#toolbar-inline-input').fill('extra');
    await page.locator('#toolbar-inline-submit').click();
    await expect(page.locator('#toolbar-inline-form')).not.toBeVisible();

    const editedText = await page.locator('#json-input').textContent();

    // Switch to Array example
    await loadExample(page, 'Array');
    const arrayText = await page.locator('#json-input').textContent();

    // Should reflect Array example, not edited Object
    expect(arrayText).not.toBe(editedText);
    expect(arrayText).toContain('alpha');
  });

});

test.describe('JSON Editor — Role Spans', () => {

  /** Read current role spans via Vite's module cache (same instance as the page). */
  async function roleSpans(page: Page): Promise<Array<{ start: number; end: number; role: string }>> {
    return page.evaluate(async () => {
      const mod = await import('/src/json-editor.ts');
      return mod.getJsonRoleSpans();
    });
  }

  test('simple object returns property-key and string-value spans', async ({ page }) => {
    await loadExample(page, 'Object');
    await expect.poll(async () => (await roleSpans(page)).length).toBeGreaterThanOrEqual(5);
    const spans = await roleSpans(page);
    expect(spans[0]).toMatchObject({ role: 'punctuation' });
    expect(spans.some(s => s.role === 'property-key')).toBe(true);
    expect(spans.some(s => s.role === 'string-value')).toBe(true);
  });

  test('array example contains number-literal and boolean-literal', async ({ page }) => {
    await loadExample(page, 'Array');
    await expect.poll(async () => {
      const s = await roleSpans(page);
      return s.some(s => s.role === 'number-literal') && s.some(s => s.role === 'boolean-literal') && s.some(s => s.role === 'null-literal');
    }).toBe(true);
  });

  test('decoration marks visible in overlay', async ({ page }) => {
    await loadExample(page, 'Object');
    const firstMark = page.locator('.decoration-overlay .decoration-mark').first();
    await expect(firstMark).toBeVisible();
    const bgColor = await firstMark.evaluate(el => getComputedStyle(el).backgroundColor);
    // Completely transparent is rgba(0, 0, 0, 0); role classes set a visible background.
    expect(bgColor).not.toBe('rgba(0, 0, 0, 0)');
    const count = await page.locator('.decoration-overlay .decoration-mark').count();
    expect(count).toBeGreaterThan(0);
  });

  test('error input shows error decoration', async ({ page }) => {
    const editor = page.locator('#json-input');
    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{bad');
    await expect.poll(async () => (await roleSpans(page)).some(s => s.role === 'error')).toBe(true);
  });

  test('error role coexists with parser diagnostics', async ({ page }) => {
    const editor = page.locator('#json-input');
    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{"a" 1}');
    await expect.poll(async () => (await roleSpans(page)).some(s => s.role === 'error')).toBe(true);
    // Parser diagnostic also present
    const errors = page.locator('#parse-errors .error-item');
    await expect(errors.first()).toBeVisible();
  });

  test('fixing error clears error decorations', async ({ page }) => {
    const editor = page.locator('#json-input');
    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{bad');
    // Error should appear
    await expect.poll(async () => (await roleSpans(page)).some(s => s.role === 'error')).toBe(true);

    // Fix it
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{"ok": 1}');
    // Error should clear
    await expect.poll(async () => !(await roleSpans(page)).some(s => s.role === 'error')).toBe(true);
  });
});

test.describe('JSON Editor — Tree Rendering Regression', () => {

  test('P2: collapse state resets on example switch', async ({ page }) => {
    // Load Nested example and collapse the root
    await loadExample(page, 'Nested');
    const toggle = page.locator('.node-row >> .node-toggle').first();
    await expect(toggle).toBeVisible();
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-expanded', 'false');

    // Switch to Simple — collapse state must reset
    await loadExample(page, 'Simple');
    const toggles = page.locator('.node-row >> .node-toggle');
    const count = await toggles.count();
    for (let i = 0; i < count; i++) {
      await expect(toggles.nth(i)).toHaveAttribute('aria-expanded', 'true');
    }
  });

  test('P2: leaf parent gains container chrome on first child', async ({ page }) => {
    // Start with a scalar — type null, which renders as a leaf (.value-node)
    const editor = page.locator('#json-input');
    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.type('null');
    await expect(page.locator('.node-row').first()).toBeVisible();
    await page.waitForTimeout(300);

    // Select the null scalar root
    const rootRow = page.locator('.node-row').first();
    await rootRow.click();

    // Change type to Object
    const changeBtn = page.locator('#change-type-btn');
    await expect(changeBtn).not.toBeDisabled();
    await changeBtn.click();
    await page.locator('#toolbar-inline-input').fill('object');
    await page.locator('#toolbar-inline-submit').click();
    await page.waitForTimeout(300);

    // Add first member
    const addBtn = page.locator('#add-member-btn');
    await expect(addBtn).not.toBeDisabled();
    await addBtn.click();
    await page.locator('#toolbar-inline-input').fill('key');
    await page.locator('#toolbar-inline-submit').click();
    await page.waitForTimeout(300);

    // Parent must now have container chrome
    const rootNode = page.locator('.tree-node.root');
    await expect(rootNode.locator(':scope > .node-children')).toBeAttached();
    await expect(rootNode.locator(':scope > .node-row > .node-toggle')).toBeAttached();
    await expect(rootNode.locator(':scope > .node-row > .node-count')).toHaveText('1');
  });
});

test.describe('JSON Editor — Inline Controls', () => {

  test('row-level type dropdown switches value node type', async ({ page }) => {
    // Load Array — has string, number, bool, null values
    await loadExample(page, 'Array');

    // Click the first value node (second .node-row — first is the array root)
    const valueNode = page.locator('.node-row.value-node').first();
    await valueNode.click();
    await expect(valueNode).toHaveClass(/selected/);

    // The type dropdown ON the selected row should be visible
    const typeSelect = valueNode.locator('.node-type-select');
    await expect(typeSelect).toBeVisible();

    // Switch the type to bool
    await typeSelect.selectOption('bool');

    // The node should now display as a boolean type
    await expect(valueNode.locator('.node-tag.bool')).toBeVisible();
  });

  test('row-level delete button removes a child node', async ({ page }) => {
    await loadExample(page, 'Array');
    const countBefore = await treeNodeCount(page);

    // Select a child value node (index 1+)
    const childRow = page.locator('.node-row').nth(1);
    await childRow.click();

    // Click the row-level delete button within the selected row
    const deleteBtn = childRow.locator('.node-action-btn[data-action="delete"]');
    await expect(deleteBtn).toBeVisible();
    await deleteBtn.click();

    // Wait for tree to update
    await expect(page.locator('.node-row')).toHaveCount(countBefore - 1, { timeout: 5000 });
  });

  test('row-level add element adds to array root', async ({ page }) => {
    await loadExample(page, 'Array');
    const countBefore = await treeNodeCount(page);

    // Select the array root
    await page.locator('.node-row').first().click();

    // Click the row-level add button
    const addBtn = page.locator('.node-action-btn[data-action="add-element"]');
    await expect(addBtn).toBeVisible();
    await addBtn.click();

    // Should now have one more child node
    await expect(page.locator('.node-row')).toHaveCount(countBefore + 1, { timeout: 5000 });
  });

  test('type-switch from scalar to array shows container controls', async ({ page }) => {
    await loadExample(page, 'Array');

    // Select a child row (index 1 is the first value node)
    const childRow = page.locator('.node-row').nth(1);
    await childRow.click();

    // Verify it has a type dropdown (scalar controls)
    const typeSelect = childRow.locator('.node-type-select');
    await expect(typeSelect).toBeVisible();

    // Switch type from string to array
    await typeSelect.selectOption('array');

    // After re-render, select the same-position row (may not preserve selection)
    const newRow = page.locator('.node-row').nth(1);
    await newRow.click();

    // Container controls should now be visible
    await expect(newRow.locator('.node-action-btn[data-action="add-element"]')).toBeVisible({ timeout: 5000 });

    // The type dropdown should be gone (containers don't get the inline type select)
    await expect(newRow.locator('.node-type-select')).not.toBeVisible();
  });
});

test.describe('JSON Editor — Format', () => {

  test('format button pretty-prints compact JSON', async ({ page }) => {
    const editor = page.locator('#json-input');
    const formatBtn = page.locator('#format-btn');

    // Type compact JSON
    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{"a":[1,2],"b":{"c":3}}');
    await page.waitForTimeout(300);

    // Click Format
    await formatBtn.click();
    await page.waitForTimeout(300);

    // Text should be pretty-printed with newlines and indentation
    const text = await editor.textContent();
    expect(text).toContain('\n');
    expect(text).toContain('  "a"');
    expect(text).toContain('    ');
  });

  test('format button shows error on invalid JSON', async ({ page }) => {
    const editor = page.locator('#json-input');
    const formatBtn = page.locator('#format-btn');

    // Clear and type invalid JSON
    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{invalid');
    await page.waitForTimeout(300);

    // Capture text before format attempt
    const textBefore = await editor.textContent();

    // Click Format
    await formatBtn.click();
    await page.waitForTimeout(300);

    // Text must be unchanged (Format didn't apply)
    const textAfter = await editor.textContent();
    expect(textAfter).toBe(textBefore);

    // Error should be shown by the Format attempt (not just parser)
    await expect(page.locator('#parse-errors .error-item').first()).toBeVisible();
  });
});
