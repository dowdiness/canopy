import { test, expect, type Page } from '@playwright/test';
import { dispatchExternalCrdtChanged } from './support/dom-events';

async function waitForEditor(page: Page) {
  await page.goto('/');
  await expect(page).toHaveTitle('Canopy Editor');
  await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
  await page.waitForFunction(() => {
    return document.querySelector('#canopy-text-editor .cm-editor') !== null;
  }, { timeout: 10000 });
}

async function outlineWidth(page: Page) {
  return Math.round(await page.locator('.outline-panel').evaluate((el) => {
    return (el as HTMLElement).getBoundingClientRect().width;
  }));
}

test.describe('Outline panel resizable behavior', () => {
  test('mouse drag widens the real outline panel', async ({ page }) => {
    await waitForEditor(page);
    const handle = page.getByRole('separator', { name: 'Resize width' });
    await expect(handle).toBeVisible();

    const before = await outlineWidth(page);
    const box = await handle.boundingBox();
    expect(box).not.toBeNull();
    if (!box) return;

    const y = box.y + box.height / 2;
    await page.mouse.move(box.x + box.width / 2, y);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width / 2 + 64, y, { steps: 6 });
    await page.mouse.up();

    await expect.poll(() => outlineWidth(page)).toBeGreaterThan(before + 40);
  });

  test('keyboard arrows nudge the outline panel width', async ({ page }) => {
    await waitForEditor(page);
    const handle = page.getByRole('separator', { name: 'Resize width' });
    await expect(handle).toHaveAttribute('aria-orientation', 'vertical');

    const before = await outlineWidth(page);
    await handle.focus();
    await page.keyboard.press('ArrowRight');
    await expect.poll(() => outlineWidth(page)).toBe(before + 8);

    await page.keyboard.press('ArrowLeft');
    await expect.poll(() => outlineWidth(page)).toBe(before);
  });

  test('resize handle stays pinned while the outline tree scrolls', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 420 });
    await waitForEditor(page);
    const source = Array.from({ length: 120 }, (_, i) => `let v${i} = ${i}`).join('\n');
    await page.evaluate((text) => {
      const g = globalThis as any;
      g.__canopy_crdt.set_text(g.__canopy_crdt_handle, text);
    }, source);
    await dispatchExternalCrdtChanged(page);

    const handle = page.getByRole('separator', { name: 'Resize width' });
    await expect(handle).toBeVisible();
    const before = await handle.boundingBox();
    expect(before).not.toBeNull();
    if (!before) return;

    const scrollState = await page.evaluate(() => {
      const panel = document.querySelector('.outline-panel') as HTMLElement;
      const tree = document.querySelector('.tree-rows') as HTMLElement;
      panel.scrollTop = 160;
      tree.scrollTop = 160;
      return {
        panelScrollTop: panel.scrollTop,
        treeScrollTop: tree.scrollTop,
        treeCanScroll: tree.scrollHeight > tree.clientHeight,
      };
    });
    expect(scrollState.panelScrollTop).toBe(0);
    expect(scrollState.treeCanScroll).toBe(true);
    expect(scrollState.treeScrollTop).toBeGreaterThan(0);

    const after = await handle.boundingBox();
    expect(after).not.toBeNull();
    if (!after) return;
    expect(Math.round(after.x)).toBe(Math.round(before.x));
    expect(Math.round(after.y)).toBe(Math.round(before.y));
  });
});
