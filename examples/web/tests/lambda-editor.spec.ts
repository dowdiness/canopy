// Lambda calculus editor — foundation invariant tests.
// Tests the editor's contract, not UI surface details.
// Uses built-in example presets to avoid text-sync timing issues.

import { test, expect, type Page } from '@playwright/test';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Load an example preset and wait for AST output to update. */
async function loadExample(page: Page, name: string) {
  await page.locator(`.example-btn:has-text("${name}")`).click();
  await expect(page.locator('#ast-output')).not.toContainText('Waiting for input...');
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

let pageErrors: Error[];

test.beforeEach(async ({ page }) => {
  pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error));
  await page.goto('/');
  await expect(page.locator('#status')).toContainText('Ready!');
});

test.describe('Lambda Editor — Foundation', () => {

  test('page loads without errors', async () => {
    expect(pageErrors).toEqual([]);
  });

  test('editor is visible and focusable', async ({ page }) => {
    const editor = page.locator('#editor');
    await expect(editor).toBeVisible();
    await expect(editor).toHaveAttribute('contenteditable', 'plaintext-only');
  });

  test('example buttons populate editor', async ({ page }) => {
    const examples = ['Basics', 'Composition', 'Currying', 'Conditional', 'Pipeline'];
    for (const name of examples) {
      await page.locator(`.example-btn:has-text("${name}")`).click();
      const text = await page.locator('#editor').textContent();
      expect(text!.trim().length).toBeGreaterThan(0);
    }
  });

  test('typing triggers AST graph', async ({ page }) => {
    const editor = page.locator('#editor');
    await editor.click();
    await page.keyboard.type('42');
    await expect(page.locator('#ast-graph svg')).toBeVisible();
  });

  test('pretty-print updates', async ({ page }) => {
    await loadExample(page, 'Basics');
    await expect(page.locator('#ast-output')).not.toContainText('Waiting for input...');
  });

  test('valid input shows no errors', async ({ page }) => {
    await loadExample(page, 'Basics');
    await expect(page.locator('#error-output')).toContainText('No errors');
    expect(await page.locator('#error-output .error-item').count()).toBe(0);
  });

});
