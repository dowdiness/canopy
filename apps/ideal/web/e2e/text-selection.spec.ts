import { test, expect } from '@playwright/test';

test('removing the inspected node clears selection without interrupting Text input', async ({ page }) => {
  await page.goto('/');
  const node = page.getByRole('treeitem', { name: '42', exact: true });
  const inspector = page.getByLabel('Node inspector');
  const content = page.locator('#canopy-text-editor .cm-content');

  await node.click();
  await expect(node).toHaveAttribute('aria-selected', 'true');
  await expect(inspector.getByRole('button', { name: 'Delete', exact: true })).toBeVisible();

  await content.focus();
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.insertText('0');

  await expect(inspector).toContainText('Click a node in the outline or editor to inspect it');
  await expect(page.getByRole('treeitem', { selected: true })).toHaveCount(0);
  await expect(content).toBeFocused();
  await page.keyboard.insertText('1');
  await expect(content).toHaveText('01');
});
