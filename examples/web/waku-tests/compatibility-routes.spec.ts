import { expect, test } from '@playwright/test';

const compatibilityRoutes = [
  ['/json.html', '/json'],
  ['/markdown.html', '/markdown'],
  ['/memo.html', '/memo'],
  ['/posts.html', '/posts'],
  ['/resume.html', '/resume'],
  ['/genui.html', '/genui'],
  ['/genui-possibilities.html', '/journey'],
] as const;

test('returns permanent redirects for every legacy document and RSC route', async ({ request }) => {
  for (const [legacy, canonical] of compatibilityRoutes) {
    const query = '?source=legacy&mode=review';
    const documentResponse = await request.get(`${legacy}${query}`, { maxRedirects: 0 });
    expect(documentResponse.status(), legacy).toBe(308);
    expect(documentResponse.headers().location, legacy).toBe(`${canonical}${query}`);

    const rscResponse = await request.get(`/RSC/R${legacy}.txt${query}`, { maxRedirects: 0 });
    expect(rscResponse.status(), `RSC ${legacy}`).toBe(308);
    expect(rscResponse.headers().location, `RSC ${legacy}`)
      .toBe(`/RSC/R${canonical}.txt${query}`);
  }
});

test('document redirects preserve query and fragment without an alias Back stop', async ({ page }) => {
  for (const [legacy, canonical] of compatibilityRoutes) {
    await page.goto('/foundation');
    await page.evaluate((href) => window.location.assign(href), `${legacy}?source=document#legacy-focus`);

    await expect(page).toHaveURL(`${canonical}?source=document#legacy-focus`);
    await page.goBack();
    await expect(page).toHaveURL('/foundation');
  }
});

test('Waku client navigation follows the RSC alias with one canonical history entry', async ({ page }) => {
  const canonicalUrl = '/json?source=client&flag=&note=a+b#legacy-focus';
  await page.goto('/foundation');
  await expect(page.locator('[data-route-lifecycle-ready]'))
    .toHaveAttribute('data-route-lifecycle-ready', 'true');
  const initialHistoryLength = await page.evaluate(() => window.history.length);

  const aliasRedirect = page.waitForResponse((response) => {
    const url = new URL(response.url());
    return url.pathname === '/RSC/R/json.html.txt' && response.status() === 308;
  });
  await page.getByRole('link', { name: 'Open the legacy JSON route' }).click();
  await aliasRedirect;

  await expect(page).toHaveURL(canonicalUrl);
  expect(await page.evaluate(() => Object.fromEntries(new URL(location.href).searchParams))).toEqual({
    source: 'client',
    flag: '',
    note: 'a b',
  });
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('{} JSON CRDT Editor');
  await expect(page.getByRole('heading', { level: 1 })).toBeFocused();
  expect(await page.evaluate(() => window.history.length)).toBe(initialHistoryLength + 1);

  await page.goBack();
  await expect(page).toHaveURL('/foundation');
  await expect(page.getByRole('heading', { level: 1 }))
    .toHaveText('Canopy Waku foundation');
  await expect(page.getByRole('heading', { level: 1 })).toBeFocused();
  await page.goForward();
  await expect(page).toHaveURL(canonicalUrl);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('{} JSON CRDT Editor');
  await expect(page.getByRole('heading', { level: 1 })).toBeFocused();
});
