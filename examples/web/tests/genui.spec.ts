import { test, expect } from '@playwright/test';
import path from 'path';

test.describe('Generative UI Demo', () => {
  test('page loads and shows initial state', async ({ page }) => {
    await page.goto('/genui.html');
    await expect(page.locator('h1')).toHaveText('Generative UI');
    await expect(page.locator('#step-num')).toHaveText('—');
  });

  test('loads preset example', async ({ page }) => {
    await page.goto('/genui.html');
    await page.locator('button[data-example="0"]').click();
    const textarea = page.locator('#source-input');
    const val = await textarea.inputValue();
    expect(val.length).toBeGreaterThan(10);
    expect(val).toContain('div');
  });

  test('streaming completes and shows tree nodes', async ({ page }) => {
    test.setTimeout(60000); // streaming takes time

    await page.goto('/genui.html');
    await page.locator('button[data-example="0"]').click();
    await page.waitForTimeout(500);

    // Click stream button
    await page.locator('#stream-btn').click();

    // Wait for streaming to complete (status bar shows "complete")
    await expect(page.locator('#status-bar')).toContainText('complete', { timeout: 45000 });

    // Verify tree output has node elements
    const treeHtml = await page.locator('#tree-output').innerHTML();
    expect(treeHtml).toContain('node-id');
    expect(treeHtml).toContain('Root');
    expect(treeHtml).toContain('Element');
  });

  test('multiple examples work', async ({ page }) => {
    test.setTimeout(120000);

    await page.goto('/genui.html');

    for (let i = 0; i < 5; i++) {
      await page.locator(`button[data-example="${i}"]`).click();
      await page.waitForTimeout(300);
      await page.locator('#stream-btn').click();
      await expect(page.locator('#status-bar')).toContainText('complete', { timeout: 45000 });
      await page.waitForTimeout(500);
    }
  });
});
