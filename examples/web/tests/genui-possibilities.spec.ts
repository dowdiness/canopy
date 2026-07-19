import { expect, test } from '@playwright/test';

const prototypeUrl = process.env.GENUI_POSSIBILITIES_URL ?? '/genui-possibilities.html';

test.describe('generative itinerary decision', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto(prototypeUrl);
  });

  test('response radiogroup supports roving arrow-key navigation', async ({ page }) => {
    const responses = page.getByRole('radio');

    await responses.first().focus();
    await page.keyboard.press('ArrowDown');

    await expect(responses.nth(1)).toBeFocused();
    await expect(responses.nth(1)).toHaveAttribute('aria-checked', 'true');
    await expect(responses.first()).toHaveAttribute('tabindex', '-1');
    await expect(responses.nth(1)).toHaveAttribute('tabindex', '0');

    await page.keyboard.press('End');
    await expect(responses.last()).toBeFocused();
    await expect(responses.last()).toHaveAttribute('aria-checked', 'true');

    await page.keyboard.press('Home');
    await expect(responses.first()).toBeFocused();
    await expect(responses.first()).toHaveAttribute('aria-checked', 'true');

    await page.keyboard.press('Space');
    await expect(responses.first()).toBeFocused();
  });

  test('apply and undo preserve rendered identity and protected itinerary content', async ({ page }) => {
    const itineraryItems = page.locator('#itinerary-list > li');
    const responses = page.getByRole('radio');

    await expect(itineraryItems).toHaveCount(4);
    await expect(responses).toHaveCount(3);
    await page.evaluate(() => {
      document.querySelectorAll('#itinerary-list > li').forEach((node, index) => {
        node.setAttribute('data-node-sentinel', `itinerary-${index}`);
      });
      document.querySelectorAll('[role="radio"]').forEach((node, index) => {
        node.setAttribute('data-node-sentinel', `response-${index}`);
      });
    });

    await responses.first().click();
    await page.getByRole('button', { name: 'Apply to itinerary' }).click();

    await expect(page.locator('#revision-label')).toHaveText('Revision 4');
    await expect(itineraryItems).toHaveCount(4);
    await expect(responses).toHaveCount(3);
    await expect(itineraryItems.nth(3)).toContainText('Chichu Art Museum');
    await expect(itineraryItems.nth(3)).toContainText('Protected');
    for (let index = 0; index < 4; index += 1) {
      await expect(itineraryItems.nth(index)).toHaveAttribute('data-node-sentinel', `itinerary-${index}`);
    }
    for (let index = 0; index < 3; index += 1) {
      await expect(responses.nth(index)).toHaveAttribute('data-node-sentinel', `response-${index}`);
    }
    await expect(responses.first()).toBeFocused();

    await page.getByRole('button', { name: 'Undo last change' }).click();

    await expect(page.locator('#revision-label')).toHaveText('Revision 5');
    await expect(itineraryItems.nth(0)).toContainText('Kyoto Station');
    await expect(itineraryItems.nth(0)).toContainText('14:10');
    for (let index = 0; index < 4; index += 1) {
      await expect(itineraryItems.nth(index)).toHaveAttribute('data-node-sentinel', `itinerary-${index}`);
    }
    for (let index = 0; index < 3; index += 1) {
      await expect(responses.nth(index)).toHaveAttribute('data-node-sentinel', `response-${index}`);
    }
    await expect(responses.first()).toBeFocused();
  });

  test('mobile keeps arrival and cost visible without horizontal overflow', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });

    const firstResponse = page.getByRole('radio').first();
    await expect(firstResponse.getByText('16:05 today')).toBeVisible();
    await expect(firstResponse.getByText('¥0', { exact: true })).toBeVisible();

    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBe(0);
  });
});
