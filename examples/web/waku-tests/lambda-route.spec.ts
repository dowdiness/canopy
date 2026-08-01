import { expect, test, type Page } from '@playwright/test';

async function waitForLambdaMount(page: Page): Promise<void> {
  await expect(page.locator('[data-lambda-ready]'))
    .toHaveAttribute('data-lambda-ready', 'true');
  await expect(page.locator('#status')).toContainText('Ready!');
}

async function replaceSource(page: Page, source: string): Promise<void> {
  await page.locator('#editor').evaluate((editor, nextSource) => {
    editor.textContent = nextSource;
    editor.dispatchEvent(new InputEvent('input', {
      bubbles: true,
      data: nextSource,
      inputType: 'insertText',
    }));
  }, source);
  await expect(page.locator('#ast-graph svg')).toBeVisible();
}

test('keeps the server-rendered Mini-ML controls inert without client JavaScript', async ({ browser }, testInfo) => {
  const baseURL = testInfo.project.use.baseURL;
  if (typeof baseURL !== 'string') throw new Error('Waku test baseURL is unavailable');
  const context = await browser.newContext({ baseURL, javaScriptEnabled: false });
  try {
    const page = await context.newPage();
    const response = await page.goto('/ml');
    expect(response?.ok()).toBe(true);
    await expect(page.getByRole('heading', { name: 'Mini-ML CRDT Editor' })).toBeVisible();
    await expect(page.locator('[data-lambda-ready]')).toHaveAttribute('inert', '');
    await expect(page.locator('[data-lambda-ready]'))
      .toHaveAttribute('data-lambda-ready', 'false');
  } finally {
    await context.close();
  }
});

test('reports Mini-ML runtime load failures through the route error boundary', async ({ page }) => {
  const pageErrors: Error[] = [];
  let failedRuntimeRequests = 0;
  page.on('pageerror', (error) => pageErrors.push(error));
  await page.route(/crdt[-_]lambda|graphviz/, (route) => {
    failedRuntimeRequests += 1;
    return route.abort('failed');
  });

  await page.goto('/ml');

  await expect(page.getByRole('heading', {
    name: 'This demo could not be displayed',
  })).toBeFocused();
  expect(failedRuntimeRequests).toBeGreaterThan(0);
  await expect(page.locator('[data-imperative-demo-host="lambda"]')).toHaveCount(0);
  await expect(page.locator('.decoration-overlay')).toHaveCount(0);
  expect(pageErrors).toEqual([]);
});

test('restores only source and stable editor focus while rebuilding derived state', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.getByRole('link', { name: /Mini-ML Editor/ }).click();
  await waitForLambdaMount(page);
  await expect(page.getByRole('heading', { name: 'Mini-ML CRDT Editor' })).toBeFocused();

  const firstAgent = await page.locator('#status').textContent();
  const source = 'fn identity(x : Int) { x }\nidentity 42';
  await replaceSource(page, source);
  await page.locator('#editor').focus();

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await page.goForward();
  await waitForLambdaMount(page);

  await expect(page.locator('#editor')).toHaveText(source);
  await expect(page.locator('#editor')).toBeFocused();
  await expect(page.locator('#ast-graph svg')).toBeVisible();
  await expect(page.locator('#ast-output')).not.toContainText('Waiting for input...');
  expect(await page.locator('#status').textContent()).not.toBe(firstAgent);
});

test('reload clears Mini-ML route memory and creates a fresh editor', async ({ page }) => {
  await page.goto('/ml');
  await waitForLambdaMount(page);
  const firstAgent = await page.locator('#status').textContent();
  await replaceSource(page, '1 + 2');

  await page.reload();
  await waitForLambdaMount(page);

  await expect(page.locator('#editor')).toHaveText('');
  await expect(page.locator('#ast-output')).toContainText('Waiting for input...');
  expect(await page.locator('#status').textContent()).not.toBe(firstAgent);
});

test('repeated route cycles release the surface, overlay, frame, and timer', async ({ page }) => {
  const pageErrors: Error[] = [];
  page.on('pageerror', (error) => pageErrors.push(error));
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');

  for (let cycle = 0; cycle < 3; cycle += 1) {
    await page.getByRole('link', { name: /Mini-ML Editor/ }).click();
    await waitForLambdaMount(page);
    await expect(page.locator('[data-imperative-demo-host="lambda"]')).toHaveCount(1);
    await expect(page.locator('.lambda-surface .decoration-overlay')).toHaveCount(1);
    await page.goBack();
    await expect(page).toHaveURL(/\/$/);
    await expect(page.locator('[data-imperative-demo-host="lambda"]')).toHaveCount(0);
    await expect(page.locator('.decoration-overlay')).toHaveCount(0);
  }

  await page.getByRole('link', { name: /Mini-ML Editor/ }).click();
  await waitForLambdaMount(page);
  await page.evaluate(() => {
    const frameId = 2_147_480_100;
    const originalRequest = window.requestAnimationFrame;
    const originalCancel = window.cancelAnimationFrame;
    const state = { cancelledFrames: [] as number[] };
    (window as Window & { __lambdaReleaseState?: typeof state }).__lambdaReleaseState = state;
    window.requestAnimationFrame = (() => frameId) as typeof window.requestAnimationFrame;
    window.cancelAnimationFrame = ((candidate: number) => {
      if (candidate === frameId) state.cancelledFrames.push(candidate);
      else originalCancel(candidate);
    }) as typeof window.cancelAnimationFrame;
    const editor = document.querySelector<HTMLElement>('#editor');
    editor?.dispatchEvent(new InputEvent('input', { bubbles: true }));
    window.requestAnimationFrame = originalRequest;
    window.history.back();
  });
  await expect(page).toHaveURL(/\/$/);
  expect(await page.evaluate(
    () => (window as Window & { __lambdaReleaseState?: {
      cancelledFrames: number[];
    } }).__lambdaReleaseState,
  )).toEqual({
    cancelledFrames: [2_147_480_100],
  });

  await page.getByRole('link', { name: /Mini-ML Editor/ }).click();
  await waitForLambdaMount(page);
  await page.evaluate(() => {
    const timerId = 2_147_480_101;
    const originalSetTimeout = window.setTimeout;
    const originalClearTimeout = window.clearTimeout;
    const state = { scheduled: false, clearedTimers: [] as number[] };
    (window as Window & { __lambdaTimerState?: typeof state }).__lambdaTimerState = state;
    (window as Window & { __restoreLambdaTimers?: () => void }).__restoreLambdaTimers = () => {
      window.setTimeout = originalSetTimeout;
      window.clearTimeout = originalClearTimeout;
    };
    window.setTimeout = ((handler: TimerHandler, timeout?: number, ...args: unknown[]) => {
      if (timeout === 150) {
        state.scheduled = true;
        return timerId;
      }
      return originalSetTimeout(handler, timeout, ...args);
    }) as typeof window.setTimeout;
    window.clearTimeout = ((candidate: number) => {
      if (candidate === timerId) state.clearedTimers.push(candidate);
      else originalClearTimeout(candidate);
    }) as typeof window.clearTimeout;
    const editor = document.querySelector<HTMLElement>('#editor');
    if (editor === null) throw new Error('Mini-ML editor is unavailable');
    editor.textContent = '1';
    editor.dispatchEvent(new InputEvent('input', { bubbles: true }));
  });
  await expect.poll(() => page.evaluate(
    () => (window as Window & { __lambdaTimerState?: { scheduled: boolean } })
      .__lambdaTimerState?.scheduled,
  )).toBe(true);
  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  expect(await page.evaluate(
    () => (window as Window & { __lambdaTimerState?: { clearedTimers: number[] } })
      .__lambdaTimerState?.clearedTimers,
  )).toEqual([2_147_480_101]);
  await page.evaluate(() => {
    (window as Window & { __restoreLambdaTimers?: () => void })
      .__restoreLambdaTimers?.();
  });

  expect(pageErrors).toEqual([]);
});

test('aborts an in-flight development AST Grep request on route exit', async ({ page }) => {
  const pageErrors: Error[] = [];
  page.on('pageerror', (error) => pageErrors.push(error));
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.getByRole('link', { name: /Mini-ML Editor/ }).click();
  await waitForLambdaMount(page);
  await page.evaluate(() => {
    const originalFetch = window.fetch.bind(window);
    const state = { started: false, aborted: false };
    (window as Window & { __lambdaRequestState?: typeof state }).__lambdaRequestState = state;
    window.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
      const url = input instanceof Request ? input.url : String(input);
      if (!url.endsWith('/api/ast-grep')) return originalFetch(input, init);
      state.started = true;
      return new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => {
          state.aborted = true;
          reject(new DOMException('Aborted', 'AbortError'));
        }, { once: true });
      });
    }) as typeof window.fetch;
  });
  await replaceSource(page, 'fn pending(x : Int) { x }');
  await expect.poll(() => page.evaluate(
    () => (window as Window & { __lambdaRequestState?: { started: boolean } })
      .__lambdaRequestState?.started,
  )).toBe(true);
  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  expect(await page.evaluate(
    () => (window as Window & { __lambdaRequestState?: { aborted: boolean } })
      .__lambdaRequestState?.aborted,
  )).toBe(true);
  expect(pageErrors).toEqual([]);
});

test('lists structural matches, jumps to utf16 ranges, and removes stale results', async ({ page }) => {
  const source = '😀\nfn alpha(x : Int) {\n  x\n}\nfn beta(y : Int) { y }';
  let requestCount = 0;
  let releaseSecondResponse: (() => void) | undefined;
  let markSecondRequestStarted: (() => void) | undefined;
  const secondResponseGate = new Promise<void>((resolve) => {
    releaseSecondResponse = resolve;
  });
  const secondRequestStarted = new Promise<void>((resolve) => {
    markSecondRequestStarted = resolve;
  });
  await page.route('**/api/ast-grep', async (route) => {
    requestCount += 1;
    if (requestCount > 1) {
      markSecondRequestStarted?.();
      await secondResponseGate;
    }
    await route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        matches: requestCount === 1
          ? [
              { byte_start: 5, byte_end: 30, pattern_id: 'moonbit-fn-def' },
              { byte_start: 31, byte_end: 53, pattern_id: 'moonbit-fn-def' },
            ]
          : [],
      }),
    });
  });

  await page.goto('/ml');
  await waitForLambdaMount(page);
  await replaceSource(page, source);

  const results = page.locator('#structural-search-results button');
  await expect(results).toHaveCount(2);
  await expect(results.first()).toContainText('L2');
  await expect(results.first().locator('code')).toHaveText('fn alpha(x : Int) {');
  await results.nth(1).click();
  await expect(page.locator('#editor')).toBeFocused();
  await expect.poll(() => page.evaluate(
    () => window.getSelection()?.toString(),
  )).toBe('fn beta(y : Int) { y }');

  await replaceSource(page, `${source} `);
  await expect(results).toHaveCount(0);
  await expect(page.locator('#structural-search-status')).toHaveText('Searching…');
  await secondRequestStarted;
  releaseSecondResponse?.();
  await expect(page.locator('#structural-search-status')).toHaveText('No structural matches');
});

test('reports structural-search provider rejections', async ({ page }) => {
  await page.route('**/api/ast-grep', async (route) => {
    await route.fulfill({
      contentType: 'application/json',
      body: JSON.stringify({
        matches: [{ byte_start: 0, byte_end: 100_000, pattern_id: 'invalid' }],
      }),
    });
  });

  await page.goto('/ml');
  await waitForLambdaMount(page);
  await replaceSource(page, 'fn rejected(x : Int) { x }');
  await expect(page.locator('#structural-search-status'))
    .toHaveText('Structural search unavailable');
});
