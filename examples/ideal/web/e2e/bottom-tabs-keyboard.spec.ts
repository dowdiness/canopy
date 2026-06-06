import { test, expect } from '@playwright/test';

// Keyboard navigation for the bottom-panel tablist, now driven by the headless
// `@tabs` behavior (lib/tabs). Automatic activation: Arrow/Home/End immediately
// move selection AND focus. Horizontal model only — ArrowUp/Down are ignored
// (APG reserves them for scrolling).

async function openBottomTabs(page: import('@playwright/test').Page) {
  await page.goto('/');
  await expect(page).toHaveTitle('Canopy Editor');
  await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
  await page.waitForFunction(
    () => document.querySelector('#canopy-text-editor .cm-editor') !== null,
    { timeout: 10000 },
  );
  await page.getByRole('button', { name: 'Panels' }).click();
  await expect(page.getByRole('tab', { name: 'Problems' })).toBeVisible();
}

test.describe('Bottom Panel Tabs — keyboard navigation', () => {
  test.beforeEach(async ({ page }) => {
    await openBottomTabs(page);
    // Establish a known starting point: click selects + focuses the first tab.
    await page.getByRole('tab', { name: 'Problems' }).click();
    await expect(page.getByRole('tab', { name: 'Problems' })).toHaveAttribute(
      'aria-selected',
      'true',
    );
  });

  test('ArrowRight / ArrowLeft move selection and focus', async ({ page }) => {
    const problems = page.getByRole('tab', { name: 'Problems' });
    const opLog = page.getByRole('tab', { name: 'Op Log' });

    await problems.press('ArrowRight');
    await expect(opLog).toHaveAttribute('aria-selected', 'true');
    await expect(opLog).toBeFocused();
    await expect(problems).toHaveAttribute('aria-selected', 'false');
    // Roving tabindex: the selected tab is the only one in the Tab sequence.
    await expect(opLog).toHaveAttribute('tabindex', '0');
    await expect(problems).toHaveAttribute('tabindex', '-1');

    await opLog.press('ArrowLeft');
    await expect(problems).toHaveAttribute('aria-selected', 'true');
    await expect(problems).toBeFocused();
  });

  test('ArrowLeft from the first tab wraps to the last', async ({ page }) => {
    const problems = page.getByRole('tab', { name: 'Problems' });
    const incrGraph = page.getByRole('tab', { name: 'Incr Graph' });

    await problems.press('ArrowLeft');
    await expect(incrGraph).toHaveAttribute('aria-selected', 'true');
    await expect(incrGraph).toBeFocused();
  });

  test('Home and End jump to the ends', async ({ page }) => {
    const problems = page.getByRole('tab', { name: 'Problems' });
    const incrGraph = page.getByRole('tab', { name: 'Incr Graph' });

    await problems.press('End');
    await expect(incrGraph).toHaveAttribute('aria-selected', 'true');
    await expect(incrGraph).toBeFocused();

    await incrGraph.press('Home');
    await expect(problems).toHaveAttribute('aria-selected', 'true');
    await expect(problems).toBeFocused();
  });

  // This covers that vertical arrows don't move selection/focus. That they also
  // don't suppress page scroll (no over-eager preventDefault) is guaranteed
  // structurally — nav_target returns None for these keys, so the keydown handler
  // never calls prevent_default — and is asserted at the unit level by the
  // "nav_target ignores vertical arrows" test in lib/tabs/src/tabs/tabs_wbtest.mbt.
  test('ArrowUp / ArrowDown do not change the selected tab', async ({ page }) => {
    const problems = page.getByRole('tab', { name: 'Problems' });

    await problems.press('ArrowDown');
    await expect(problems).toHaveAttribute('aria-selected', 'true');
    await expect(problems).toBeFocused();

    await problems.press('ArrowUp');
    await expect(problems).toHaveAttribute('aria-selected', 'true');
    await expect(problems).toBeFocused();
  });

  test('selected tab is wired to its panel via ARIA', async ({ page }) => {
    const crdtTab = page.getByRole('tab', { name: 'CRDT State' });
    await crdtTab.click();
    await expect(crdtTab).toHaveAttribute('aria-selected', 'true');
    // aria-controls is set only on the selected tab; wait for the re-render.
    await expect(crdtTab).toHaveAttribute('aria-controls', /\S+/);

    const controls = await crdtTab.getAttribute('aria-controls');
    expect(controls).toBeTruthy();
    const panel = page.locator(`#${controls}`);
    await expect(panel).toHaveAttribute('role', 'tabpanel');
    // aria-labelledby points back at the (behavior-owned) tab button id.
    const labelledby = await panel.getAttribute('aria-labelledby');
    expect(labelledby).toBe(await crdtTab.getAttribute('id'));
  });
});

test.describe('Bottom Panel Tabs — Tailwind chrome', () => {
  test('Tailwind-owned bottom tab strip styles desktop active/inactive and hover', async ({
    page,
  }) => {
    await openBottomTabs(page);
    await page.getByRole('tab', { name: 'Problems' }).click();

    const styles = await page.evaluate(() => {
      const byText = (label: string) =>
        Array.from(document.querySelectorAll<HTMLElement>('.bottom-tabs .tab')).find(
          (el) => el.textContent?.trim() === label,
        );
      const strip = document.querySelector<HTMLElement>('.bottom-tabs');
      const active = byText('Problems');
      const inactive = byText('Op Log');
      if (!strip || !active || !inactive) return null;
      const stripStyle = getComputedStyle(strip);
      const activeStyle = getComputedStyle(active);
      const inactiveStyle = getComputedStyle(inactive);
      return {
        stripDisplay: stripStyle.display,
        stripAlignItems: stripStyle.alignItems,
        stripHeight: stripStyle.height,
        stripPaddingLeft: stripStyle.paddingLeft,
        stripGap: stripStyle.gap,
        stripBorder: stripStyle.borderBottomColor,
        activeBackground: activeStyle.backgroundColor,
        activeColor: activeStyle.color,
        activeBorderColor: activeStyle.borderBottomColor,
        activeBorderWidth: activeStyle.borderBottomWidth,
        inactiveBackground: inactiveStyle.backgroundColor,
        inactiveColor: inactiveStyle.color,
        inactiveBorderColor: inactiveStyle.borderBottomColor,
        inactiveMinHeight: inactiveStyle.minHeight,
        inactivePaddingBottom: inactiveStyle.paddingBottom,
      };
    });

    expect(styles).not.toBeNull();
    expect(styles?.stripDisplay).toBe('flex');
    expect(styles?.stripAlignItems).toBe('center');
    expect(styles?.stripHeight).toBe('36px');
    expect(styles?.stripPaddingLeft).toBe('12px');
    expect(styles?.stripGap).toBe('4px');
    expect(styles?.stripBorder).toBe('rgb(40, 40, 62)');
    expect(styles?.activeBackground).toBe('rgba(0, 0, 0, 0)');
    expect(styles?.activeColor).toBe('rgb(176, 144, 224)');
    expect(styles?.activeBorderColor).toBe('rgb(130, 80, 223)');
    expect(styles?.activeBorderWidth).toBe('2px');
    expect(styles?.inactiveBackground).toBe('rgba(0, 0, 0, 0)');
    expect(styles?.inactiveColor).toBe('rgb(138, 138, 170)');
    expect(styles?.inactiveBorderColor).toBe('rgba(0, 0, 0, 0)');
    expect(styles?.inactiveMinHeight).toBe('32px');
    expect(styles?.inactivePaddingBottom).toBe('6px');

    const opLog = page.getByRole('tab', { name: 'Op Log' });
    await opLog.hover();
    await expect
      .poll(async () => opLog.evaluate((el) => getComputedStyle(el).backgroundColor))
      .toBe('rgb(34, 34, 56)');
    await expect
      .poll(async () => opLog.evaluate((el) => getComputedStyle(el).color))
      .toBe('rgb(184, 184, 208)');
  });

  test('Tailwind-owned bottom tab strip keeps mobile touch targets', async ({
    page,
  }) => {
    await openBottomTabs(page);
    await page.setViewportSize({ width: 390, height: 844 });

    const styles = await page.evaluate(() => {
      const strip = document.querySelector<HTMLElement>('.bottom-tabs');
      const tab = Array.from(
        document.querySelectorAll<HTMLElement>('.bottom-tabs .tab'),
      ).find((el) => el.textContent?.trim() === 'Problems');
      if (!strip || !tab) return null;
      const stripStyle = getComputedStyle(strip);
      const tabStyle = getComputedStyle(tab);
      const rect = tab.getBoundingClientRect();
      return {
        stripHeight: stripStyle.height,
        stripMinHeight: stripStyle.minHeight,
        tabMinHeight: tabStyle.minHeight,
        tabMinWidth: tabStyle.minWidth,
        tabPaddingTop: tabStyle.paddingTop,
        tabPaddingBottom: tabStyle.paddingBottom,
        tabHeight: rect.height,
      };
    });

    expect(styles).not.toBeNull();
    expect(
      Number.parseFloat(styles?.stripHeight ?? '0'),
    ).toBeGreaterThanOrEqual(44);
    expect(styles?.stripMinHeight).toBe('44px');
    expect(styles?.tabMinHeight).toBe('44px');
    expect(styles?.tabMinWidth).toBe('44px');
    expect(styles?.tabPaddingTop).toBe('12px');
    expect(styles?.tabPaddingBottom).toBe('10px');
    expect(styles?.tabHeight ?? 0).toBeGreaterThanOrEqual(44);
  });
});
