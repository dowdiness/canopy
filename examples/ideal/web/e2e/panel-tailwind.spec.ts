import { test, expect, type Page } from '@playwright/test';

async function waitForEditorReady(page: Page) {
  await page.goto('/');
  await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
  await page.waitForFunction(() => {
    return document.querySelector('#canopy-text-editor .cm-editor') !== null;
  }, { timeout: 10000 });
}

async function ensurePanelOpen(page: Page, name: 'Outline' | 'Inspector') {
  const toggle = page.getByRole('button', { name });
  if ((await toggle.getAttribute('aria-pressed')) !== 'true') {
    await toggle.click();
  }
  await expect(toggle).toHaveAttribute('aria-pressed', 'true');
}

test.describe('Ideal Tailwind panel recipes', () => {
  test('Tailwind-owned panel header and section chrome styles desktop', async ({
    page,
  }) => {
    await waitForEditorReady(page);

    const styles = await page.evaluate(() => {
      const outline = document.querySelector<HTMLElement>('.outline-panel');
      const inspector = document.querySelector<HTMLElement>('.inspector-panel');
      const outlineHeader = outline?.querySelector<HTMLElement>('.panel-header');
      const outlineLabel = outlineHeader?.querySelector<HTMLElement>('.panel-label');
      const outlineSection = outline?.querySelector<HTMLElement>('.panel-section');
      const inspectorHeader = inspector?.querySelector<HTMLElement>('.panel-header');
      const inspectorLabel = inspectorHeader?.querySelector<HTMLElement>('.inspector-label');
      const inspectorSection = inspector?.querySelector<HTMLElement>('.inspector-section');
      if (
        !outlineHeader ||
        !outlineLabel ||
        !outlineSection ||
        !inspectorHeader ||
        !inspectorLabel ||
        !inspectorSection
      ) return null;

      const outlineHeaderStyle = getComputedStyle(outlineHeader);
      const outlineLabelStyle = getComputedStyle(outlineLabel);
      const outlineSectionStyle = getComputedStyle(outlineSection);
      const inspectorHeaderStyle = getComputedStyle(inspectorHeader);
      const inspectorLabelStyle = getComputedStyle(inspectorLabel);
      const inspectorSectionStyle = getComputedStyle(inspectorSection);
      return {
        outlineHeaderPaddingTop: outlineHeaderStyle.paddingTop,
        outlineHeaderPaddingRight: outlineHeaderStyle.paddingRight,
        outlineHeaderPaddingBottom: outlineHeaderStyle.paddingBottom,
        outlineLabelFontSize: outlineLabelStyle.fontSize,
        outlineLabelFontWeight: outlineLabelStyle.fontWeight,
        outlineLabelColor: outlineLabelStyle.color,
        outlineLabelLetterSpacing: outlineLabelStyle.letterSpacing,
        outlineLabelTextTransform: outlineLabelStyle.textTransform,
        outlineSectionPaddingTop: outlineSectionStyle.paddingTop,
        outlineSectionPaddingLeft: outlineSectionStyle.paddingLeft,
        outlineSectionBorderWidth: outlineSectionStyle.borderTopWidth,
        outlineSectionBorderColor: outlineSectionStyle.borderTopColor,
        inspectorHeaderPaddingTop: inspectorHeaderStyle.paddingTop,
        inspectorLabelHasPanelHook: inspectorLabel.classList.contains('panel-label'),
        inspectorLabelColor: inspectorLabelStyle.color,
        inspectorSectionHasPanelHook: inspectorSection.classList.contains('panel-section'),
        inspectorSectionPaddingTop: inspectorSectionStyle.paddingTop,
        inspectorSectionBorderWidth: inspectorSectionStyle.borderTopWidth,
      };
    });

    expect(styles).not.toBeNull();
    expect(styles?.outlineHeaderPaddingTop).toBe('16px');
    expect(styles?.outlineHeaderPaddingRight).toBe('16px');
    expect(styles?.outlineHeaderPaddingBottom).toBe('12px');
    expect(styles?.outlineLabelFontSize).toBe('11px');
    expect(styles?.outlineLabelFontWeight).toBe('600');
    expect(styles?.outlineLabelColor).toBe('rgb(138, 138, 170)');
    expect(Number.parseFloat(styles?.outlineLabelLetterSpacing ?? '0')).toBeCloseTo(1.1, 1);
    expect(styles?.outlineLabelTextTransform).toBe('uppercase');
    expect(styles?.outlineSectionPaddingTop).toBe('12px');
    expect(styles?.outlineSectionPaddingLeft).toBe('16px');
    expect(styles?.outlineSectionBorderWidth).toBe('1px');
    expect(styles?.outlineSectionBorderColor).toBe('rgb(40, 40, 62)');
    expect(styles?.inspectorHeaderPaddingTop).toBe('16px');
    expect(styles?.inspectorLabelHasPanelHook).toBe(true);
    expect(styles?.inspectorLabelColor).toBe('rgb(138, 138, 170)');
    expect(styles?.inspectorSectionHasPanelHook).toBe(true);
    expect(styles?.inspectorSectionPaddingTop).toBe('12px');
    expect(styles?.inspectorSectionBorderWidth).toBe('1px');
  });

  test('Tailwind-owned panel chrome is present in mobile drawer state', async ({
    page,
  }) => {
    await waitForEditorReady(page);
    await ensurePanelOpen(page, 'Outline');
    await ensurePanelOpen(page, 'Inspector');
    await page.setViewportSize({ width: 390, height: 844 });

    const styles = await page.evaluate(() => {
      const outline = document.querySelector<HTMLElement>('.outline-panel');
      const inspector = document.querySelector<HTMLElement>('.inspector-panel');
      const outlineHeader = outline?.querySelector<HTMLElement>('.panel-header');
      const outlineSection = outline?.querySelector<HTMLElement>('.panel-section');
      const inspectorLabel = inspector?.querySelector<HTMLElement>('.inspector-label');
      const inspectorSection = inspector?.querySelector<HTMLElement>('.inspector-section');
      if (!outline || !inspector || !outlineHeader || !outlineSection || !inspectorLabel || !inspectorSection) {
        return null;
      }
      const outlineStyle = getComputedStyle(outline);
      const inspectorStyle = getComputedStyle(inspector);
      const outlineHeaderStyle = getComputedStyle(outlineHeader);
      const outlineSectionStyle = getComputedStyle(outlineSection);
      const inspectorLabelStyle = getComputedStyle(inspectorLabel);
      const inspectorSectionStyle = getComputedStyle(inspectorSection);
      return {
        outlineClassName: outline.className,
        inspectorClassName: inspector.className,
        outlinePosition: outlineStyle.position,
        inspectorPosition: inspectorStyle.position,
        outlineWidth: outlineStyle.width,
        inspectorWidth: inspectorStyle.width,
        outlineHeaderPaddingTop: outlineHeaderStyle.paddingTop,
        outlineSectionPaddingLeft: outlineSectionStyle.paddingLeft,
        outlineSectionBorderColor: outlineSectionStyle.borderTopColor,
        inspectorLabelFontSize: inspectorLabelStyle.fontSize,
        inspectorLabelTextTransform: inspectorLabelStyle.textTransform,
        inspectorSectionPaddingTop: inspectorSectionStyle.paddingTop,
      };
    });

    expect(styles).not.toBeNull();
    expect(styles?.outlineClassName).toContain('panel-visible');
    expect(styles?.inspectorClassName).toContain('panel-visible');
    expect(styles?.outlinePosition).toBe('fixed');
    expect(styles?.inspectorPosition).toBe('fixed');
    expect(styles?.outlineWidth).toBe('390px');
    expect(styles?.inspectorWidth).toBe('390px');
    expect(styles?.outlineHeaderPaddingTop).toBe('16px');
    expect(styles?.outlineSectionPaddingLeft).toBe('16px');
    expect(styles?.outlineSectionBorderColor).toBe('rgb(40, 40, 62)');
    expect(styles?.inspectorLabelFontSize).toBe('11px');
    expect(styles?.inspectorLabelTextTransform).toBe('uppercase');
    expect(styles?.inspectorSectionPaddingTop).toBe('12px');
  });
});
