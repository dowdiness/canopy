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
});
