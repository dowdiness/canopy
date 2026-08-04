import { expect, test, type Page } from '@playwright/test';

const DEFAULT_SOURCE = '{"hello": "world"}';

async function waitForJsonMount(page: Page): Promise<void> {
  await expect(page.locator('[data-json-ready]'))
    .toHaveAttribute('data-json-ready', 'true');
}

async function replaceSource(page: Page, source: string): Promise<void> {
  await page.locator('#json-input').evaluate((editor, nextSource) => {
    editor.textContent = nextSource;
    editor.dispatchEvent(new InputEvent('input', {
      bubbles: true,
      data: nextSource,
      inputType: 'insertText',
    }));
  }, source);
  await expect.poll(
    () => page.evaluate(() => window.getJsonRoleSpans().length),
  ).toBeGreaterThan(0);
}

test('keeps the server-rendered JSON controls inert without client JavaScript', async ({ browser }, testInfo) => {
  const baseURL = testInfo.project.use.baseURL;
  if (typeof baseURL !== 'string') throw new Error('Waku test baseURL is unavailable');
  const context = await browser.newContext({ baseURL, javaScriptEnabled: false });
  try {
    const page = await context.newPage();
    const response = await page.goto('/json');
    expect(response?.ok()).toBe(true);
    await expect(page.locator('[data-json-ready]')).toHaveAttribute('inert', '');
    await expect(page.locator('[data-json-ready]'))
      .toHaveAttribute('data-json-ready', 'false');
  } finally {
    await context.close();
  }
});

test('reports runtime load failures through the route error boundary', async ({ page }) => {
  const pageErrors: Error[] = [];
  let failedRuntimeRequests = 0;
  page.on('pageerror', (error) => pageErrors.push(error));
  await page.route(/crdt[-_]json/, (route) => {
    failedRuntimeRequests += 1;
    return route.abort('failed');
  });

  await page.goto('/json');

  await expect(page.getByRole('heading', {
    name: 'This demo could not be displayed',
  })).toBeFocused();
  expect(failedRuntimeRequests).toBeGreaterThan(0);
  await expect(page.locator('[data-imperative-demo-host="json"]')).toHaveCount(0);
  expect(await page.evaluate(() => typeof window.getJsonRoleSpans)).toBe('undefined');
  expect(pageErrors).toEqual([]);
});

test('restores source and stable focus while rebuilding structure state', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.getByRole('link', { name: /JSON Editor/ }).click();
  await waitForJsonMount(page);
  await expect(page).toHaveURL(/\/json$/);
  await expect(page.getByRole('heading', { name: '{} JSON CRDT Editor' })).toBeFocused();

  const source = '{"nested":{"value":42}}';
  await replaceSource(page, source);
  const structureToggle = page.locator('#struct-toggle-btn');
  await structureToggle.click();
  const rootToggle = page.locator('#json-editor-view .node-toggle').first();
  await expect(rootToggle).toHaveText('▼');
  await rootToggle.click();
  await expect(rootToggle).toHaveText('▶');
  await structureToggle.focus();

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await page.goForward();
  await waitForJsonMount(page);

  await expect(page.locator('#json-input')).toHaveText(source);
  await expect(structureToggle).toHaveText('▦ Structured');
  await expect(structureToggle).toBeFocused();
  await expect(page.locator('#patch-log-count')).toHaveText('0');
  await structureToggle.click();
  await expect(rootToggle).toHaveText('▼');
});

test('reload clears route memory and reconstructs controller internals', async ({ page }) => {
  await page.goto('/json');
  await waitForJsonMount(page);
  await replaceSource(page, '{"transient":true}');
  await page.locator('#struct-toggle-btn').click();
  await page.locator('#json-editor-view .node-action-btn[data-action="add-member"]')
    .first()
    .click();
  await expect(page.locator('#patch-log-count')).not.toHaveText('0');

  await page.reload();
  await waitForJsonMount(page);

  await expect(page.locator('#json-input')).toHaveText(DEFAULT_SOURCE);
  await expect(page.locator('#json-input')).toBeVisible();
  await expect(page.locator('#struct-toggle-btn')).toHaveText('▦ Structured');
  await expect(page.locator('#patch-log-count')).toHaveText('0');
  await expect(page.locator('#json-editor-view')).toBeHidden();
});

test('repeated route cycles leave one surface and release hooks, overlays, and frames', async ({ page }) => {
  const pageErrors: Error[] = [];
  page.on('pageerror', (error) => pageErrors.push(error));
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');

  for (let cycle = 0; cycle < 3; cycle += 1) {
    await page.getByRole('link', { name: /JSON Editor/ }).click();
    await waitForJsonMount(page);
    await expect(page.locator('[data-imperative-demo-host="json"]')).toHaveCount(1);
    await expect(page.locator('.json-surface .decoration-overlay')).toHaveCount(1);
    expect(await page.evaluate(() => typeof window.getJsonRoleSpans)).toBe('function');

    await page.goBack();
    await expect(page).toHaveURL(/\/$/);
    await expect(page.locator('[data-imperative-demo-host="json"]')).toHaveCount(0);
    await expect(page.locator('.decoration-overlay')).toHaveCount(0);
    expect(await page.evaluate(() => typeof window.getJsonRoleSpans)).toBe('undefined');
  }

  await page.getByRole('link', { name: /JSON Editor/ }).click();
  await waitForJsonMount(page);
  await page.evaluate(() => {
    const frameIds = [2_147_483_000, 2_147_483_001];
    const originalRequest = window.requestAnimationFrame;
    const originalCancel = window.cancelAnimationFrame;
    let requestIndex = 0;
    (window as Window & { __jsonCancelledFrames?: number[] }).__jsonCancelledFrames = [];
    window.requestAnimationFrame = ((callback: FrameRequestCallback) => {
      if (requestIndex >= frameIds.length) return originalRequest(callback);
      const frameId = frameIds[requestIndex];
      requestIndex += 1;
      return frameId;
    }) as typeof window.requestAnimationFrame;
    window.cancelAnimationFrame = ((frameId: number) => {
      if (frameIds.includes(frameId)) {
        (window as Window & { __jsonCancelledFrames?: number[] })
          .__jsonCancelledFrames?.push(frameId);
        return;
      }
      originalCancel(frameId);
    }) as typeof window.cancelAnimationFrame;
    const editor = document.querySelector<HTMLElement>('#json-input');
    editor?.dispatchEvent(new InputEvent('input', { bubbles: true }));
    editor?.dispatchEvent(new Event('scroll'));
    window.history.back();
  });
  await expect(page).toHaveURL(/\/$/);
  expect(await page.evaluate(
    () => (window as Window & { __jsonCancelledFrames?: number[] })
      .__jsonCancelledFrames,
  )).toEqual([2_147_483_000, 2_147_483_001]);
  expect(pageErrors).toEqual([]);
});
