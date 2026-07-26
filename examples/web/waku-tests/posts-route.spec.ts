import { expect, test, type Page } from '@playwright/test';

const POST_STORAGE_KEY = 'canopy.posts.v1';
const POST_EVENT_STORAGE_KEY = 'canopy.post-events.v1';

const storedPosts = [
  {
    id: 'post-sync-recovery',
    text: 'For sync recovery we decided to retry locally before merging remote commits.',
    createdAt: '2026-06-10T09:00:00.000Z',
  },
  {
    id: 'post-basil-window',
    text: 'Basil seedlings recovered on the kitchen window shelf after I stopped overwatering.',
    createdAt: '2026-06-09T09:00:00.000Z',
  },
] as const;

async function seedPosts(page: Page) {
  await page.evaluate(
    ({ key, posts }) => window.localStorage.setItem(key, JSON.stringify(posts)),
    { key: POST_STORAGE_KEY, posts: storedPosts },
  );
}

async function waitForPostsMount(page: Page) {
  await expect(page.locator('#post-form'))
    .toHaveAttribute('data-posts-ready', 'true');
}

test('keeps the server-rendered Posts form inert without client JavaScript', async ({ browser }, testInfo) => {
  const baseURL = testInfo.project.use.baseURL;
  if (typeof baseURL !== 'string') throw new Error('Waku test baseURL is unavailable');
  const context = await browser.newContext({ baseURL, javaScriptEnabled: false });
  try {
    const page = await context.newPage();
    const response = await page.goto('/posts');
    expect(response?.ok()).toBe(true);
    await expect(page.locator('#post-form')).toHaveAttribute('inert', '');
    await expect(page.locator('#post-form'))
      .toHaveAttribute('data-posts-ready', 'false');
  } finally {
    await context.close();
  }
});

test('restores the Posts draft, Ask mode, highlighted post, and focus after traversal', async ({ page }) => {
  await page.goto('/');
  await seedPosts(page);
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.getByRole('link', { name: 'Posts' }).click();
  await waitForPostsMount(page);
  await expect(page).toHaveURL(/\/posts$/);
  await expect(page.getByRole('heading', { name: 'Post to yourself.' })).toBeFocused();

  const question = 'what did I decide about sync recovery?';
  await page.getByLabel('Write').fill(question);
  await page.getByRole('button', { name: 'Ask' }).click();
  await page.getByRole('button', { name: /Open source post/ }).click();
  const openedPost = page.locator('.post-item[data-highlighted="true"]');
  await expect(openedPost).toBeFocused();

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await page.goForward();
  await waitForPostsMount(page);
  await expect(page).toHaveURL(/\/posts$/);

  await expect(page.getByLabel('Write')).toHaveValue(question);
  await expect(page.locator('#related-kicker')).toHaveText('Asked from your posts');
  await expect(page.locator('#related-title')).toHaveText('Source posts');
  await expect(openedPost).toBeFocused();
});

test('reload keeps only the existing Posts stores and clears route-memory state', async ({ page }) => {
  await page.goto('/');
  await seedPosts(page);
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.getByRole('link', { name: 'Posts' }).click();
  await waitForPostsMount(page);

  await page.getByLabel('Write').fill('A durable post written before a route-only draft.');
  await page.getByRole('button', { name: 'Post' }).click();
  await page.getByLabel('Write').fill('route-only draft');
  await page.reload();
  await waitForPostsMount(page);

  await expect(page.getByLabel('Write')).toHaveValue('');
  await expect(page.locator('.post-item p')).toHaveText([
    'A durable post written before a route-only draft.',
    ...storedPosts.map(({ text }) => text),
  ]);
  await expect(page.locator('#related-panel')).toBeHidden();
  await expect(page.locator('.post-item[data-highlighted="true"]')).toHaveCount(0);

  const storage = await page.evaluate(
    ({ postKey, eventKey }) => ({
      posts: JSON.parse(window.localStorage.getItem(postKey) ?? '[]') as unknown[],
      events: JSON.parse(window.localStorage.getItem(eventKey) ?? '[]') as unknown[],
      keys: Object.keys(window.localStorage).sort(),
    }),
    { postKey: POST_STORAGE_KEY, eventKey: POST_EVENT_STORAGE_KEY },
  );
  expect(storage.posts).toHaveLength(3);
  expect(storage.events).toEqual([
    expect.objectContaining({ type: 'post_created' }),
  ]);
  expect(storage.keys).toEqual([POST_EVENT_STORAGE_KEY, POST_STORAGE_KEY].sort());
});

test('repeated Posts route cycles release listeners and pending focus work', async ({ page }) => {
  await page.addInitScript(() => {
    const listenerRecords: Array<{
      target: EventTarget;
      type: string;
      listener: EventListenerOrEventListenerObject;
    }> = [];
    const originalAdd = EventTarget.prototype.addEventListener;
    const originalRemove = EventTarget.prototype.removeEventListener;
    const isPostsTarget = (target: EventTarget) =>
      target instanceof Element &&
      target.closest('[data-imperative-demo-host="posts"]') !== null;

    EventTarget.prototype.addEventListener = function (type, listener, options) {
      if (listener !== null && isPostsTarget(this)) {
        listenerRecords.push({ target: this, type, listener });
      }
      originalAdd.call(this, type, listener, options);
    };
    EventTarget.prototype.removeEventListener = function (type, listener, options) {
      const index = listener === null ? -1 : listenerRecords.findIndex(
        (record) => record.target === this && record.type === type && record.listener === listener,
      );
      if (index >= 0) listenerRecords.splice(index, 1);
      originalRemove.call(this, type, listener, options);
    };
    Object.defineProperty(window, '__postsResources', {
      value: { listenerCount: () => listenerRecords.length },
    });
  });

  await page.goto('/');
  await seedPosts(page);
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  const mountedListenerCounts: number[] = [];

  for (let cycle = 0; cycle < 2; cycle += 1) {
    await page.getByRole('link', { name: 'Posts' }).click();
    await waitForPostsMount(page);
    await expect(page.getByLabel('Write')).toBeVisible();
    mountedListenerCounts.push(await page.evaluate(
      () => (window as unknown as {
        __postsResources: { listenerCount(): number };
      }).__postsResources.listenerCount(),
    ));

    await page.goBack();
    await expect(page).toHaveURL(/\/$/);
    expect(await page.evaluate(
      () => (window as unknown as {
        __postsResources: { listenerCount(): number };
      }).__postsResources.listenerCount(),
    )).toBe(0);
  }

  expect(mountedListenerCounts[0]).toBeGreaterThan(0);
  expect(mountedListenerCounts[1]).toBe(mountedListenerCounts[0]);

  await page.getByRole('link', { name: 'Posts' }).click();
  await waitForPostsMount(page);
  await page.getByLabel('Write').fill('sync recovery');
  await page.evaluate(() => {
    const frameId = 2_147_483_000;
    const originalRequest = window.requestAnimationFrame;
    const originalCancel = window.cancelAnimationFrame;
    let intercepted = false;
    (window as Window & { __postsFocusFrameCancelled?: boolean }).__postsFocusFrameCancelled = false;
    window.requestAnimationFrame = ((callback: FrameRequestCallback) => {
      if (intercepted) return originalRequest(callback);
      intercepted = true;
      window.requestAnimationFrame = originalRequest;
      return frameId;
    }) as typeof window.requestAnimationFrame;
    window.cancelAnimationFrame = ((requestedId: number) => {
      if (requestedId === frameId) {
        (window as Window & { __postsFocusFrameCancelled?: boolean })
          .__postsFocusFrameCancelled = true;
        return;
      }
      originalCancel(requestedId);
    }) as typeof window.cancelAnimationFrame;
    document.querySelector<HTMLButtonElement>('.related-open')?.click();
    window.history.back();
  });
  await expect(page).toHaveURL(/\/$/);
  expect(await page.evaluate(
    () => (window as Window & { __postsFocusFrameCancelled?: boolean })
      .__postsFocusFrameCancelled,
  )).toBe(true);
});
