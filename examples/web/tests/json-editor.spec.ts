import { test, expect, type Page } from '@playwright/test';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Load an example preset and wait for the editor to update. */
async function loadExample(page: Page, name: string) {
  await page.locator(`.example-btn:has-text("${name}")`).click();
  await page.waitForTimeout(500);
}

/** Toggle to structured view. */
async function toggleStructured(page: Page) {
  await page.locator('#struct-toggle-btn').click();
  await expect(page.locator('#json-editor-view .node-row').first()).toBeVisible({ timeout: 5000 });
}

/** Count tree nodes in the structured view. */
async function treeNodeCount(page: Page): Promise<number> {
  return page.locator('#json-editor-view .node-row').count();
}

/** Get the currently active editor element. */
function editorArea(page: Page) {
  return page.locator('#json-input');
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

let pageErrors: Error[];

test.beforeEach(async ({ page }) => {
  pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error));
  await page.goto('/json.html');
});

// ---------------------------------------------------------------------------
// Foundation
// ---------------------------------------------------------------------------

test.describe('JSON Editor — Foundation', () => {

  test('page loads without errors', async () => {
    expect(pageErrors).toEqual([]);
  });

  test('editor visible in raw mode', async ({ page }) => {
    await expect(page.locator('#json-input')).toBeVisible();
  });

  test('toggle to structured shows tree', async ({ page }) => {
    await toggleStructured(page);
    const count = await treeNodeCount(page);
    expect(count).toBeGreaterThan(0);
  });

  test('example buttons populate editor', async ({ page }) => {
    for (const name of ['Simple', 'Object', 'Array', 'Nested']) {
      await loadExample(page, name);
      const text = await editorArea(page).textContent();
      expect(text!.trim().length).toBeGreaterThan(0);
    }
  });

  test('valid JSON shows no parse errors', async ({ page }) => {
    await loadExample(page, 'Object');
    await expect(page.locator('#errors-panel')).not.toBeVisible();
  });

});

// ---------------------------------------------------------------------------
// Editing — raw mode
// ---------------------------------------------------------------------------

test.describe('JSON Editor — Raw Mode', () => {

  test('parse error lifecycle', async ({ page }) => {
    const editor = editorArea(page);
    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{bad');

    // Errors should appear
    await expect(page.locator('#errors-panel')).toBeVisible();
    await expect(page.locator('#parse-errors .error-item').first()).toBeVisible();

    // Fix the input
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{"ok": 1}');

    // Errors should clear
    await expect(page.locator('#errors-panel')).not.toBeVisible({ timeout: 5000 });
  });

});

// ---------------------------------------------------------------------------
// Editing — structured mode
// ---------------------------------------------------------------------------

test.describe('JSON Editor — Structured Mode', () => {

  test('add member via row-level button', async ({ page }) => {
    await loadExample(page, 'Object');
    await toggleStructured(page);
    const countBefore = await treeNodeCount(page);

    // Click + button on the object root row
    await page.locator('#json-editor-view .node-action-btn[data-action="add-member"]').first().click();
    await page.waitForTimeout(500);

    const countAfter = await treeNodeCount(page);
    expect(countAfter).toBeGreaterThan(countBefore);
  });

  test('delete node via row-level button', async ({ page }) => {
    await loadExample(page, 'Array');
    await toggleStructured(page);
    const countBefore = await treeNodeCount(page);

    // Click × on a child row
    await page.locator('#json-editor-view .node-action-btn[data-action="delete"]').first().click();
    await page.waitForTimeout(500);

    const countAfter = await treeNodeCount(page);
    expect(countAfter).toBeLessThan(countBefore);
  });

  test('type dropdown switches value type', async ({ page }) => {
    await loadExample(page, 'Array');
    await toggleStructured(page);

    // The first child row should have a type select
    const row = page.locator('#json-editor-view .node-row').nth(1);
    const select = row.locator('.node-type-select');
    await expect(select).toBeVisible();

    // Switch type
    await select.selectOption('bool');

    // After re-render, the row should show bool tag
    await page.waitForTimeout(500);
    await expect(row.locator('.node-tag.bool')).toBeVisible();
  });

  test('collapse toggle persists across re-render', async ({ page }) => {
    await loadExample(page, 'Nested');
    await toggleStructured(page);

    // Collapse the root container
    const toggle = page.locator('#json-editor-view .node-toggle').first();
    await expect(toggle).toBeVisible();
    await toggle.click();
    await expect(toggle).toHaveText('▶');

    // Perform an edit that triggers re-render
    await page.locator('#json-editor-view .node-action-btn[data-action="add-member"]').first().click();
    await page.waitForTimeout(500);

    // Collapse state should persist
    await expect(toggle).toHaveText('▶');
  });

});

// ---------------------------------------------------------------------------
// Role Spans
// ---------------------------------------------------------------------------

test.describe('JSON Editor — Role Spans', () => {

  test('simple object returns property-key and string-value spans', async ({ page }) => {
    await loadExample(page, 'Object');
    await expect.poll(async () => (await windowGetRoleSpans(page)).length).toBeGreaterThanOrEqual(5);
    const spans = await windowGetRoleSpans(page);
    expect(spans[0]).toMatchObject({ role: 'punctuation' });
    expect(spans.some(s => s.role === 'property-key')).toBe(true);
    expect(spans.some(s => s.role === 'string-value')).toBe(true);
  });

  test('array example contains number-literal and boolean-literal', async ({ page }) => {
    await loadExample(page, 'Array');
    await expect.poll(async () => {
      const s = await windowGetRoleSpans(page);
      return s.some(s => s.role === 'number-literal') && s.some(s => s.role === 'boolean-literal') && s.some(s => s.role === 'null-literal');
    }).toBe(true);
  });

  test('decoration marks visible in overlay', async ({ page }) => {
    await loadExample(page, 'Object');
    const firstMark = page.locator('.decoration-overlay .decoration-mark').first();
    await expect(firstMark).toBeVisible();
    const bgColor = await firstMark.evaluate(el => getComputedStyle(el).backgroundColor);
    expect(bgColor).not.toBe('rgba(0, 0, 0, 0)');
    const count = await page.locator('.decoration-overlay .decoration-mark').count();
    expect(count).toBeGreaterThan(0);
  });

  test('error input shows error decoration', async ({ page }) => {
    const editor = editorArea(page);
    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{bad');
    await expect.poll(async () => (await windowGetRoleSpans(page)).some(s => s.role === 'error')).toBe(true);
  });

  test('error role coexists with parser diagnostics', async ({ page }) => {
    const editor = editorArea(page);
    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{"a" 1}');
    await expect.poll(async () => (await windowGetRoleSpans(page)).some(s => s.role === 'error')).toBe(true);
    await expect(page.locator('#errors-panel')).toBeVisible();
  });

  test('fixing error clears error decorations', async ({ page }) => {
    const editor = editorArea(page);
    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{bad');
    await expect.poll(async () => (await windowGetRoleSpans(page)).some(s => s.role === 'error')).toBe(true);

    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{"ok": 1}');
    await expect.poll(async () => !(await windowGetRoleSpans(page)).some(s => s.role === 'error')).toBe(true);
  });

});

// ---------------------------------------------------------------------------
// Format
// ---------------------------------------------------------------------------

test.describe('JSON Editor — Format', () => {

  test('format button pretty-prints compact JSON', async ({ page }) => {
    const editor = editorArea(page);
    const formatBtn = page.locator('#format-btn');

    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{"a":[1,2],"b":{"c":3}}');
    await page.waitForTimeout(300);

    await formatBtn.click();
    await page.waitForTimeout(300);

    const text = await editor.textContent();
    expect(text).toContain('\n');
    expect(text).toContain('  "a"');
  });

  test('format button shows error on invalid JSON', async ({ page }) => {
    const editor = editorArea(page);
    const formatBtn = page.locator('#format-btn');

    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{invalid');
    await page.waitForTimeout(300);

    const textBefore = await editor.textContent();

    await formatBtn.click();
    await page.waitForTimeout(300);

    const textAfter = await editor.textContent();
    expect(textAfter).toBe(textBefore);
    await expect(page.locator('#errors-panel')).toBeVisible();
  });

});

// ---------------------------------------------------------------------------
// Helpers (internal)
// ---------------------------------------------------------------------------

async function windowGetRoleSpans(page: Page): Promise<Array<{ start: number; end: number; role: string }>> {
  return page.evaluate(() => window.getJsonRoleSpans());
}
