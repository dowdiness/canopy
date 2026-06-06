import { test, expect, type Page } from '@playwright/test';

async function waitForEditorReady(page: Page) {
  await page.goto('/');
  await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
  await page.waitForFunction(() => {
    return document.querySelector('#canopy-text-editor .cm-editor') !== null;
  }, { timeout: 10000 });
}

async function selectNodeWithInspectorDetails(page: Page) {
  await page.getByRole('button', { name: 'Basics' }).click();

  const firstRow = page.locator('.outline-panel .tree-row').first();
  await expect(firstRow).toBeVisible();
  await firstRow.click();
  await expect(page.locator('.inspector-panel .source-preview')).toBeVisible();
  await expect(
    page.locator('.inspector-panel .token-span-row').first(),
  ).toBeVisible();
}

async function readInspectorDetailStyles(page: Page) {
  return page.evaluate(() => {
    const inspector = document.querySelector<HTMLElement>('.inspector-panel');
    const row = inspector?.querySelector<HTMLElement>('.inspector-row');
    const key = row?.querySelector<HTMLElement>('.inspector-key');
    const value = row?.querySelector<HTMLElement>('.inspector-value');
    const preview = inspector?.querySelector<HTMLElement>('.source-preview');
    const tokenRow = inspector?.querySelector<HTMLElement>('.token-span-row');
    const tokenRole = tokenRow?.querySelector<HTMLElement>('.token-span-role');
    const tokenRange = tokenRow?.querySelector<HTMLElement>('.token-span-range');
    const tokenText = tokenRow?.querySelector<HTMLElement>('.token-span-text');
    if (
      !row ||
      !key ||
      !value ||
      !preview ||
      !tokenRow ||
      !tokenRole ||
      !tokenRange ||
      !tokenText
    ) return null;

    const rowStyle = getComputedStyle(row);
    const keyStyle = getComputedStyle(key);
    const valueStyle = getComputedStyle(value);
    const previewStyle = getComputedStyle(preview);
    const tokenRowStyle = getComputedStyle(tokenRow);
    const tokenRoleStyle = getComputedStyle(tokenRole);
    const tokenRangeStyle = getComputedStyle(tokenRange);
    const tokenTextStyle = getComputedStyle(tokenText);
    return {
      rowClassName: row.className,
      rowDisplay: rowStyle.display,
      rowGap: rowStyle.gap,
      rowPaddingTop: rowStyle.paddingTop,
      keyFontSize: keyStyle.fontSize,
      keyFontWeight: keyStyle.fontWeight,
      keyColor: keyStyle.color,
      keyWidth: keyStyle.width,
      keyFlexShrink: keyStyle.flexShrink,
      keyWhiteSpace: keyStyle.whiteSpace,
      valueFontSize: valueStyle.fontSize,
      valueColor: valueStyle.color,
      valueFontFamily: valueStyle.fontFamily,
      valueFontVariantNumeric: valueStyle.fontVariantNumeric,
      valueLetterSpacing: valueStyle.letterSpacing,
      previewBackground: previewStyle.backgroundColor,
      previewRadius: previewStyle.borderTopLeftRadius,
      previewPaddingTop: previewStyle.paddingTop,
      previewPaddingLeft: previewStyle.paddingLeft,
      previewMarginTop: previewStyle.marginTop,
      previewFontSize: previewStyle.fontSize,
      previewWhiteSpace: previewStyle.whiteSpace,
      previewOverflowX: previewStyle.overflowX,
      previewOverflowY: previewStyle.overflowY,
      tokenRowClassName: tokenRow.className,
      tokenRowDisplay: tokenRowStyle.display,
      tokenRowGap: tokenRowStyle.gap,
      tokenRowPaddingTop: tokenRowStyle.paddingTop,
      tokenRowFontSize: tokenRowStyle.fontSize,
      tokenRowFontFamily: tokenRowStyle.fontFamily,
      tokenRoleColor: tokenRoleStyle.color,
      tokenRoleMinWidth: tokenRoleStyle.minWidth,
      tokenRoleFlexShrink: tokenRoleStyle.flexShrink,
      tokenRangeColor: tokenRangeStyle.color,
      tokenRangeMinWidth: tokenRangeStyle.minWidth,
      tokenRangeFontVariantNumeric: tokenRangeStyle.fontVariantNumeric,
      tokenTextColor: tokenTextStyle.color,
    };
  });
}

test.describe('Ideal Tailwind inspector detail class bundles', () => {
  test('Tailwind-owned inspector row/source/token chrome styles desktop', async ({
    page,
  }) => {
    await waitForEditorReady(page);
    await selectNodeWithInspectorDetails(page);

    const styles = await readInspectorDetailStyles(page);

    expect(styles).not.toBeNull();
    expect(styles?.rowClassName).toMatch(/^inspector-row\b/);
    expect(styles?.rowDisplay).toBe('flex');
    expect(styles?.rowGap).toBe('8px');
    expect(styles?.rowPaddingTop).toBe('4px');
    expect(styles?.keyFontSize).toBe('14px');
    expect(styles?.keyFontWeight).toBe('400');
    expect(styles?.keyColor).toBe('rgb(136, 136, 168)');
    expect(styles?.keyWidth).toBe('76px');
    expect(styles?.keyFlexShrink).toBe('0');
    expect(styles?.keyWhiteSpace).toBe('nowrap');
    expect(styles?.valueFontSize).toBe('14px');
    expect(styles?.valueColor).toBe('rgb(228, 228, 240)');
    expect(styles?.valueFontFamily).toContain('Iosevka');
    expect(styles?.valueFontVariantNumeric).toBe('tabular-nums');
    expect(Number.parseFloat(styles?.valueLetterSpacing ?? '0')).toBeCloseTo(
      -0.14,
      2,
    );
    expect(styles?.previewBackground).toBe('rgb(34, 34, 56)');
    expect(styles?.previewRadius).toBe('4px');
    expect(styles?.previewPaddingTop).toBe('8px');
    expect(styles?.previewPaddingLeft).toBe('12px');
    expect(styles?.previewMarginTop).toBe('8px');
    expect(styles?.previewFontSize).toBe('13px');
    expect(styles?.previewWhiteSpace).toBe('pre');
    expect(styles?.previewOverflowX).toBe('auto');
    expect(styles?.previewOverflowY).toBe('auto');
    expect(styles?.tokenRowClassName).toMatch(/^token-span-row\b/);
    expect(styles?.tokenRowDisplay).toBe('flex');
    expect(styles?.tokenRowGap).toBe('8px');
    expect(styles?.tokenRowPaddingTop).toBe('2px');
    expect(styles?.tokenRowFontSize).toBe('13px');
    expect(styles?.tokenRowFontFamily).toContain('Iosevka');
    expect(styles?.tokenRoleColor).toBe('rgb(136, 136, 168)');
    expect(styles?.tokenRoleMinWidth).toBe('52px');
    expect(styles?.tokenRoleFlexShrink).toBe('0');
    expect(styles?.tokenRangeColor).toBe('rgb(138, 138, 170)');
    expect(styles?.tokenRangeMinWidth).toBe('44px');
    expect(styles?.tokenRangeFontVariantNumeric).toBe('tabular-nums');
    expect(styles?.tokenTextColor).toBe('rgb(130, 170, 255)');
  });
});
