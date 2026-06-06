import { test, expect, type Page } from '@playwright/test';
import { dispatchExternalCrdtChanged } from './support/dom-events';

const resizeHandleSelector = '.panel-resize-handle.outline-resize-handle';

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

async function resizeHandleChrome(page: Page) {
  return page.locator(resizeHandleSelector).evaluate((el) => {
    const style = getComputedStyle(el as HTMLElement);
    const after = getComputedStyle(el as HTMLElement, '::after');
    return {
      className: (el as HTMLElement).className,
      display: style.display,
      position: style.position,
      top: style.top,
      right: style.right,
      bottom: style.bottom,
      width: style.width,
      zIndex: style.zIndex,
      borderTopWidth: style.borderTopWidth,
      backgroundColor: style.backgroundColor,
      afterPosition: after.position,
      afterTop: after.top,
      afterBottom: after.bottom,
      afterLeft: after.left,
      afterWidth: after.width,
      afterBackground: after.backgroundColor,
      afterOpacity: after.opacity,
      afterBoxShadow: after.boxShadow,
      focusVisible: el.matches(':focus-visible'),
      outlineWidth: style.outlineWidth,
      outlineStyle: style.outlineStyle,
      outlineColor: style.outlineColor,
      outlineOffset: style.outlineOffset,
    };
  });
}

async function focusResizeHandleWithKeyboard(page: Page) {
  const handle = page.locator(resizeHandleSelector);
  await page.evaluate(() => {
    const active = document.activeElement;
    if (active instanceof HTMLElement) active.blur();
  });
  for (let i = 0; i < 80; i += 1) {
    await page.keyboard.press('Tab');
    if (await handle.evaluate((el) => el === document.activeElement)) {
      return;
    }
  }
  throw new Error('Resize handle was not reachable by keyboard tab order');
}

test.describe('Outline panel resizable behavior', () => {
  test('uses the compact default width on tablet before resizing', async ({ page }) => {
    await page.setViewportSize({ width: 1000, height: 720 });
    await waitForEditor(page);

    await expect.poll(() => outlineWidth(page)).toBe(180);
  });

  test('Tailwind-owned resize handle chrome styles desktop states', async ({ page }) => {
    await waitForEditor(page);
    const handle = page.getByRole('separator', { name: 'Resize width' });
    await expect(handle).toBeVisible();

    const styles = await resizeHandleChrome(page);
    expect(styles.className).toContain('panel-resize-handle outline-resize-handle');
    expect(styles.display).toBe('block');
    expect(styles.position).toBe('absolute');
    expect(styles.top).toBe('0px');
    expect(styles.right).toBe('0px');
    expect(styles.bottom).toBe('0px');
    expect(styles.width).toBe('8px');
    expect(styles.zIndex).toBe('2');
    expect(styles.borderTopWidth).toBe('0px');
    expect(styles.backgroundColor).toBe('rgba(0, 0, 0, 0)');
    expect(styles.afterPosition).toBe('absolute');
    expect(styles.afterTop).toBe('0px');
    expect(styles.afterBottom).toBe('0px');
    expect(styles.afterLeft).toBe('3px');
    expect(styles.afterWidth).toBe('1px');
    expect(styles.afterBackground).toBe('rgb(40, 40, 62)');
    expect(styles.afterOpacity).toBe('0');

    await handle.hover();
    await expect
      .poll(async () => (await resizeHandleChrome(page)).afterOpacity)
      .toBe('1');
    await expect
      .poll(async () => (await resizeHandleChrome(page)).afterBackground)
      .toBe('rgb(130, 80, 223)');
    expect((await resizeHandleChrome(page)).afterBoxShadow).toContain(
      'rgba(130, 80, 223, 0.45)',
    );

    await page.mouse.move(20, 20);
    await focusResizeHandleWithKeyboard(page);
    await expect
      .poll(async () => (await resizeHandleChrome(page)).focusVisible)
      .toBe(true);
    const focused = await resizeHandleChrome(page);
    expect(focused.outlineWidth).toBe('2px');
    expect(focused.outlineStyle).toBe('solid');
    expect(focused.outlineColor).toBe('rgb(160, 112, 239)');
    expect(focused.outlineOffset).toBe('-2px');
    await expect
      .poll(async () => (await resizeHandleChrome(page)).afterOpacity)
      .toBe('1');
    await expect
      .poll(async () => (await resizeHandleChrome(page)).afterBackground)
      .toBe('rgb(130, 80, 223)');
    expect((await resizeHandleChrome(page)).afterBoxShadow).toContain(
      'rgba(130, 80, 223, 0.45)',
    );
  });

  test('Tailwind-owned resize handle is hidden on mobile', async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 844 });
    await waitForEditor(page);

    const handle = page.locator(resizeHandleSelector);
    await expect(handle).toBeHidden();
    expect((await resizeHandleChrome(page)).display).toBe('none');

    await page.setViewportSize({ width: 390, height: 844 });
    await expect(handle).toBeHidden();
    expect((await resizeHandleChrome(page)).display).toBe('none');
  });

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
