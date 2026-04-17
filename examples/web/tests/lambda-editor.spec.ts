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

  test('example input parses successfully', async ({ page }) => {
    await loadExample(page, 'Basics');
    // Parsing succeeds → AST graph renders. The lambda language has no
    // type-annotation syntax, so the typechecker flags the unannotated
    // lambdas in this example — that behavior is covered by the
    // "typecheck error" test below; here we only verify parse success.
    await expect(page.locator('#ast-graph svg')).toBeVisible();
  });

  test('unbound variable shows eval warning', async ({ page }) => {
    const editor = page.locator('#editor');
    await editor.click();
    await page.keyboard.type('x');

    // "x" is an unbound variable — diagnostics panel should show a warning
    await expect(page.locator('#error-output .diag-item.diag-warning')).toBeVisible();
    await expect(page.locator('#error-output')).toContainText('unbound');
  });

  test('unbound variable produces typecheck error alongside warning', async ({ page }) => {
    const editor = page.locator('#editor');
    await editor.click();
    await page.keyboard.type('x + 1');

    await expect(page.locator('#error-output .diag-item.diag-error')).toBeVisible();
    await expect(page.locator('#error-output')).toContainText('unbound variable: x');
  });

  test('unannotated lambda produces typecheck error', async ({ page }) => {
    const editor = page.locator('#editor');
    await editor.click();
    await page.keyboard.type('\\x. x');

    await expect(page.locator('#error-output .diag-item.diag-error')).toBeVisible();
    await expect(page.locator('#error-output')).toContainText('missing type annotation');
  });

  test('well-typed expression shows no errors', async ({ page }) => {
    const editor = page.locator('#editor');
    await editor.click();
    await page.keyboard.type('1 + 2');

    await expect(page.locator('#error-output')).toContainText('No errors');
    expect(await page.locator('#error-output .diag-item').count()).toBe(0);
  });

  test('parse errors suppress type diagnostics', async ({ page }) => {
    // A bare backslash is a malformed lambda — the parser expects a variable
    // name and body after it, so the input fails to parse. Because the AST is
    // incomplete, get_diagnostics_json only emits parse errors and skips the
    // type-checker entirely (the suppression guard in canopy_lambda.mbt:170).
    const editor = page.locator('#editor');
    await editor.click();
    await page.keyboard.type('\\');

    await expect(page.locator('#error-output .diag-item.diag-error').first()).toBeVisible();
    await expect(page.locator('#error-output')).not.toContainText('missing type annotation');
    await expect(page.locator('#error-output')).not.toContainText('unbound variable');
  });

});
