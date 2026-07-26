import { expect, test, type Page } from '@playwright/test';

const DEFAULT_HEADING = '# Hello World';

async function waitForMarkdownMount(page: Page): Promise<void> {
  await expect(page.locator('[data-markdown-ready]'))
    .toHaveAttribute('data-markdown-ready', 'true');
  await expect(page.locator('#block-container .block-text').first()).toBeVisible();
}

async function switchMode(
  page: Page,
  mode: 'Block' | 'Raw' | 'Preview',
): Promise<void> {
  await page.getByRole('button', { name: mode, exact: true }).click();
  const pane = mode === 'Block'
    ? '#block-pane'
    : mode === 'Raw'
      ? '#raw-pane'
      : '#preview-pane';
  await expect(page.locator(pane)).toBeVisible();
}

test('keeps the server-rendered Markdown controls inert without client JavaScript', async ({ browser }, testInfo) => {
  const baseURL = testInfo.project.use.baseURL;
  if (typeof baseURL !== 'string') throw new Error('Waku test baseURL is unavailable');
  const context = await browser.newContext({ baseURL, javaScriptEnabled: false });
  try {
    const page = await context.newPage();
    const response = await page.goto('/markdown');
    expect(response?.ok()).toBe(true);
    await expect(page.getByRole('heading', { name: '▱ Markdown Editor' })).toBeVisible();
    await expect(page.locator('[data-markdown-ready]')).toHaveAttribute('inert', '');
    await expect(page.locator('[data-markdown-ready]'))
      .toHaveAttribute('data-markdown-ready', 'false');
  } finally {
    await context.close();
  }
});

test('reports Markdown runtime load failures through the route error boundary', async ({ page }) => {
  const pageErrors: Error[] = [];
  let failedRuntimeRequests = 0;
  page.on('pageerror', (error) => pageErrors.push(error));
  await page.route(/crdt[-_]markdown/, (route) => {
    failedRuntimeRequests += 1;
    return route.abort('failed');
  });

  await page.goto('/markdown');

  await expect(page.getByRole('heading', {
    name: 'This demo could not be displayed',
  })).toBeFocused();
  expect(failedRuntimeRequests).toBeGreaterThan(0);
  await expect(page.locator('[data-imperative-demo-host="markdown"]')).toHaveCount(0);
  expect(pageErrors).toEqual([]);
});

test('restores document text and stable control focus while rebuilding mode state', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.getByRole('link', { name: /Markdown Editor/ }).click();
  await waitForMarkdownMount(page);
  await expect(page).toHaveURL(/\/markdown$/);
  await expect(page.getByRole('heading', { name: '▱ Markdown Editor' })).toBeFocused();

  const source = '# Route memory\n\nOnly document text returns.\n';
  await switchMode(page, 'Raw');
  await page.locator('#raw-editor').fill(source);
  await switchMode(page, 'Block');
  const previewTab = page.locator('[data-route-focus="mode-preview"]');
  await previewTab.focus();

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await page.goForward();
  await waitForMarkdownMount(page);

  await expect(page.locator('#block-pane')).toBeVisible();
  await expect(page.locator('#raw-pane')).toBeHidden();
  await expect(page.locator('.mode-tab.active')).toHaveText('Block');
  await expect(page.locator('.block-textarea')).toHaveCount(0);
  await expect(previewTab).toBeFocused();
  await switchMode(page, 'Raw');
  await expect(page.locator('#raw-editor')).toHaveValue(source);
});

test('falls back to the heading when the prior pane is rebuilt', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.getByRole('link', { name: /Markdown Editor/ }).click();
  await waitForMarkdownMount(page);
  await switchMode(page, 'Raw');
  const rawEditor = page.locator('#raw-editor');
  const source = '# Pending route snapshot\n\nCaptured before the frame.\n';
  await rawEditor.evaluate((editor: HTMLTextAreaElement, nextSource) => {
    const pendingFrameId = 2_147_481_999;
    const originalRequest = window.requestAnimationFrame;
    window.requestAnimationFrame = (() => pendingFrameId) as typeof window.requestAnimationFrame;
    editor.value = nextSource;
    editor.dispatchEvent(new InputEvent('input', {
      bubbles: true,
      data: nextSource,
      inputType: 'insertText',
    }));
    window.requestAnimationFrame = originalRequest;
  }, source);
  await expect(rawEditor).toBeFocused();

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await page.goForward();
  await waitForMarkdownMount(page);

  await expect(page.getByRole('heading', { name: '▱ Markdown Editor' })).toBeFocused();
  await expect(page.locator('#block-pane')).toBeVisible();
  await switchMode(page, 'Raw');
  await expect(rawEditor).toHaveValue(source);
});

test('reload clears route memory and reconstructs Markdown internals', async ({ page }) => {
  await page.goto('/markdown');
  await waitForMarkdownMount(page);
  await switchMode(page, 'Raw');
  await page.locator('#raw-editor').fill('# Transient\n');
  await switchMode(page, 'Preview');

  await page.reload();
  await waitForMarkdownMount(page);

  await expect(page.locator('#block-pane')).toBeVisible();
  await expect(page.locator('.mode-tab.active')).toHaveText('Block');
  await expect(page.locator('.block-textarea')).toHaveCount(0);
  await switchMode(page, 'Raw');
  await expect(page.locator('#raw-editor')).toHaveValue(new RegExp(DEFAULT_HEADING));
  await expect(page.locator('#raw-editor')).not.toHaveValue(/# Transient/);
});

test('repeated route cycles release listeners and pending frames', async ({ page }) => {
  const pageErrors: Error[] = [];
  page.on('pageerror', (error) => pageErrors.push(error));
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.evaluate(() => {
    const tracked = { keydown: 0, pointerup: 0 };
    const originalAdd = document.addEventListener.bind(document);
    document.addEventListener = ((
      type: string,
      listener: EventListenerOrEventListenerObject | null,
      options?: boolean | AddEventListenerOptions,
    ) => {
      if ((type !== 'keydown' && type !== 'pointerup') || listener === null) {
        originalAdd(type, listener, options);
        return;
      }
      const wrapped = (event: Event) => {
        tracked[type] += 1;
        if (typeof listener === 'function') listener.call(document, event);
        else listener.handleEvent(event);
      };
      originalAdd(type, wrapped, options);
    }) as typeof document.addEventListener;
    (window as Window & { __markdownListenerCalls?: typeof tracked })
      .__markdownListenerCalls = tracked;
  });

  for (let cycle = 0; cycle < 3; cycle += 1) {
    await page.getByRole('link', { name: /Markdown Editor/ }).click();
    await waitForMarkdownMount(page);
    await expect(page.locator('[data-imperative-demo-host="markdown"]')).toHaveCount(1);
    await expect(page.locator('.block-editor')).toHaveCount(1);
    await page.locator('#block-container .block').first().click();
    await expect(page.locator('.block-textarea')).toBeVisible();

    await page.goBack();
    await expect(page).toHaveURL(/\/$/);
    await expect(page.locator('[data-imperative-demo-host="markdown"]')).toHaveCount(0);
    const callsBefore = await page.evaluate(
      () => ({ ...(window as Window & {
        __markdownListenerCalls?: { keydown: number; pointerup: number };
      }).__markdownListenerCalls! }),
    );
    await page.evaluate(() => {
      document.dispatchEvent(new KeyboardEvent('keydown', { key: '1', ctrlKey: true }));
      document.dispatchEvent(new PointerEvent('pointerup'));
    });
    expect(await page.evaluate(
      () => (window as Window & {
        __markdownListenerCalls?: { keydown: number; pointerup: number };
      }).__markdownListenerCalls,
    )).toEqual(callsBefore);
  }

  await page.getByRole('link', { name: /Markdown Editor/ }).click();
  await waitForMarkdownMount(page);
  await switchMode(page, 'Raw');
  await page.evaluate(() => {
    const frameId = 2_147_482_000;
    const originalRequest = window.requestAnimationFrame;
    const originalCancel = window.cancelAnimationFrame;
    (window as Window & { __markdownCancelledFrames?: number[] })
      .__markdownCancelledFrames = [];
    window.requestAnimationFrame = (() => frameId) as typeof window.requestAnimationFrame;
    window.cancelAnimationFrame = ((candidate: number) => {
      if (candidate === frameId) {
        (window as Window & { __markdownCancelledFrames?: number[] })
          .__markdownCancelledFrames?.push(candidate);
        return;
      }
      originalCancel(candidate);
    }) as typeof window.cancelAnimationFrame;
    const editor = document.querySelector<HTMLTextAreaElement>('#raw-editor');
    if (editor === null) throw new Error('Raw editor is unavailable');
    editor.value = '# Pending frame';
    editor.dispatchEvent(new InputEvent('input', { bubbles: true }));
    window.requestAnimationFrame = originalRequest;
    window.history.back();
  });
  await expect(page).toHaveURL(/\/$/);
  expect(await page.evaluate(
    () => (window as Window & { __markdownCancelledFrames?: number[] })
      .__markdownCancelledFrames,
  )).toEqual([2_147_482_000]);
  expect(pageErrors).toEqual([]);
});
