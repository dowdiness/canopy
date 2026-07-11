import { test, expect } from '@playwright/test';

async function waitForEditorReady(page: import('@playwright/test').Page) {
  await page.goto('/');
  await expect(page).toHaveTitle('Canopy Editor');
  await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
  await page.waitForFunction(() => {
    return document.querySelector('#canopy-text-editor .cm-editor') !== null;
  }, { timeout: 10000 });
}

test.describe('Bottom panel — Incr Graph', () => {
  test('IncrGraph tab renders an SVG of the parser runtime', async ({ page }) => {
    await waitForEditorReady(page);

    // Reveal the bottom panel and switch to the IncrGraph tab.
    await page.getByRole('button', { name: 'Panels' }).click();
    await page.getByRole('tab', { name: 'Incr Graph' }).click();

    // The container is mounted via inner_html. The model-owned tap is
    // attached BEFORE `set_text` in init_model, so the initial-parse memo
    // recomputes triggered by set_text + outline-state construction are
    // observed. Assert the SVG without any keystroke fallback — if this
    // ever fails, the init-before-reads invariant has regressed.
    const panel = page.locator('#canopy-incr-container');
    await expect(panel).toBeVisible();
    await expect(panel.locator('svg')).toHaveCount(1, { timeout: 5000 });
  });

  test('IncrGraph tab renders a status-color legend beside the SVG', async ({
    page,
  }) => {
    await waitForEditorReady(page);
    await page.getByRole('button', { name: 'Panels' }).click();
    await page.getByRole('tab', { name: 'Incr Graph' }).click();

    const panel = page.locator('#canopy-incr-container');
    await expect(panel).toBeVisible();
    await expect(panel.locator('svg')).toHaveCount(1, { timeout: 5000 });

    // The legend is a sibling of the role="img" SVG region — a fixed key
    // for the four VisualNodeStatus colors.
    const legend = panel.locator('.incr-legend');
    await expect(legend).toBeVisible();
    await expect(legend.locator('.incr-legend-item')).toHaveCount(4);
    for (const label of ['Idle', 'Recomputing', 'Changed', 'Failed']) {
      await expect(legend.getByText(label, { exact: true })).toBeVisible();
    }

    // Swatch colors come from the visualizer lib's status palette
    // (VisualNodeStatus::fill / ::stroke). Assert the "Failed" swatch carries
    // that fill so the legend can't silently render colorless chips.
    const failedSwatch = legend
      .locator('.incr-legend-item', { hasText: 'Failed' })
      .locator('.incr-legend-swatch');
    await expect(failedSwatch).toHaveAttribute('style', /#f3d6d8/);

    await page.screenshot({ path: 'test-results/incr-graph-legend.png' });
  });
});
