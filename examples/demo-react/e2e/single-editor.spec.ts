import { test, expect } from '@playwright/test';

test.describe('Single Editor Mode', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('should load the page with correct title', async ({ page }) => {
    await expect(page).toHaveTitle('Lambda CRDT Editor - React + EditorProtocol Demo');
  });

  test('should display Single Editor mode by default', async ({ page }) => {
    await expect(page.getByRole('button', { name: 'Single Editor' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Collaborative Demo' })).toBeVisible();
    await expect(page.getByPlaceholder(/Type lambda calculus/)).toBeVisible();
  });

  test('should have disabled undo/redo buttons initially', async ({ page }) => {
    await expect(page.getByRole('button', { name: 'Undo' })).toBeDisabled();
    await expect(page.getByRole('button', { name: 'Redo' })).toBeDisabled();
  });

  test('should insert Identity example when clicking button', async ({ page }) => {
    await page.getByRole('button', { name: 'Identity' }).click();

    const textarea = page.getByPlaceholder(/Type lambda calculus/);
    await expect(textarea).toHaveValue('((x) => x) 42');
  });

  test('should insert Church 2 example', async ({ page }) => {
    await page.getByRole('button', { name: 'Church 2' }).click();

    const textarea = page.getByPlaceholder(/Type lambda calculus/);
    await expect(textarea).toHaveValue('((f, x) => f (f x)) ((n) => n + 1) 0');
  });

  test('should insert Add example', async ({ page }) => {
    await page.getByRole('button', { name: 'Add' }).click();

    const textarea = page.getByPlaceholder(/Type lambda calculus/);
    await expect(textarea).toHaveValue('((x, y) => x + y) 10 5');
  });

  test('should insert Conditional example', async ({ page }) => {
    await page.getByRole('button', { name: 'Conditional' }).click();

    const textarea = page.getByPlaceholder(/Type lambda calculus/);
    await expect(textarea).toHaveValue('if 1 then 42 else 0');
  });

  test('should insert Apply example', async ({ page }) => {
    await page.getByRole('button', { name: 'Apply' }).click();

    const textarea = page.getByPlaceholder(/Type lambda calculus/);
    await expect(textarea).toHaveValue('((f, x) => f x) ((n) => n - 1) 10');
  });

  test('should update character count when typing', async ({ page }) => {
    const textarea = page.getByPlaceholder(/Type lambda calculus/);
    await textarea.fill('Hello');

    // Check char count display updates - use status-value next to Chars label
    await expect(page.locator('.status-item').filter({ hasText: 'Chars:' }).locator('.status-value')).toContainText('5');
  });

  test('should clear editor when clicking Clear button', async ({ page }) => {
    const textarea = page.getByPlaceholder(/Type lambda calculus/);
    await textarea.fill('Some text');

    await page.getByRole('button', { name: 'Clear' }).click();

    await expect(textarea).toHaveValue('');
  });

  test('should enable undo button after typing', async ({ page }) => {
    const textarea = page.getByPlaceholder(/Type lambda calculus/);
    await textarea.pressSequentially('Hi');

    // Wait for undo to be enabled
    await expect(page.getByRole('button', { name: 'Undo' })).toBeEnabled();
  });

  test('should switch to Collaborative Demo mode', async ({ page }) => {
    await page.getByRole('button', { name: 'Collaborative Demo' }).click();

    await expect(page.getByRole('heading', { name: 'Per-Agent Undo/Redo Demo' })).toBeVisible();
    await expect(page.locator('.panel-title').filter({ hasText: 'Alice' })).toBeVisible();
    await expect(page.locator('.panel-title').filter({ hasText: 'Bob' })).toBeVisible();
  });
});
