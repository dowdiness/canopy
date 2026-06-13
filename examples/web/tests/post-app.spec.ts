import { test, expect } from '@playwright/test';

const POST_STORAGE_KEY = 'canopy.posts.v1';
const POST_EVENT_STORAGE_KEY = 'canopy.post-events.v1';

test.beforeEach(async ({ page }) => {
  await page.goto('/posts.html');
  await expect(page.getByRole('heading', { name: 'Post to yourself.' })).toBeVisible();
});

test.describe('local-first post app', () => {
  test('posts text with the button and keeps it after reload', async ({ page }) => {
    const input = page.getByLabel('Write');

    await input.fill('Remember the product wedge: post exists before retrieval.');
    await page.getByRole('button', { name: 'Post' }).click();

    await expect(input).toHaveValue('');
    await expect(page.locator('.post-item p')).toHaveText([
      'Remember the product wedge: post exists before retrieval.',
    ]);
    await expect(page.locator('#post-count')).toHaveText('1 post');

    const events = await page.evaluate(
      key => JSON.parse(window.localStorage.getItem(key) ?? '[]') as unknown[],
      POST_EVENT_STORAGE_KEY,
    );
    expect(events).toEqual(
      expect.arrayContaining([expect.objectContaining({ type: 'post_created' })]),
    );

    await page.reload();

    await expect(page.locator('.post-item p')).toHaveText([
      'Remember the product wedge: post exists before retrieval.',
    ]);
    await expect(page.locator('#post-count')).toHaveText('1 post');
  });

  test('Ctrl+Enter posts while plain Enter keeps writing', async ({ page }) => {
    const input = page.getByLabel('Write');

    await input.fill('First line');
    await input.press('Enter');
    await input.pressSequentially('Second line');

    await expect(input).toHaveValue('First line\nSecond line');
    await expect(page.locator('.post-item')).toHaveCount(0);

    await input.press('Control+Enter');

    await expect(page.locator('.post-item p')).toHaveText(['First line\nSecond line']);
    await expect(input).toHaveValue('');
  });

  test('shows the chronological fallback newest first', async ({ page }) => {
    const input = page.getByLabel('Write');

    await input.fill('Older post');
    await input.press('Control+Enter');
    await input.fill('Newer post');
    await input.press('Control+Enter');

    await expect(page.locator('.post-item p')).toHaveText([
      'Newer post',
      'Older post',
    ]);
  });

  test('surfaces related posts while typing a draft', async ({ page }) => {
    await page.evaluate(
      ({ key, posts }) => window.localStorage.setItem(key, JSON.stringify(posts)),
      {
        key: POST_STORAGE_KEY,
        posts: [
          {
            id: 'post-basil-window',
            text: 'Basil seedlings recovered on the kitchen window shelf after I stopped overwatering.',
            createdAt: '2026-06-10T09:00:00.000Z',
          },
          {
            id: 'post-herb-light',
            text: 'The kitchen window gets stronger afternoon light, so tender herbs move there first.',
            createdAt: '2026-06-09T09:00:00.000Z',
          },
          {
            id: 'post-basil-soup',
            text: 'Tomato basil soup worked best with the small grocery basil, not the dried jar.',
            createdAt: '2026-06-08T09:00:00.000Z',
          },
          {
            id: 'post-parser-baseline',
            text: 'Projection identity baseline only advances after semantic lowering succeeds.',
            createdAt: '2026-06-07T09:00:00.000Z',
          },
          {
            id: 'post-running-shoes',
            text: 'Replace the running shoes before the next long trail loop.',
            createdAt: '2026-06-06T09:00:00.000Z',
          },
        ],
      },
    );
    await page.reload();

    const input = page.getByLabel('Write');
    const relatedPanel = page.locator('#related-panel');
    const relatedTexts = page.locator('.related-text');

    await expect(relatedPanel).toBeHidden();

    await input.pressSequentially('basil kitchen window');

    await expect(relatedPanel).toBeVisible();
    await expect(page.locator('#related-count')).toHaveText('3 related posts');
    await expect(relatedTexts).toHaveText([
      'Basil seedlings recovered on the kitchen window shelf after I stopped overwatering.',
      'The kitchen window gets stronger afternoon light, so tender herbs move there first.',
      'Tomato basil soup worked best with the small grocery basil, not the dried jar.',
    ]);

    await input.fill('parser identity baseline');

    await expect(page.locator('#related-count')).toHaveText('1 related post');
    await expect(relatedTexts).toHaveText([
      'Projection identity baseline only advances after semantic lowering succeeds.',
    ]);

    await input.fill('');
    await expect(relatedPanel).toBeHidden();
  });

  test('boosts revisited related posts and explains why they surfaced', async ({ page }) => {
    const olderText = 'Sync recovery policy keeps retry buffer before merge.';
    const newerText = 'Sync recovery policy keeps retry buffer before commit.';

    await page.evaluate(
      ({ key, posts }) => window.localStorage.setItem(key, JSON.stringify(posts)),
      {
        key: POST_STORAGE_KEY,
        posts: [
          {
            id: 'post-sync-commit',
            text: newerText,
            createdAt: '2026-06-10T09:00:00.000Z',
          },
          {
            id: 'post-sync-merge',
            text: olderText,
            createdAt: '2026-06-08T09:00:00.000Z',
          },
        ],
      },
    );
    await page.reload();

    const input = page.getByLabel('Write');
    const relatedTexts = page.locator('.related-text');

    await input.fill('sync recovery policy retry buffer');

    await expect(relatedTexts).toHaveText([newerText, olderText]);

    await page
      .locator('.related-item')
      .filter({ hasText: 'merge' })
      .getByRole('button', { name: /Open related post/ })
      .click();

    await expect(page.locator('.post-item[data-highlighted="true"] p')).toHaveText(olderText);
    await expect(relatedTexts).toHaveText([olderText, newerText]);
    await expect(page.locator('.related-item').first().locator('.related-reason')).toContainText([
      'Echoes sync · recovery · policy',
      'Revisited 1x',
    ]);

    const events = await page.evaluate(
      key => JSON.parse(window.localStorage.getItem(key) ?? '[]') as unknown[],
      POST_EVENT_STORAGE_KEY,
    );
    const relatedOpenEvent = events.find(
      (event): event is Record<string, unknown> =>
        typeof event === 'object' &&
        event !== null &&
        (event as Record<string, unknown>).type === 'related_opened',
    );
    expect(relatedOpenEvent).toMatchObject({
      type: 'related_opened',
      postId: 'post-sync-merge',
    });
    expect(Object.prototype.hasOwnProperty.call(relatedOpenEvent ?? {}, 'queryText')).toBe(false);
  });
});
