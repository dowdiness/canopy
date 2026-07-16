import { expect, test } from '@playwright/test';

test('hides the local-only spike and omits its production endpoint', async ({ page, request }) => {
  await page.goto('/genui.html');

  await expect(page.locator('#genui-spike')).toBeHidden();
  await expect(page.locator('#data-generate-candidate')).toBeVisible();

  const response = await request.post('/api/genui-spike', {
    data: { caseId: 'orders-pending-attention' },
  });
  expect(response.status()).toBe(404);
});
