import { test, expect, type Page } from '@playwright/test';
import { getEditorText } from './support/editor-state';

async function enterStructureMode(page: Page) {
  await page.getByRole('button', { name: 'Structure' }).click();
  await expect(page.locator('canopy-editor .structure-let_def').first()).toBeVisible();
}

async function deleteFirstDefinition(page: Page) {
  await page.locator('canopy-editor .structure-let_def').first().click();
  await page.keyboard.press('Backspace');
}

async function waitForNextFrame(page: Page) {
  await page.evaluate(() => new Promise<void>(resolve => {
    requestAnimationFrame(() => resolve());
  }));
}

test('Structure Delete changes the document without legacy events', async ({ page }) => {
  await page.goto('/');
  await enterStructureMode(page);
  await page.evaluate(() => {
    const counts = { requests: 0, applied: 0 };
    (globalThis as any).__legacyStructureEventCounts = counts;
    document.addEventListener('structural-edit-request', () => { counts.requests += 1; });
    document.addEventListener('structural-edit-applied', () => { counts.applied += 1; });
  });

  const before = await getEditorText(page);
  await deleteFirstDefinition(page);

  await expect.poll(() => getEditorText(page)).not.toBe(before);
  expect(await page.evaluate(() =>
    (globalThis as any).__legacyStructureEventCounts,
  )).toEqual({ requests: 0, applied: 0 });
});

test('Structure shortcuts undo and redo one structural edit', async ({ page }) => {
  await page.goto('/');
  await enterStructureMode(page);

  const before = await getEditorText(page);
  await deleteFirstDefinition(page);
  await expect.poll(() => getEditorText(page)).not.toBe(before);
  const deleted = await getEditorText(page);

  await page.keyboard.press('Control+z');
  await expect.poll(() => getEditorText(page)).toBe(before);
  await page.keyboard.press('Control+Shift+z');
  await expect.poll(() => getEditorText(page)).toBe(deleted);
});

test('Structure history survives mode reactivation', async ({ page }) => {
  await page.goto('/');
  await enterStructureMode(page);

  const before = await getEditorText(page);
  await deleteFirstDefinition(page);
  await expect.poll(() => getEditorText(page)).not.toBe(before);

  await page.getByRole('button', { name: 'Text' }).click();
  await expect(page.locator('#canopy-text-editor .cm-content')).toBeVisible();
  await enterStructureMode(page);
  await page.locator('canopy-editor .structure-let_def').first().click();
  await page.keyboard.press('Control+z');

  await expect.poll(() => getEditorText(page)).toBe(before);
});

test('readonly Structure shortcuts do not mutate', async ({ page }) => {
  await page.goto('/');
  await enterStructureMode(page);

  const before = await getEditorText(page);
  await deleteFirstDefinition(page);
  await expect.poll(() => getEditorText(page)).not.toBe(before);
  const deleted = await getEditorText(page);
  await page.locator('canopy-editor').evaluate(editor => {
    editor.setAttribute('readonly', '');
  });
  await page.locator('canopy-editor .structure-let_def').first().click();

  for (const shortcut of ['Backspace', 'Control+z']) {
    await page.keyboard.press(shortcut);
    await waitForNextFrame(page);
    expect(await getEditorText(page)).toBe(deleted);
  }
});
