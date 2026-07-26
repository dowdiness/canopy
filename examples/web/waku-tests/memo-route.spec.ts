import { expect, test, type Page } from '@playwright/test';

async function waitForMemoMount(page: Page): Promise<void> {
  await expect(page.locator('[data-memo-ready]'))
    .toHaveAttribute('data-memo-ready', 'true');
  await expect(page.locator('#status'))
    .toHaveText('Ready. Enter your API key and start typing.');
}

async function enterMemoFromHub(page: Page): Promise<void> {
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.getByRole('link', { name: /Canopy Memo/ }).click();
  await waitForMemoMount(page);
}

async function installImmediateProvider(page: Page, fixed: string): Promise<void> {
  await page.evaluate((fixedText) => {
    const originalFetch = window.fetch.bind(window);
    const state = { calls: 0 };
    (window as Window & { __memoProviderState?: typeof state }).__memoProviderState = state;
    window.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
      const url = input instanceof Request ? input.url : String(input);
      if (!url.includes('generativelanguage.googleapis.com')) {
        return originalFetch(input, init);
      }
      state.calls += 1;
      const actions = JSON.stringify([{
        action: 'fix_typos',
        original: 'teh',
        fixed: fixedText,
      }]);
      return Promise.resolve(new Response(JSON.stringify({
        candidates: [{ content: { parts: [{ text: actions }] } }],
      }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }));
    }) as typeof window.fetch;
  }, fixed);
}

test('keeps the development Memo controls inert without client JavaScript', async ({ browser }, testInfo) => {
  const baseURL = testInfo.project.use.baseURL;
  if (typeof baseURL !== 'string') throw new Error('Waku test baseURL is unavailable');
  const context = await browser.newContext({ baseURL, javaScriptEnabled: false });
  try {
    const page = await context.newPage();
    const response = await page.goto('/memo');
    expect(response?.ok()).toBe(true);
    await expect(page.getByRole('heading', { name: 'Canopy Memo' })).toBeVisible();
    await expect(page.locator('[data-memo-ready]')).toHaveAttribute('inert', '');
    await expect(page.locator('[data-memo-ready]'))
      .toHaveAttribute('data-memo-ready', 'false');
  } finally {
    await context.close();
  }
});

test('reports Memo runtime load failures through the route error boundary', async ({ page }) => {
  const pageErrors: Error[] = [];
  let failedRuntimeRequests = 0;
  page.on('pageerror', (error) => pageErrors.push(error));
  await page.route(/crdt[-_]lambda/, (route) => {
    failedRuntimeRequests += 1;
    return route.abort('failed');
  });

  await page.goto('/memo');

  await expect(page.getByRole('heading', {
    name: 'This demo could not be displayed',
  })).toBeFocused();
  expect(failedRuntimeRequests).toBeGreaterThan(0);
  await expect(page.locator('[data-imperative-demo-host="memo"]')).toHaveCount(0);
  expect(pageErrors).toEqual([]);
});

test('restores draft, instruction, proposal, and stable focus without credentials or rate state', async ({ page }) => {
  await enterMemoFromHub(page);
  await installImmediateProvider(page, 'the memo');
  await page.locator('#api-key').fill('not-snapshotted');
  await page.locator('#memo').fill('teh memo');
  await page.locator('#instruction').fill('Make it formal');
  await page.getByRole('button', { name: 'Fix Typos' }).click();
  await expect(page.locator('#diff-section')).toHaveClass(/visible/);
  await expect(page.locator('#diff-original')).toHaveText('teh memo');
  await expect(page.locator('#diff-fixed')).toHaveText('the memo');
  await page.locator('#instruction').focus();

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await page.goForward();
  await waitForMemoMount(page);

  await expect(page.locator('#memo')).toHaveValue('teh memo');
  await expect(page.locator('#instruction')).toHaveValue('Make it formal');
  await expect(page.locator('#instruction')).toBeFocused();
  await expect(page.locator('#api-key')).toHaveValue('');
  await expect(page.locator('#diff-section')).toHaveClass(/visible/);
  await expect(page.locator('#diff-original')).toHaveText('teh memo');
  await expect(page.locator('#diff-fixed')).toHaveText('the memo');
  await page.getByRole('button', { name: 'Accept' }).click();
  await expect(page.locator('#memo')).toHaveValue('the memo');
  await expect(page.locator('#diff-section')).not.toHaveClass(/visible/);

  await page.locator('#api-key').fill('fresh-key');
  await page.locator('#memo').fill('teh memo');
  await page.getByRole('button', { name: 'Fix Typos' }).click();
  await expect.poll(() => page.evaluate(
    () => (window as Window & { __memoProviderState?: { calls: number } })
      .__memoProviderState?.calls,
  )).toBe(2);
  await expect(page.locator('#status')).not.toContainText('Rate limited');
});

test('invalidates a pending provider result when the route exits', async ({ page }) => {
  const pageErrors: Error[] = [];
  page.on('pageerror', (error) => pageErrors.push(error));
  await enterMemoFromHub(page);
  await page.evaluate(() => {
    const originalFetch = window.fetch.bind(window);
    const state = { started: false, resolved: false };
    (window as Window & { __memoPendingState?: typeof state }).__memoPendingState = state;
    window.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
      const url = input instanceof Request ? input.url : String(input);
      if (!url.includes('generativelanguage.googleapis.com')) {
        return originalFetch(input, init);
      }
      state.started = true;
      return new Promise<Response>((resolve) => {
        (window as Window & { __resolveMemoProvider?: () => void })
          .__resolveMemoProvider = () => {
            state.resolved = true;
            const actions = JSON.stringify([{
              action: 'fix_typos',
              original: 'teh',
              fixed: 'the pending draft',
            }]);
            resolve(new Response(JSON.stringify({
              candidates: [{ content: { parts: [{ text: actions }] } }],
            }), { status: 200, headers: { 'content-type': 'application/json' } }));
          };
      });
    }) as typeof window.fetch;
  });
  await page.locator('#api-key').fill('temporary-key');
  await page.locator('#memo').fill('teh pending draft');
  await page.getByRole('button', { name: 'Fix Typos' }).click();
  await expect(page.locator('#status')).toHaveText('Calling Gemini API...');
  await expect.poll(() => page.evaluate(
    () => (window as Window & { __memoPendingState?: { started: boolean } })
      .__memoPendingState?.started,
  )).toBe(true);

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await page.goForward();
  await waitForMemoMount(page);
  await expect(page.locator('#memo')).toHaveValue('teh pending draft');
  await expect(page.locator('#api-key')).toHaveValue('');
  await expect(page.locator('#diff-section')).not.toHaveClass(/visible/);

  await page.evaluate(() => {
    (window as Window & { __resolveMemoProvider?: () => void })
      .__resolveMemoProvider?.();
  });
  await expect.poll(() => page.evaluate(
    () => (window as Window & { __memoPendingState?: { resolved: boolean } })
      .__memoPendingState?.resolved,
  )).toBe(true);
  await page.waitForTimeout(100);
  await expect(page.locator('#status'))
    .toHaveText('Ready. Enter your API key and start typing.');
  await expect(page.locator('#diff-section')).not.toHaveClass(/visible/);
  expect(pageErrors).toEqual([]);
});

test('reload clears draft, instruction, and completed proposal route memory', async ({ page }) => {
  await page.goto('/memo');
  await waitForMemoMount(page);
  await installImmediateProvider(page, 'the transient draft');
  await page.locator('#api-key').fill('temporary-key');
  await page.locator('#memo').fill('teh transient draft');
  await page.locator('#instruction').fill('Temporary instruction');
  await page.getByRole('button', { name: 'Fix Typos' }).click();
  await expect(page.locator('#diff-section')).toHaveClass(/visible/);

  await page.reload();
  await waitForMemoMount(page);

  await expect(page.locator('#memo')).toHaveValue('');
  await expect(page.locator('#instruction')).toHaveValue('');
  await expect(page.locator('#api-key')).toHaveValue('');
  await expect(page.locator('#diff-section')).not.toHaveClass(/visible/);
});

test('repeated route cycles release the surface and detached control listeners', async ({ page }) => {
  const pageErrors: Error[] = [];
  page.on('pageerror', (error) => pageErrors.push(error));
  await enterMemoFromHub(page);

  for (let cycle = 0; cycle < 3; cycle += 1) {
    await expect(page.locator('[data-imperative-demo-host="memo"]')).toHaveCount(1);
    await page.goBack();
    await expect(page).toHaveURL(/\/$/);
    await expect(page.locator('[data-imperative-demo-host="memo"]')).toHaveCount(0);
    await page.goForward();
    await waitForMemoMount(page);
  }

  await page.evaluate(() => {
    const originalFetch = window.fetch.bind(window);
    const state = { calls: 0 };
    (window as Window & { __memoDetachedState?: typeof state }).__memoDetachedState = state;
    window.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
      const url = input instanceof Request ? input.url : String(input);
      if (url.includes('generativelanguage.googleapis.com')) {
        state.calls += 1;
        return Promise.resolve(new Response('{"candidates":[]}', {
          status: 200,
          headers: { 'content-type': 'application/json' },
        }));
      }
      return originalFetch(input, init);
    }) as typeof window.fetch;
    (window as Window & { __memoDetachedControls?: Record<string, HTMLElement> })
      .__memoDetachedControls = {
        key: document.querySelector<HTMLInputElement>('#api-key')!,
        memo: document.querySelector<HTMLTextAreaElement>('#memo')!,
        instruction: document.querySelector<HTMLInputElement>('#instruction')!,
        fix: document.querySelector<HTMLButtonElement>('#fix-typos-btn')!,
        edit: document.querySelector<HTMLButtonElement>('#edit-btn')!,
      };
  });
  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await page.evaluate(() => {
    const controls = (window as Window & {
      __memoDetachedControls?: Record<string, HTMLElement>;
    }).__memoDetachedControls;
    if (controls === undefined) throw new Error('Detached Memo controls are unavailable');
    (controls.key as HTMLInputElement).value = 'detached-key';
    (controls.memo as HTMLTextAreaElement).value = 'detached draft';
    (controls.instruction as HTMLInputElement).value = 'detached instruction';
    controls.fix.click();
    controls.edit.click();
  });
  await page.waitForTimeout(100);
  expect(await page.evaluate(
    () => (window as Window & { __memoDetachedState?: { calls: number } })
      .__memoDetachedState?.calls,
  )).toBe(0);
  expect(pageErrors).toEqual([]);
});
