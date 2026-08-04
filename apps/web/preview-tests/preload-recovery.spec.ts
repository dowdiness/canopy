import { expect, test } from '@playwright/test';

const recoveryKey = 'canopy.preload-recovery.v1';

test('allows one preload recovery per route and leaves stable route errors', async ({ page }) => {
  const documentRequests = new Map<string, number>();
  page.on('request', (request) => {
    const url = new URL(request.url());
    if (request.isNavigationRequest()) {
      documentRequests.set(
        url.pathname,
        (documentRequests.get(url.pathname) ?? 0) + 1,
      );
    }
  });
  await page.route(/\/assets\/(?:crdt-(?:json|lambda)|graphviz)-/, (route) =>
    route.abort('failed'));

  await page.goto('/ml');

  const errorHeading = page.getByRole('heading', {
    name: 'This demo could not be displayed',
  });
  await expect(errorHeading).toBeFocused({ timeout: 15_000 });
  expect(documentRequests.get('/ml')).toBe(2);
  await page.waitForTimeout(11_000);
  expect(documentRequests.get('/ml')).toBe(2);
  await expect(errorHeading).toBeFocused();
  await expect(page.locator('[data-imperative-demo-host="lambda"]')).toHaveCount(0);

  await page.goto('/json');
  await expect(errorHeading).toBeFocused({ timeout: 15_000 });
  expect(documentRequests.get('/json')).toBe(2);
  await expect(page.locator('[data-imperative-demo-host="json"]')).toHaveCount(0);

  const mlRequestsBeforeReturn = documentRequests.get('/ml') ?? 0;
  await page.goto('/ml');
  await expect(errorHeading).toBeFocused({ timeout: 15_000 });
  await page.waitForTimeout(500);
  expect(documentRequests.get('/ml')).toBe(mlRequestsBeforeReturn + 1);
  expect(await page.evaluate((key) =>
    JSON.parse(sessionStorage.getItem(key) ?? '[]'), recoveryKey))
    .toEqual(['/ml', '/json']);
});
