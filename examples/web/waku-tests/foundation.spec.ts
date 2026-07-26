import { expect, test } from '@playwright/test';

const expectedModuleIds = [
  '@moonbit/crdt-lambda',
  '@moonbit/crdt-json',
  '@moonbit/crdt-markdown',
  '@moonbit/crdt-jsx',
  '@moonbit/graphviz',
];

test('loads every generated module only through the Waku client probe', async ({ page }) => {
  const response = await page.goto('/');
  expect(response?.status()).toBe(200);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Canopy Waku foundation');

  const probe = page.locator('[data-moonbit-client-probe]');
  await expect(probe).toHaveAttribute('data-moonbit-client-probe', 'ready');
  await expect(probe.locator('[data-module-id]')).toHaveCount(expectedModuleIds.length);
  await expect(probe.locator('[data-module-id]')).toHaveText(expectedModuleIds);
});
