import { readFile } from 'node:fs/promises';
import { expect, test } from '@playwright/test';

const FORBIDDEN_PROVIDER_MARKERS = [
  '127.0.0.1:11434',
  'GENUI_OLLAMA_MODEL',
  '/api/genui-feasibility',
  'promptTokens',
  'outputTokens',
] as const;

test('replays the recorded control without exposing the local study runner', async ({ page, request }) => {
  await page.goto('/genui.html');

  await expect(page.getByRole('button', { name: 'Run recorded candidate' })).toBeVisible();
  await expect(page.locator('#feasibility-live-panel')).toHaveCount(0);
  await page.getByRole('button', { name: 'Run recorded candidate' }).click();
  await expect(page.locator('#feasibility-classification')).toHaveText('success');
  await expect(page.locator('#feasibility-preview')).toContainText('Pending orders requiring attention');

  const response = await request.post('/api/genui-feasibility', {
    data: {
      studyId: 'genui-local-v1',
      runCapability: 'not-available-in-production',
      caseId: 'orders-pending-attention',
      slotId: 0,
    },
  });
  expect(response.status()).toBe(404);
});

test('production JavaScript assets omit every local provider marker', async ({ request }) => {
  const developmentSource = await readFile(new URL('../src/features/genui/browser/mount.js', import.meta.url), 'utf8');
  expect(developmentSource).toContain('/api/genui-feasibility');

  const documentResponse = await request.get('/genui.html');
  expect(documentResponse.ok()).toBe(true);
  const html = await documentResponse.text();
  const assetPaths = [
    ...html.matchAll(/<script\b[^>]*\bsrc=["']([^"']+\.js(?:\?[^"']*)?)["'][^>]*>/g),
  ].map((match) => match[1]);
  expect(assetPaths.length).toBeGreaterThan(0);

  for (const assetPath of assetPaths) {
    const assetResponse = await request.get(assetPath);
    expect(assetResponse.ok()).toBe(true);
    const source = await assetResponse.text();
    for (const marker of FORBIDDEN_PROVIDER_MARKERS) {
      expect(source, `${assetPath} contains ${marker}`).not.toContain(marker);
    }
  }
});
