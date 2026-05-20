// E2E test: outline tree keyboard navigation using navigate_proj.
import { test, expect } from '@playwright/test';

test.describe('Outline keyboard navigation', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await expect(page).toHaveTitle('Canopy Editor');
    // Load the "Basics" example (small tree with multiple let bindings)
    await page.getByRole('button', { name: 'Basics' }).click();
    // Wait for outline to render
    await expect(page.getByLabel('AST outline')).toBeVisible();
  });

  /** Click a node to select it, then focus the tree-rows container for keyboard events. */
  async function selectAndFocus(page: import('@playwright/test').Page, label: string | RegExp) {
    const outline = page.getByLabel('AST outline');
    const node = outline.locator('.tree-label-text', { hasText: label }).first();
    await node.click();
    // Focus the tree-rows container (has on_keydown + tabindex=0)
    await outline.locator('.tree-rows').focus();
    await expect(outline.locator('.tree-row.selected')).toBeVisible();
  }

  function selectedLabel(page: import('@playwright/test').Page) {
    return page.getByLabel('AST outline').locator('.tree-row.selected .tree-label-text');
  }

  test('click selects a node in the outline', async ({ page }) => {
    await selectAndFocus(page, 'App');
    await expect(selectedLabel(page)).toBeVisible();
  });

  test('ArrowDown navigates to first child', async ({ page }) => {
    await selectAndFocus(page, /^module/);
    const before = await selectedLabel(page).textContent();

    await page.keyboard.press('ArrowDown');
    await expect(selectedLabel(page)).not.toHaveText(before!);
  });

  test('ArrowUp from child navigates to parent', async ({ page }) => {
    await selectAndFocus(page, 'App');
    const before = await selectedLabel(page).textContent();
    expect(before).toContain('App');

    await page.keyboard.press('ArrowUp');
    await expect(selectedLabel(page)).not.toHaveText(before!);
  });

  test('ArrowRight navigates to next sibling', async ({ page }) => {
    await selectAndFocus(page, /^module/);
    await page.keyboard.press('ArrowDown');
    const firstChild = await selectedLabel(page).textContent();

    await page.keyboard.press('ArrowRight');
    await expect(selectedLabel(page)).not.toHaveText(firstChild!);
  });

  test('ArrowLeft navigates to previous sibling', async ({ page }) => {
    await selectAndFocus(page, /^module/);
    await page.keyboard.press('ArrowDown');
    await page.keyboard.press('ArrowRight');
    const secondChild = await selectedLabel(page).textContent();

    await page.keyboard.press('ArrowLeft');
    await expect(selectedLabel(page)).not.toHaveText(secondChild!);
  });

  test('ArrowUp from root does nothing', async ({ page }) => {
    await selectAndFocus(page, /^module/);
    const before = await selectedLabel(page).textContent();

    await page.keyboard.press('ArrowUp');
    // Should stay on same node
    await expect(selectedLabel(page)).toHaveText(before!);
  });

  test('round-trip: Down then Up returns to same node', async ({ page }) => {
    await selectAndFocus(page, /^module/);
    const original = await selectedLabel(page).textContent();

    await page.keyboard.press('ArrowDown');
    await expect(selectedLabel(page)).not.toHaveText(original!);

    await page.keyboard.press('ArrowUp');
    await expect(selectedLabel(page)).toHaveText(original!);
  });

  test('click scrolls selected text into view', async ({ page }) => {
    const source = Array.from({ length: 120 }, (_, i) => `let v${i} = ${i}`).join('\n');
    await page.evaluate((text) => {
      const g = globalThis as any;
      g.__canopy_crdt.set_text(g.__canopy_crdt_handle, text);
      document.getElementById('canopy-external-crdt-changed-trigger')?.click();
    }, source);
    const targetNode = page.getByLabel('AST outline')
      .locator('.tree-label-text', { hasText: /^119$/ })
      .first();
    await expect(targetNode).toHaveText('119');

    await page.evaluate(() => {
      const scroller = document.querySelector('#canopy-text-editor .cm-scroller') as HTMLElement | null;
      if (scroller) scroller.scrollTop = 0;
    });

    await targetNode.click();

    await expect.poll(async () => {
      return page.evaluate(() => {
        const scroller = document.querySelector('#canopy-text-editor .cm-scroller') as HTMLElement | null;
        return scroller?.scrollTop ?? 0;
      });
    }, { timeout: 5000 }).toBeGreaterThan(0);
  });
});
