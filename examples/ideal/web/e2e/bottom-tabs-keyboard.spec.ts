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
