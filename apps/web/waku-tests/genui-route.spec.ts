import { expect, test, type Page } from '@playwright/test';

const DEFAULT_SOURCE = `<div class="card">
  <h1>Hello, World!</h1>
  <p>Streaming JSX → live DOM.</p>
</div>`;

async function waitForGenui(page: Page): Promise<void> {
  await expect(page.locator('[data-genui-ready]'))
    .toHaveAttribute('data-genui-ready', 'true');
}

async function enterGenuiFromHub(page: Page): Promise<void> {
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.getByRole('link', { name: /Generative UI/ }).click();
  await waitForGenui(page);
  await expect(page.locator('style[data-genui-route-styles]')).toHaveCount(1);
  await expect(page).toHaveURL(/\/genui$/);
}

async function hubStyle(page: Page) {
  return page.evaluate(() => {
    const main = getComputedStyle(document.querySelector('.demo-hub main')!);
    const heading = getComputedStyle(document.querySelector('.page-heading h1')!);
    const body = getComputedStyle(document.body);
    return {
      mainWidth: main.width,
      mainPaddingTop: main.paddingTop,
      headingFontSize: heading.fontSize,
      headingLineHeight: heading.lineHeight,
      bodyBackground: body.backgroundColor,
    };
  });
}

test('keeps the server-rendered GenUI controls inert without client JavaScript', async ({ browser }, testInfo) => {
  const baseURL = testInfo.project.use.baseURL;
  if (typeof baseURL !== 'string') throw new Error('Waku test baseURL is unavailable');
  const context = await browser.newContext({ baseURL, javaScriptEnabled: false });
  try {
    const page = await context.newPage();
    const response = await page.goto('/genui');
    expect(response?.ok()).toBe(true);
    await expect(page.getByRole('heading', { name: 'Generative UI' })).toBeVisible();
    await expect(page.locator('[data-genui-ready]')).toHaveAttribute('inert', '');
    await expect(page.locator('[data-genui-ready]'))
      .toHaveAttribute('data-genui-ready', 'false');
  } finally {
    await context.close();
  }
});

test('restores source, recorded commit, explorer state, committed revision, and row focus', async ({ page }) => {
  await enterGenuiFromHub(page);
  await expect(page.getByRole('heading', { name: 'Generative UI' })).toBeFocused();

  const source = '<section><h2>Restored GenUI</h2><p>Committed source</p></section>';
  await page.locator('#source-input').fill(source);
  await page.getByRole('button', { name: '▶ Stream' }).click();
  await expect(page.locator('#status-bar')).toContainText('DOM nodes rendered');
  const committed = await page.evaluate(() => ({
    revision: (window as Window & {
      __canopyGenUiTest?: { sessionRevision(): number | null };
    }).__canopyGenUiTest?.sessionRevision() ?? null,
    markup: document.querySelector('#html-preview')?.innerHTML ?? '',
  }));
  expect(committed.revision).not.toBeNull();

  await page.getByRole('button', { name: 'Inventory' }).click();
  await page.getByRole('button', { name: 'Run recorded candidate' }).click();
  await expect(page.locator('#feasibility-classification')).toHaveText('success');
  const recordedRevision = await page.locator('#feasibility-revision').textContent();
  const recordedMarkup = await page.locator('#feasibility-preview').innerHTML();

  await page.getByRole('button', { name: 'CSV fixture' }).click();
  await page.getByLabel('Filter name, status, or ID').fill('paid');
  const selectedRow = page.getByTestId('order-row-ord-1003');
  await selectedRow.click();
  await selectedRow.focus();
  await page.getByRole('button', { name: 'Diagnostics' }).click();
  await selectedRow.focus();

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await page.goForward();
  await waitForGenui(page);

  await expect(page.locator('#source-input')).toHaveValue(source);
  await expect(page.locator('#html-preview')).toHaveJSProperty('innerHTML', committed.markup);
  expect(await page.evaluate(() => (window as Window & {
    __canopyGenUiTest?: { sessionRevision(): number | null };
  }).__canopyGenUiTest?.sessionRevision() ?? null)).toBe(committed.revision);
  await expect(page.getByRole('button', { name: 'Inventory' })).toHaveClass(/active/);
  await expect(page.locator('#feasibility-revision')).toHaveText(recordedRevision ?? '');
  await expect(page.locator('#feasibility-preview')).toHaveJSProperty('innerHTML', recordedMarkup);
  await expect(page.getByRole('button', { name: 'CSV fixture' }))
    .toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByLabel('Filter name, status, or ID')).toHaveValue('paid');
  await expect(selectedRow).toHaveAttribute('aria-selected', 'true');
  await expect(selectedRow).toBeFocused();
  await expect(page.locator('#step-num')).toHaveText('—');
  await expect(page.getByRole('button', { name: 'Tree' })).toHaveClass(/active/);
});

test('reload clears route memory without creating browser persistence', async ({ page }) => {
  await page.goto('/genui');
  await waitForGenui(page);
  await page.locator('#source-input').fill('<main>Transient source</main>');
  await page.getByRole('button', { name: 'CSV fixture' }).click();
  await page.getByLabel('Filter name, status, or ID').fill('pending');
  await page.getByTestId('order-row-ord-1002').click();
  await page.getByRole('button', { name: 'Incidents' }).click();
  await page.getByRole('button', { name: 'Run recorded candidate' }).click();
  await expect(page.locator('#feasibility-classification')).toHaveText('success');

  await page.reload();
  await waitForGenui(page);

  await expect(page.locator('#source-input')).toHaveValue(DEFAULT_SOURCE);
  await expect(page.getByRole('button', { name: 'JSON fixture' }))
    .toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByLabel('Filter name, status, or ID')).toHaveValue('');
  await expect(page.locator('[aria-selected="true"]')).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Orders' })).toHaveClass(/active/);
  await expect(page.locator('#feasibility-revision')).toHaveText('—');
  await expect(page.evaluate(async () => ({
    local: Object.keys(localStorage),
    session: Object.keys(sessionStorage),
    databases: (await indexedDB.databases()).map(database => database.name),
  }))).resolves.toEqual({ local: [], session: [], databases: [] });
});

test('route exit aborts stream, live fetch, provider wait, handles, timers, and development hooks', async ({ page }) => {
  const pageErrors: Error[] = [];
  page.on('pageerror', error => pageErrors.push(error));
  await page.addInitScript(() => {
    const originalFetch = window.fetch.bind(window);
    const originalSetTimeout = window.setTimeout.bind(window);
    const originalClearTimeout = window.clearTimeout.bind(window);
    const state = {
      fetchStarted: false,
      fetchAborted: false,
      trackStreamTimers: false,
      streamTimers: new Set<number>(),
    };
    (window as Window & { __genuiRouteResources?: typeof state }).__genuiRouteResources = state;
    window.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
      const request = input instanceof Request ? input : new Request(input, init);
      if (new URL(request.url).pathname !== '/api/genui-feasibility') {
        return originalFetch(input, init);
      }
      state.fetchStarted = true;
      return new Promise<Response>((_resolve, reject) => {
        const abort = () => {
          state.fetchAborted = true;
          reject(new DOMException('The request was aborted.', 'AbortError'));
        };
        if (request.signal.aborted) abort();
        else request.signal.addEventListener('abort', abort, { once: true });
      });
    }) as typeof window.fetch;
    window.setTimeout = ((handler: TimerHandler, timeout?: number, ...args: unknown[]) => {
      let timer = 0;
      const wrapped = typeof handler === 'function'
        ? (...callbackArgs: unknown[]) => {
            state.streamTimers.delete(timer);
            return handler(...callbackArgs);
          }
        : handler;
      timer = originalSetTimeout(wrapped, timeout, ...args);
      if (state.trackStreamTimers && (timeout === 60 || timeout === 100)) {
        state.streamTimers.add(timer);
      }
      return timer;
    }) as typeof window.setTimeout;
    window.clearTimeout = ((timer?: number) => {
      if (timer !== undefined) state.streamTimers.delete(timer);
      originalClearTimeout(timer);
    }) as typeof window.clearTimeout;
  });

  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  const hubStyleBefore = await hubStyle(page);
  await page.getByRole('link', { name: /Generative UI/ }).click();
  await waitForGenui(page);
  await page.getByRole('button', { name: 'Run recorded candidate' }).click();
  await expect(page.locator('#feasibility-classification')).toHaveText('success');
  const recordedCommit = {
    revision: await page.locator('#feasibility-revision').textContent(),
    markup: await page.locator('#feasibility-preview').innerHTML(),
  };
  await page.locator('#source-input').fill(
    `<div>${Array.from({ length: 30 }, (_, index) => `<span>${index}</span>`).join('')}</div>`,
  );
  await page.evaluate(() => {
    const resources = (window as Window & {
      __genuiRouteResources?: { trackStreamTimers: boolean };
    }).__genuiRouteResources;
    if (resources) resources.trackStreamTimers = true;
  });
  const detachedStreamButton = await page.locator('#stream-btn').elementHandle();
  await page.getByRole('button', { name: '▶ Stream' }).click();
  await expect(page.locator('#stream-btn')).toHaveText('■ Stop');
  await expect.poll(() => page.evaluate(() => (window as Window & {
    __canopyGenUiTest?: { sessionRevision(): number | null };
  }).__canopyGenUiTest?.sessionRevision() ?? null)).not.toBeNull();

  await page.evaluate(() => {
    const host = document.querySelector('[data-imperative-demo-host="genui"]');
    const root = document.createElement('div');
    root.id = 'genui-route-test-root';
    host?.append(root);
    const windowWithApis = window as Window & {
      __canopyGenUiTest?: {
        sessionNewForTest(rootId: string): { handle: number; revision: number };
        asyncDriverNewForSession(handle: number, revision: number): {
          driver_handle: number;
          generation_id: number;
        };
        asyncDriverProviderNew(
          driver: number,
          generation: number,
          revision: number,
          sequence: number,
        ): { provider_handle: number };
        asyncDriverProviderWait(handle: number): Promise<unknown>;
      };
      __canopyGenUiFeasibilityTest?: {
        runSlot(input: Record<string, unknown>): Promise<unknown>;
      };
      __genuiProviderOutcome?: Promise<unknown>;
      __genuiFetchOutcome?: Promise<unknown>;
    };
    const api = windowWithApis.__canopyGenUiTest!;
    const session = api.sessionNewForTest(root.id);
    const driver = api.asyncDriverNewForSession(session.handle, session.revision);
    const provider = api.asyncDriverProviderNew(
      driver.driver_handle,
      driver.generation_id,
      session.revision,
      0,
    );
    windowWithApis.__genuiProviderOutcome = api.asyncDriverProviderWait(provider.provider_handle);
    windowWithApis.__genuiFetchOutcome = windowWithApis.__canopyGenUiFeasibilityTest!.runSlot({
      studyId: 'genui-local-v1',
      runCapability: '1'.repeat(64),
      caseId: 'orders-pending-attention',
      slotId: 0,
    }).then(
      value => ({ status: 'resolved', value }),
      error => ({ status: 'rejected', error: String(error) }),
    );
  });
  await expect.poll(() => page.evaluate(() => (window as Window & {
    __genuiRouteResources?: { fetchStarted: boolean };
  }).__genuiRouteResources?.fetchStarted)).toBe(true);

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.locator('[data-imperative-demo-host="genui"]')).toHaveCount(0);
  await expect(page.locator('style[data-genui-route-styles]')).toHaveCount(0);
  await expect.poll(() => page.evaluate(() => (window as Window & {
    __genuiRouteResources?: { fetchAborted: boolean };
  }).__genuiRouteResources?.fetchAborted)).toBe(true);
  expect(await page.evaluate(() => (window as Window & {
    __genuiProviderOutcome?: Promise<unknown>;
  }).__genuiProviderOutcome)).toEqual({ kind: 'aborted' });
  expect(await page.evaluate(() => {
    const typed = window as Window & {
      __canopyGenUiTest?: unknown;
      __canopyGenUiFeasibilityTest?: unknown;
      __genuiRouteResources?: { streamTimers: Set<number> };
    };
    return {
      testHook: typeof typed.__canopyGenUiTest,
      feasibilityHook: typeof typed.__canopyGenUiFeasibilityTest,
      timers: typed.__genuiRouteResources?.streamTimers.size,
    };
  })).toEqual({ testHook: 'undefined', feasibilityHook: 'undefined', timers: 0 });

  await detachedStreamButton?.evaluate(button => button.click());
  expect(await page.evaluate(() => (window as Window & {
    __genuiRouteResources?: { streamTimers: Set<number> };
  }).__genuiRouteResources?.streamTimers.size)).toBe(0);

  for (let cycle = 0; cycle < 2; cycle += 1) {
    await page.goForward();
    await waitForGenui(page);
    await expect(page.locator('[data-imperative-demo-host="genui"]')).toHaveCount(1);
    await expect(page.locator('style[data-genui-route-styles]')).toHaveCount(1);
    expect(await page.evaluate(() => typeof (window as Window & {
      __canopyGenUiTest?: unknown;
    }).__canopyGenUiTest)).toBe('object');
    await expect(page.locator('#html-preview'))
      .toContainText('Stream JSX to see rendered output.');
    expect(await page.evaluate(() => (window as Window & {
      __canopyGenUiTest?: { sessionRevision(): number | null };
    }).__canopyGenUiTest?.sessionRevision() ?? null)).toBeNull();
    await expect(page.locator('#feasibility-revision'))
      .toHaveText(recordedCommit.revision ?? '');
    await expect(page.locator('#feasibility-preview'))
      .toHaveJSProperty('innerHTML', recordedCommit.markup);
    await page.goBack();
    await expect(page).toHaveURL(/\/$/);
    await expect(page.locator('style[data-genui-route-styles]')).toHaveCount(0);
    expect(await page.evaluate(() => typeof (window as Window & {
      __canopyGenUiTest?: unknown;
    }).__canopyGenUiTest)).toBe('undefined');
  }
  expect(await hubStyle(page)).toEqual(hubStyleBefore);
  expect(pageErrors).toEqual([]);
});
