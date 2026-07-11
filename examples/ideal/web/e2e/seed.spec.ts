import { test, expect } from '@playwright/test';

test.describe('Ideal Editor - Seed', () => {
  test('should load the editor', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveTitle('Canopy Editor');
    await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
    await expect(page.getByRole('button', { name: 'Structure' })).toBeVisible();
  });

  test('should switch to Structure mode', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('button', { name: 'Structure' }).click();
    await expect(page.getByRole('button', { name: 'Structure' })).toHaveAttribute('aria-pressed', 'true');
    // The editor should show AST structure blocks
    await expect(page.getByLabel('Code editor')).toBeVisible();
  });

  test('should load example and show AST', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('button', { name: 'Basics' }).click();
    await page.getByRole('button', { name: 'Structure' }).click();
    // Outline should show the AST
    await expect(page.getByLabel('AST outline')).toBeVisible();
  });
});
