import path from 'node:path';
import { expect, test, type Page } from '@playwright/test';

async function waitForResume(page: Page): Promise<void> {
  await expect(page.locator('[data-resume-ready]'))
    .toHaveAttribute('data-resume-ready', 'true');
}

async function enterResumeFromHub(page: Page): Promise<void> {
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.getByRole('link', { name: /Session Resume/ }).click();
  await waitForResume(page);
  await expect(page).toHaveURL(/\/resume$/);
}

async function importFixture(page: Page): Promise<void> {
  await page.getByLabel('Open session file').setInputFiles(
    path.resolve('tests/fixtures/pi-session-v3.jsonl'),
  );
  await expect(page.locator('.pilot-session-status')).toContainText('pi-session-v3.jsonl');
  await page.locator('#branch-select').selectOption('0000000f');
}

test('keeps the server-rendered Resume inspection inert without client JavaScript', async ({ browser }, testInfo) => {
  const baseURL = testInfo.project.use.baseURL;
  if (typeof baseURL !== 'string') throw new Error('Waku test baseURL is unavailable');
  const context = await browser.newContext({ baseURL, javaScriptEnabled: false });
  try {
    const page = await context.newPage();
    const response = await page.goto('/resume');
    expect(response?.ok()).toBe(true);
    await expect(page.locator('[data-resume-ready]')).toHaveAttribute('inert', '');
    await expect(page.locator('[data-resume-ready]'))
      .toHaveAttribute('data-resume-ready', 'false');
    await expect(page.locator('.pilot-workbench')).toBeVisible();
  } finally {
    await context.close();
  }
});

test('hydrates the server-rendered timestamps in a different client time zone', async ({ browser }, testInfo) => {
  const baseURL = testInfo.project.use.baseURL;
  if (typeof baseURL !== 'string') throw new Error('Waku test baseURL is unavailable');
  const serverContext = await browser.newContext({ baseURL, javaScriptEnabled: false });
  const clientContext = await browser.newContext({ baseURL, timezoneId: 'America/New_York' });
  try {
    const serverPage = await serverContext.newPage();
    await serverPage.goto('/resume');
    const serverTimestamps = await serverPage.locator('time').allTextContents();
    expect(serverTimestamps.length).toBeGreaterThan(0);

    const hydrationErrors: string[] = [];
    const clientPage = await clientContext.newPage();
    clientPage.on('console', message => {
      if (
        message.type() === 'error' &&
        /hydration|server rendered html|didn't match/i.test(message.text())
      ) {
        hydrationErrors.push(message.text());
      }
    });
    await clientPage.goto('/resume');
    await waitForResume(clientPage);

    expect(await clientPage.locator('time').allTextContents()).toEqual(serverTimestamps);
    expect(hydrationErrors).toEqual([]);
  } finally {
    await serverContext.close();
    await clientContext.close();
  }
});

test('restores imported state, completed chat, source fragment, and listbox focus, then Forget purges them', async ({ page }) => {
  await enterResumeFromHub(page);
  await importFixture(page);

  const historyLength = await page.evaluate(() => window.history.length);
  const selectedOption = page.locator('.pilot-conversation-list [data-entry-id="00000004"]');
  await selectedOption.click();
  await expect(page).toHaveURL(/\/resume#source-00000004$/);
  await page.locator('.pilot-conversation-list [data-entry-id="00000003"]').click();
  await expect(page).toHaveURL(/\/resume#source-00000003$/);
  expect(await page.evaluate(() => window.history.length)).toBe(historyLength);

  const chat = page.locator('.pilot-source-chat');
  await chat.getByLabel('Chat message').fill('Keep this completed turn in route memory.');
  await chat.getByRole('button', { name: 'Send' }).click();
  await expect(chat.locator('.ai-message[data-role="assistant"]')).toContainText(
    'without attached activity history',
  );
  await selectedOption.click();
  await expect(selectedOption).toBeFocused();

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await page.goForward();
  await waitForResume(page);

  await expect(page.locator('.pilot-session-status')).toContainText('pi-session-v3.jsonl');
  await expect(page.locator('#branch-select')).toHaveValue('0000000f');
  await expect(selectedOption).toHaveAttribute('aria-selected', 'true');
  await expect(chat.locator('.ai-message')).toHaveCount(2);
  await expect(chat).toContainText('Keep this completed turn in route memory.');
  await expect(selectedOption).toBeFocused();

  await page.getByRole('button', { name: 'Forget session' }).click();
  await expect(page.getByRole('button', { name: 'Forget session' })).toHaveCount(0);
  await expect(chat.locator('.ai-message')).toHaveCount(0);
  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await page.goForward();
  await waitForResume(page);

  await expect(page.locator('.pilot-session-status')).toContainText('Example');
  await expect(page.getByRole('button', { name: 'Forget session' })).toHaveCount(0);
  await expect(chat.locator('.ai-message')).toHaveCount(0);
});

test('aborts status and pending chat work on route exit without snapshotting the partial turn', async ({ page }) => {
  await page.addInitScript(() => {
    const originalFetch = window.fetch.bind(window);
    const state = {
      statusMode: 'pending' as 'pending' | 'available',
      statusPendingCount: 0,
      statusAbortCount: 0,
      chatStarted: false,
      chatSignalAborted: false,
    };
    (window as Window & { __resumeFetchState?: typeof state }).__resumeFetchState = state;
    window.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
      const request = input instanceof Request ? input : new Request(input, init);
      const pathname = new URL(request.url).pathname;
      const signal = input instanceof Request ? input.signal : init?.signal;
      if (pathname === '/api/pi-resume-chat/status') {
        if (state.statusMode === 'pending') {
          state.statusPendingCount += 1;
          return new Promise<Response>((_resolve, reject) => {
            const abort = () => {
              state.statusPendingCount -= 1;
              state.statusAbortCount += 1;
              reject(new DOMException('The request was aborted.', 'AbortError'));
            };
            if (signal?.aborted) abort();
            else signal?.addEventListener('abort', abort, { once: true });
          });
        }
        return Promise.resolve(new Response(JSON.stringify({
          available: true,
          provider: 'fake',
          model: 'pke-chat-fake-v1',
          localRelay: true,
        }), {
          headers: { 'content-type': 'application/json' },
        }));
      }
      if (pathname === '/api/pi-resume-chat' && request.method === 'POST') {
        state.chatStarted = true;
        return new Promise<Response>((_resolve, reject) => {
          const abort = () => {
            state.chatSignalAborted = true;
            reject(new DOMException('The request was aborted.', 'AbortError'));
          };
          if (signal?.aborted) abort();
          else signal?.addEventListener('abort', abort, { once: true });
        });
      }
      return originalFetch(input, init);
    }) as typeof window.fetch;
  });
  await enterResumeFromHub(page);

  await expect.poll(() => page.evaluate(() => {
    const state = (window as Window & {
      __resumeFetchState?: { statusPendingCount: number };
    }).__resumeFetchState;
    return state?.statusPendingCount ?? 0;
  })).toBeGreaterThan(0);
  const abortCountBeforeExit = await page.evaluate(() =>
    (window as Window & { __resumeFetchState?: { statusAbortCount: number } })
      .__resumeFetchState?.statusAbortCount ?? 0,
  );
  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await expect.poll(() => page.evaluate(() => {
    const state = (window as Window & {
      __resumeFetchState?: {
        statusPendingCount: number;
      };
    }).__resumeFetchState;
    return state?.statusPendingCount;
  })).toBe(0);
  await expect.poll(() => page.evaluate((previous) => {
    const state = (window as Window & {
      __resumeFetchState?: { statusAbortCount: number };
    }).__resumeFetchState;
    return (state?.statusAbortCount ?? 0) > previous;
  }, abortCountBeforeExit)).toBe(true);
  await page.evaluate(() => {
    const state = (window as Window & {
      __resumeFetchState?: { statusMode: 'pending' | 'available' };
    }).__resumeFetchState;
    if (state !== undefined) state.statusMode = 'available';
  });

  await page.goForward();
  await waitForResume(page);

  const prompt = page.getByLabel('Chat message');
  await expect(prompt).toBeEnabled();
  await prompt.fill('This pending turn must not be restored.');
  await page.locator('.pilot-source-chat').getByRole('button', { name: 'Send' }).click();
  await expect.poll(() => page.evaluate(() =>
    (window as Window & { __resumeFetchState?: { chatStarted: boolean } })
      .__resumeFetchState?.chatStarted,
  )).toBe(true);

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await expect.poll(() => page.evaluate(() => {
    const state = (window as Window & {
      __resumeFetchState?: {
        chatSignalAborted: boolean;
      };
    }).__resumeFetchState;
    return state === undefined
      ? undefined
      : state.chatSignalAborted;
  })).toBe(true);

  await page.goForward();
  await waitForResume(page);
  await expect(page.locator('.pilot-source-chat .ai-message')).toHaveCount(0);
  await expect(page.getByLabel('Chat message')).toHaveValue('');
});

test('clears route-only Resume state on reload without creating browser persistence', async ({ page }) => {
  await enterResumeFromHub(page);
  await importFixture(page);
  await expect(page.getByRole('button', { name: 'Forget session' })).toBeVisible();

  await page.reload();
  await waitForResume(page);

  await expect(page.locator('.pilot-session-status')).toContainText('Example');
  await expect(page.getByRole('button', { name: 'Forget session' })).toHaveCount(0);
  await expect(page.locator('#branch-select')).toHaveValue('0000000f');
  await expect(page.evaluate(async () => ({
    local: Object.keys(localStorage),
    session: Object.keys(sessionStorage),
    databases: (await indexedDB.databases()).map(database => database.name),
  }))).resolves.toEqual({ local: [], session: [], databases: [] });
});
