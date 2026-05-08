import { test, expect } from '@playwright/test';

async function waitForEditor(page: import('@playwright/test').Page) {
  await page.goto('/');
  await expect(page).toHaveTitle('Canopy Editor');
  await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
  await page.waitForFunction(
    () => {
      const ce = document.querySelector('canopy-editor');
      return ce?.shadowRoot?.querySelector('.cm-editor') !== null;
    },
    { timeout: 10000 },
  );
}

async function openBottomPanel(page: import('@playwright/test').Page) {
  // The Panels button toggles the bottom panel; History tab lives inside it.
  await page.getByRole('button', { name: 'Panels' }).click();
}

async function typeInEditor(
  page: import('@playwright/test').Page,
  text: string,
) {
  await page.evaluate(() => {
    const ce = document.querySelector('canopy-editor');
    const cm = ce?.shadowRoot?.querySelector('.cm-content') as HTMLElement;
    cm?.focus();
  });
  await page.keyboard.type(text, { delay: 20 });
}

test.describe('Causal History tab', () => {
  test('renders SVG for the seeded document', async ({ page }) => {
    await waitForEditor(page);
    await openBottomPanel(page);
    await page.getByRole('button', { name: 'History' }).click();
    // Container must exist and end up containing an SVG (Phase 1a output
    // routed through @gv_layout / @gv_svg by history_render_cmd).
    const container = page.locator('#canopy-history-container');
    await expect(container).toBeVisible();
    await expect(container.locator('svg')).toBeVisible({ timeout: 10000 });
    // Legend decoder: "You" chip for the local agent + "now" frontier
    // chip. Without these, color encoding is unreadable.
    const legend = container.locator('.history-legend');
    await expect(legend).toContainText('You');
    await expect(legend).toContainText('now');
  });

  test('refreshes after reopening the bottom panel post-edit', async ({
    page,
  }) => {
    await waitForEditor(page);
    await openBottomPanel(page);
    await page.getByRole('button', { name: 'History' }).click();
    const container = page.locator('#canopy-history-container');
    await expect(container.locator('svg')).toBeVisible({ timeout: 10000 });
    const initialMarkup = await container.innerHTML();

    // Close the panel, edit while hidden, reopen.
    await openBottomPanel(page);
    await typeInEditor(page, 'x');
    await openBottomPanel(page);
    // Without the TogglePanel(Bottom) refresh hook, the container would
    // still hold the pre-edit SVG. Expect the markup to have changed.
    await expect
      .poll(() => container.innerHTML(), { timeout: 10000 })
      .not.toBe(initialMarkup);
  });
});
