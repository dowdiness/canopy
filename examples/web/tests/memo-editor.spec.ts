import { test, expect } from '@playwright/test';

test.describe('Memo editor', () => {
  test('loads without errors and validates local input before calling the API', async ({ page }) => {
    const pageErrors: Error[] = [];
    page.on('pageerror', error => pageErrors.push(error));

    await page.goto('/memo.html');

    await expect(page.getByRole('heading', { name: 'Canopy Memo' })).toBeVisible();
    await expect(page.locator('#status')).toHaveText('Ready. Enter your API key and start typing.');

    await page.getByRole('button', { name: 'Fix Typos' }).click();
    await expect(page.locator('#status')).toHaveText('Please enter your Gemini API key.');

    await page.locator('#api-key').fill('local-test-key');
    await page.getByRole('button', { name: 'Fix Typos' }).click();
    await expect(page.locator('#status')).toHaveText('Nothing to process — textarea is empty.');

    await page.locator('#memo').fill('A local draft');
    await page.getByRole('button', { name: 'Edit' }).click();
    await expect(page.locator('#status')).toHaveText('Please enter an edit instruction.');
    await expect(page.locator('#instruction')).toBeFocused();
    expect(pageErrors).toEqual([]);
  });
});
