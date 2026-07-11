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

  test('streaming completes and shows tree + HTML nodes', async ({ page }) => {
    test.setTimeout(60000);

    await page.goto('/genui.html');
    await page.locator('button[data-example="0"]').click();
    await page.waitForTimeout(500);

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
      await page.waitForTimeout(300);
      await page.locator('#stream-btn').click();
      await expect(page.locator('#status-bar')).toContainText('DOM nodes rendered', { timeout: 45000 });
      await page.waitForTimeout(500);
    }
  });
});
