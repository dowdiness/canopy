import { test, expect, type Page } from '@playwright/test';

async function waitForEditorReady(page: Page, path = '/') {
  await page.goto(path);
  await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
  await page.waitForFunction(() => {
    return document.querySelector('#canopy-text-editor .cm-editor') !== null;
  }, { timeout: 10000 });
}

async function selectOutlineNode(page: Page) {
  await page.locator('.tree-row').first().click();
  await expect(page.locator('.inspector-actions .action-btn').first()).toBeVisible({
    timeout: 5000,
  });
}

test.describe('Ideal Tailwind toolbar/button recipes', () => {
  test('Tailwind-owned toolbar chrome styles desktop states', async ({ page }) => {
    await waitForEditorReady(page);

    const styles = await page.evaluate(() => {
      const byText = (selector: string, label: string) =>
        Array.from(document.querySelectorAll<HTMLElement>(selector)).find(
          (el) => el.textContent?.trim() === label,
        );
      const toolbar = document.querySelector<HTMLElement>('.toolbar');
      const title = document.querySelector<HTMLElement>('.toolbar-title');
      const undo = byText('button.toolbar-btn', 'Undo');
      const textTab = byText('button.tab', 'Text');
      const inspectorToggle = byText('button.panel-toggle', 'Inspector');
      if (!toolbar || !title || !undo || !textTab || !inspectorToggle) return null;
      const toolbarStyle = getComputedStyle(toolbar);
      const titleStyle = getComputedStyle(title);
      const undoStyle = getComputedStyle(undo);
      const textTabStyle = getComputedStyle(textTab);
      const inspectorStyle = getComputedStyle(inspectorToggle);
      return {
        toolbarDisplay: toolbarStyle.display,
        toolbarAlignItems: toolbarStyle.alignItems,
        toolbarHeight: toolbarStyle.height,
        toolbarBackground: toolbarStyle.backgroundColor,
        toolbarBorder: toolbarStyle.borderBottomColor,
        toolbarShadow: toolbarStyle.boxShadow,
        titleFontSize: titleStyle.fontSize,
        titleColor: titleStyle.color,
        titleMarginRight: titleStyle.marginRight,
        undoBackground: undoStyle.backgroundColor,
        undoColor: undoStyle.color,
        undoMinHeight: undoStyle.minHeight,
        undoPaddingLeft: undoStyle.paddingLeft,
        undoBorderWidth: undoStyle.borderTopWidth,
        textTabBackground: textTabStyle.backgroundColor,
        textTabColor: textTabStyle.color,
        inspectorBackground: inspectorStyle.backgroundColor,
        inspectorColor: inspectorStyle.color,
      };
    });

    expect(styles).not.toBeNull();
    expect(styles?.toolbarDisplay).toBe('flex');
    expect(styles?.toolbarAlignItems).toBe('center');
    expect(styles?.toolbarHeight).toBe('48px');
    expect(styles?.toolbarBackground).toBe('rgb(18, 18, 31)');
    expect(styles?.toolbarBorder).toBe('rgb(40, 40, 62)');
    expect(styles?.toolbarShadow).toContain('0px 1px 0px');
    expect(styles?.titleFontSize).toBe('16px');
    expect(styles?.titleColor).toBe('rgb(184, 184, 208)');
    expect(styles?.titleMarginRight).toBe('8px');
    expect(styles?.undoBackground).toBe('rgba(0, 0, 0, 0)');
    expect(styles?.undoColor).toBe('rgb(138, 138, 170)');
    expect(styles?.undoMinHeight).toBe('32px');
    expect(styles?.undoPaddingLeft).toBe('12px');
    expect(styles?.undoBorderWidth).toBe('0px');
    expect(styles?.textTabBackground).toBe('rgb(130, 80, 223)');
    expect(styles?.textTabColor).toBe('rgb(255, 255, 255)');
    expect(styles?.inspectorBackground).toBe('rgb(34, 34, 56)');
    expect(styles?.inspectorColor).toBe('rgb(228, 228, 240)');

    const undo = page.getByRole('button', { name: 'Undo' });
    await undo.hover();
    await expect
      .poll(async () => undo.evaluate((el) => getComputedStyle(el).backgroundColor))
      .toBe('rgb(34, 34, 56)');
    await expect
      .poll(async () => undo.evaluate((el) => getComputedStyle(el).color))
      .toBe('rgb(184, 184, 208)');
  });

  test('Tailwind-owned toolbar chrome styles mobile and landscape states', async ({
    page,
  }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await waitForEditorReady(page);

    const mobileStyles = await page.evaluate(() => {
      const byText = (selector: string, label: string) =>
        Array.from(document.querySelectorAll<HTMLElement>(selector)).find(
          (el) => el.textContent?.trim() === label,
        );
      const toolbar = document.querySelector<HTMLElement>('.toolbar');
      const title = document.querySelector<HTMLElement>('.toolbar-title');
      const undo = byText('button.toolbar-btn', 'Undo');
      const basics = byText('button.example-btn', 'Basics');
      if (!toolbar || !title || !undo || !basics) return null;
      const toolbarStyle = getComputedStyle(toolbar);
      const titleStyle = getComputedStyle(title);
      const undoStyle = getComputedStyle(undo);
      const basicsStyle = getComputedStyle(basics);
      return {
        toolbarOverflowX: toolbarStyle.overflowX,
        toolbarGap: toolbarStyle.gap,
        toolbarPaddingLeft: toolbarStyle.paddingLeft,
        titleDisplay: titleStyle.display,
        undoMinHeight: undoStyle.minHeight,
        undoMinWidth: undoStyle.minWidth,
        undoPaddingTop: undoStyle.paddingTop,
        basicsDisplay: basicsStyle.display,
      };
    });

    expect(mobileStyles).not.toBeNull();
    expect(mobileStyles?.toolbarOverflowX).toBe('auto');
    expect(mobileStyles?.toolbarGap).toBe('4px');
    expect(mobileStyles?.toolbarPaddingLeft).toBe('8px');
    expect(mobileStyles?.titleDisplay).toBe('none');
    expect(mobileStyles?.undoMinHeight).toBe('44px');
    expect(mobileStyles?.undoMinWidth).toBe('44px');
    expect(mobileStyles?.undoPaddingTop).toBe('12px');
    expect(mobileStyles?.basicsDisplay).toBe('none');

    await page.setViewportSize({ width: 700, height: 360 });
    await expect
      .poll(async () =>
        page.locator('.toolbar').evaluate((el) => getComputedStyle(el).height),
      )
      .toBe('40px');
  });

  test('Tailwind-owned action button recipe styles neutral and danger states', async ({
    page,
  }) => {
    await waitForEditorReady(page);
    await selectOutlineNode(page);

    const wrap = page.locator('.inspector-actions .action-btn').filter({
      hasText: 'Wrap in λ',
    });
    const danger = page.locator('.inspector-actions .action-btn.danger').filter({
      hasText: 'Delete',
    });

    const initialStyles = await wrap.evaluate((wrapEl) => {
      const dangerEl = document.querySelector<HTMLElement>(
        '.inspector-actions .action-btn.danger',
      );
      if (!dangerEl) return null;
      const wrapStyle = getComputedStyle(wrapEl);
      const dangerStyle = getComputedStyle(dangerEl);
      return {
        wrapBackground: wrapStyle.backgroundColor,
        wrapBorder: wrapStyle.borderTopColor,
        wrapColor: wrapStyle.color,
        wrapFontSize: wrapStyle.fontSize,
        wrapRadius: wrapStyle.borderTopLeftRadius,
        wrapTextAlign: wrapStyle.textAlign,
        dangerBackground: dangerStyle.backgroundColor,
        dangerColor: dangerStyle.color,
      };
    });

    expect(initialStyles).not.toBeNull();
    expect(initialStyles?.wrapBackground).toBe('rgb(34, 34, 56)');
    expect(initialStyles?.wrapBorder).toBe('rgba(0, 0, 0, 0)');
    expect(initialStyles?.wrapColor).toBe('rgb(184, 184, 208)');
    expect(initialStyles?.wrapFontSize).toBe('14px');
    expect(initialStyles?.wrapRadius).toBe('6px');
    expect(initialStyles?.wrapTextAlign).toBe('left');
    expect(initialStyles?.dangerBackground).toBe('rgb(34, 34, 56)');
    expect(initialStyles?.dangerColor).toBe('rgb(239, 68, 68)');

    await wrap.hover();
    await expect
      .poll(async () => wrap.evaluate((el) => getComputedStyle(el).backgroundColor))
      .toBe('rgba(130, 80, 223, 0.12)');
    await expect
      .poll(async () => wrap.evaluate((el) => getComputedStyle(el).borderTopColor))
      .toBe('rgba(130, 80, 223, 0.2)');
    await expect
      .poll(async () => wrap.evaluate((el) => getComputedStyle(el).color))
      .toBe('rgb(176, 144, 224)');

    await danger.hover();
    await expect
      .poll(async () => danger.evaluate((el) => getComputedStyle(el).backgroundColor))
      .toBe('rgba(207, 34, 46, 0.1)');
    await expect
      .poll(async () => danger.evaluate((el) => getComputedStyle(el).borderTopColor))
      .toBe('rgba(207, 34, 46, 0.2)');
    await expect
      .poll(async () => danger.evaluate((el) => getComputedStyle(el).color))
      .toBe('rgb(239, 68, 68)');
  });
});
