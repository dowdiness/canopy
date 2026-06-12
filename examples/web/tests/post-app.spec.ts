import { test, expect } from '@playwright/test';

test.beforeEach(async ({ page }) => {
  await page.goto('/posts.html');
  await expect(page.getByRole('heading', { name: 'Post to yourself.' })).toBeVisible();
});

test.describe('local-first post app', () => {
  test('posts text with the button and keeps it after reload', async ({ page }) => {
    const input = page.getByLabel('Write');

    await input.fill('Remember the product wedge: post exists before retrieval.');
    await page.getByRole('button', { name: 'Post' }).click();

    await expect(input).toHaveValue('');
    await expect(page.locator('.post-item p')).toHaveText([
      'Remember the product wedge: post exists before retrieval.',
    ]);
    await expect(page.locator('#post-count')).toHaveText('1 post');

    await page.reload();

    await expect(page.locator('.post-item p')).toHaveText([
      'Remember the product wedge: post exists before retrieval.',
    ]);
    await expect(page.locator('#post-count')).toHaveText('1 post');
  });

  test('Ctrl+Enter posts while plain Enter keeps writing', async ({ page }) => {
    const input = page.getByLabel('Write');

    await input.fill('First line');
    await input.press('Enter');
    await input.pressSequentially('Second line');

    await expect(input).toHaveValue('First line\nSecond line');
    await expect(page.locator('.post-item')).toHaveCount(0);

    await input.press('Control+Enter');

    await expect(page.locator('.post-item p')).toHaveText(['First line\nSecond line']);
    await expect(input).toHaveValue('');
  });

  test('shows the chronological fallback newest first', async ({ page }) => {
    const input = page.getByLabel('Write');

    await input.fill('Older post');
    await input.press('Control+Enter');
    await input.fill('Newer post');
    await input.press('Control+Enter');

    await expect(page.locator('.post-item p')).toHaveText([
      'Newer post',
      'Older post',
    ]);
  });
});
