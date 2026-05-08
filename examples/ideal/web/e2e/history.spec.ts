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
  });
});
