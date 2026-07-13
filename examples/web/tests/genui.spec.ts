import { test, expect } from '@playwright/test';

test.describe('Generative UI Demo', () => {
  test('page loads and shows initial state', async ({ page }) => {
    await page.goto('/genui.html');
    await expect(page.locator('h1')).toHaveText('Generative UI');
    await expect(page.locator('#step-num')).toHaveText('—');
  });

  test('loads preset example', async ({ page }) => {
    await page.goto('/genui.html');
    await page.locator('button[data-example="0"]').click();
    const textarea = page.locator('#source-input');
    const val = await textarea.inputValue();
    expect(val.length).toBeGreaterThan(10);
    expect(val).toContain('div');
  });

  test('renders the host-owned JSON fixture as a table', async ({ page }) => {
    await page.goto('/genui.html');
    const table = page.getByRole('table', { name: 'Orders' });
    const rows = table.locator('tbody').getByRole('row');
    await expect(rows).toHaveCount(6);
    await expect(page.getByTestId('data-row-count')).toHaveText('6');
    await expect(page.getByTestId('data-summary-count')).toHaveText('6');
    await expect(page.getByTestId('data-summary-total')).toHaveText('$6,846.50');
    await expect(page.getByTestId('data-summary-average')).toHaveText('$1,141.08');
    await expect(rows.filter({ hasText: 'Acme renewal' })).toContainText('$1,280.50');
  });

  test('filters rows while preserving a selected host-owned row', async ({ page }) => {
    await page.goto('/genui.html');
    const table = page.getByRole('table', { name: 'Orders' });
    const rows = table.locator('tbody').getByRole('row');
    await page.getByTestId('order-row-ord-1002').click();
    await expect(page.getByRole('status')).toHaveText('Selected: Northstar onboarding (ord-1002)');
    await expect(page.getByTestId('data-detail-name')).toHaveText('Northstar onboarding');
    await expect(page.getByTestId('data-detail-name')).toBeVisible();

    await page.getByLabel('Filter name, status, or ID').fill('paid');
    await expect(rows).toHaveCount(3);
    await expect(page.getByTestId('data-row-count')).toHaveText('3');
    await expect(page.getByTestId('data-summary-count')).toHaveText('3');
    await expect(page.getByTestId('data-summary-total')).toHaveText('$2,486.50');
    await expect(page.getByTestId('data-summary-average')).toHaveText('$828.83');
    await expect(page.getByRole('status')).toHaveText('Selected: Northstar onboarding (ord-1002) — hidden by filter.');

    await page.getByRole('button', { name: 'Clear filter' }).click();
    await expect(rows).toHaveCount(6);
    await expect(page.getByTestId('order-row-ord-1002')).toHaveAttribute('aria-selected', 'true');
  });

  test('preserves keyboard focus when selecting a row', async ({ page }) => {
    await page.goto('/genui.html');
    const row = page.getByTestId('order-row-ord-1003');
    await row.focus();
    await row.press('Enter');
    await expect(row).toHaveAttribute('aria-selected', 'true');
    await expect(row).toBeFocused();
    await expect(page.getByTestId('data-detail-name')).toBeVisible();
  });

  test('switches to the CSV fixture while preserving detail and selection', async ({ page }) => {
    await page.goto('/genui.html');
    await page.getByTestId('order-row-ord-1004').click();
    await expect(page.getByTestId('data-detail-id')).toHaveText('ord-1004');
    await expect(page.getByTestId('data-detail-amount')).toHaveText('$2,180.00');

    const csvSource = page.getByRole('button', { name: 'CSV fixture' });
    await csvSource.click();
    await expect(csvSource).toHaveAttribute('aria-pressed', 'true');
    await expect(page.getByRole('button', { name: 'JSON fixture' })).toHaveAttribute('aria-pressed', 'false');
    await expect(page.getByTestId('data-row-count')).toHaveText('6');
    await expect(page.getByTestId('data-detail-name')).toHaveText('Lumen migration');
    await expect(page.getByRole('status')).toHaveText('Selected: Lumen migration (ord-1004)');
  });

  test('streaming completes and shows tree + HTML nodes', async ({ page }) => {
    test.setTimeout(60000);

    await page.goto('/genui.html');
    await page.locator('button[data-example="0"]').click();

    await page.locator('#stream-btn').click();

    // Wait for streaming complete
    await expect(page.locator('#status-bar')).toContainText('DOM nodes rendered', { timeout: 45000 });

    // Verify tree output
    const treeHtml = await page.locator('#tree-output').innerHTML();
    expect(treeHtml).toContain('node-id');
    expect(treeHtml).toContain('Root');

    // Verify HTML rendered preview shows elements
    const htmlContent = await page.locator('#html-preview').innerHTML();
    expect(htmlContent.length).toBeGreaterThan(10);
    expect(htmlContent).not.toContain('Stream JSX to see rendered output.');

    const heading = page.locator('#html-preview h1');
    const headingStyle = await heading.evaluate((element) => {
      const style = getComputedStyle(element);
      return {
        borderLeftWidth: style.borderLeftWidth,
        paddingLeft: style.paddingLeft,
      };
    });
    expect(headingStyle).toEqual({
      borderLeftWidth: '0px',
      paddingLeft: '0px',
    });
    await expect(heading).toHaveAttribute('data-node-id', /\d+/);

    // Verify DOM node count is shown
    const nodeCount = await page.locator('#html-node-count').textContent();
    expect(parseInt(nodeCount)).toBeGreaterThan(0);
  });

  test('multiple examples produce DOM nodes', async ({ page }) => {
    test.setTimeout(90000);

    await page.goto('/genui.html');

    for (let i = 0; i < 3; i++) {
      await page.locator(`button[data-example="${i}"]`).click();
      await page.locator('#stream-btn').click();
      await expect(page.locator('#status-bar')).toContainText('DOM nodes rendered', { timeout: 45000 });
    }
  });
  test('generates and commits the constrained data candidate through the browser action', async ({ page }) => {
    await page.goto('/genui.html');
    await page.getByRole('button', { name: 'Generate candidate' }).click();
    await expect(page.locator('#status-bar')).toContainText(
      'Candidate committed through replay, validation, dry-run, and DOM apply.',
    );
    await expect(page.locator('#html-preview [data-genui-kind="stack"]')).toBeVisible();
    await expect(page.locator('#html-preview [data-genui-kind="table"]')).toHaveCount(1);
    await expect(page.locator('#html-preview')).toContainText('Orders');
  });

});
