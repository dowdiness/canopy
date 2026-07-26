import { expect, test } from '@playwright/test';

const expectedDemos = [
  ['Mini-ML Editor', '/ml'],
  ['JSON Editor', '/json'],
  ['Markdown Editor', '/markdown'],
  ['Canopy Memo', '/memo'],
  ['Posts', '/posts'],
  ['Session Resume', '/resume'],
  ['Generative UI', '/genui'],
  ['Journey Proposals', '/journey'],
] as const;

test('server-renders the complete canonical demo catalog at the Waku root', async ({ request }) => {
  const response = await request.get('/');
  expect(response.status()).toBe(200);

  const html = await response.text();
  for (const [title, href] of expectedDemos) {
    expect(html).toContain(title);
    expect(html).toContain(`href="${href}"`);
  }
});

test('/index.html renders the same Hub without redirecting', async ({ request }) => {
  const root = await request.get('/');
  const compatibility = await request.get('/index.html', { maxRedirects: 0 });
  const rootHtml = await root.text();
  const compatibilityHtml = await compatibility.text();

  expect(compatibility.status()).toBe(200);
  expect(compatibility.headers()).not.toHaveProperty('location');
  for (const [title, href] of expectedDemos) {
    expect(rootHtml).toContain(`${title}</strong>`);
    expect(compatibilityHtml).toContain(`${title}</strong>`);
    expect(compatibilityHtml).toContain(`href="${href}"`);
  }
});

test('unknown routes return the accessible custom page with HTTP 404', async ({ page }) => {
  const response = await page.goto('/missing-demo');

  expect(response?.status()).toBe(404);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Demo not found');
  await expect(page.getByRole('link', { name: 'Back to demos' })).toHaveAttribute('href', '/');
});

test('keeps all Hub choices usable without overflow at desktop and mobile widths', async ({ page }) => {
  for (const viewport of [
    { width: 1280, height: 800 },
    { width: 390, height: 844 },
  ]) {
    await page.setViewportSize(viewport);
    await page.goto('/');

    const links = page.locator('[data-demo-id]');
    await expect(links).toHaveCount(expectedDemos.length);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth))
      .toBe(true);
    for (const link of await links.all()) {
      const box = await link.boundingBox();
      expect(box?.height).toBeGreaterThanOrEqual(44);
      expect(box?.width).toBeGreaterThanOrEqual(44);
    }
  }
});

test('pre-commit failure restores the source without an extra Back stop', async ({ page }) => {
  await page.goto('/foundation');
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.route('**/RSC/R/json.txt?**', (route) => route.abort('failed'));

  await page.getByRole('link', { name: /JSON Editor/ }).click();

  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Canopy demos');
  await expect(page.getByRole('alert')).toContainText('The demo could not be loaded.');
  await expect(page.getByRole('button', { name: 'Retry' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Open directly' })).toHaveAttribute('href', '/json');

  await page.unroute('**/RSC/R/json.txt?**');
  await page.goBack();
  await expect(page).toHaveURL(/\/foundation$/);
});

test('does not intercept modified Hub clicks', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  await page.evaluate(() => {
    (window as Window & { __modifiedClickPrevented?: boolean }).__modifiedClickPrevented = true;
    document.addEventListener('click', (event) => {
      (window as Window & { __modifiedClickPrevented?: boolean }).__modifiedClickPrevented =
        event.defaultPrevented;
    }, { once: true });
  });

  await page.getByRole('link', { name: /JSON Editor/ }).dispatchEvent('click', {
    button: 0,
    ctrlKey: true,
  });

  expect(await page.evaluate(
    () => (window as Window & { __modifiedClickPrevented?: boolean }).__modifiedClickPrevented,
  )).toBe(false);
  await expect(page).toHaveURL(/\/$/);
});

test('Back restores the Hub history entry scroll position', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 500 });
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  const journeyLink = page.getByRole('link', { name: /Journey Proposals/ });
  await journeyLink.scrollIntoViewIfNeeded();
  const hubScroll = await page.evaluate(() => window.scrollY);
  expect(hubScroll).toBeGreaterThan(0);

  await journeyLink.click();
  await expect(page).toHaveURL(/\/journey$/);
  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole('heading', { level: 1 })).toBeFocused();
  await page.waitForTimeout(250);
  expect(await page.evaluate(() => window.scrollY)).toBe(hubScroll);
});

test('push, Back, and Forward keep one Waku history chain and focus each route heading', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');

  await page.getByRole('link', { name: /JSON Editor/ }).click();
  await expect(page).toHaveURL(/\/json$/);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('JSON Editor');
  await expect(page.getByRole('heading', { level: 1 })).toBeFocused();

  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Canopy demos');
  await expect(page.getByRole('heading', { level: 1 })).toBeFocused();

  await page.goForward();
  await expect(page).toHaveURL(/\/json$/);
  await expect(page.getByRole('heading', { level: 1 })).toBeFocused();
});
