import type { Page } from '@playwright/test';

export async function loggedActions(page: Page): Promise<number> {
  const text = await page.locator('#action-stat').innerText();
  const count = text.match(/\d+/);
  if (!count) throw new Error(`Action count is missing: ${text}`);
  return Number(count[0]);
}
