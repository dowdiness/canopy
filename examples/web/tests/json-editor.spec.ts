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
    let prevCount = await treeNodeCount(page);

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
    await page.waitForTimeout(300);

    // Tree should have more nodes
    const countAfter = await treeNodeCount(page);
    expect(countAfter).toBeGreaterThan(countBefore);

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
    await page.waitForTimeout(300);

    // Form hides, tree gains a member
    await expect(page.locator('#toolbar-inline-form')).not.toBeVisible();
    const countAfter = await treeNodeCount(page);
    expect(countAfter).toBeGreaterThan(countBefore);

    // Open form again, cancel with Escape
    await page.locator('.node-row').first().click();
    await page.locator('#add-member-btn').click();
    await expect(page.locator('#toolbar-inline-form')).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.locator('#toolbar-inline-form')).not.toBeVisible();

    // Node count unchanged after cancel
    const countFinal = await treeNodeCount(page);
    expect(countFinal).toBe(countAfter);
  });

  test('parse error lifecycle', async ({ page }) => {
    const editor = page.locator('#json-input');

    // Clear editor and type broken JSON
    await editor.click();
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{bad');
    await page.waitForTimeout(300);

    // Errors should appear
    const errorCount = await page.locator('#parse-errors .error-item').count();
    expect(errorCount).toBeGreaterThan(0);

    // Fix the input
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.type('{"ok": 1}');
    await page.waitForTimeout(300);

    // Errors should clear
    expect(await page.locator('#parse-errors .error-item').count()).toBe(0);
  });

  test('example switching resets state', async ({ page }) => {
    // Load Object, perform an edit
    await loadExample(page, 'Object');
    await page.locator('.node-row').first().click();
    await page.locator('#add-member-btn').click();
    await page.locator('#toolbar-inline-input').fill('extra');
    await page.locator('#toolbar-inline-submit').click();
    await page.waitForTimeout(300);

    const editedText = await page.locator('#json-input').textContent();

    // Switch to Array example
    await loadExample(page, 'Array');
    const arrayText = await page.locator('#json-input').textContent();

    // Should reflect Array example, not edited Object
    expect(arrayText).not.toBe(editedText);
    expect(arrayText).toContain('alpha');
  });

});
