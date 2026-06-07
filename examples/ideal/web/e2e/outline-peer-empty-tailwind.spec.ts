import { test, expect, type Page } from '@playwright/test';

async function waitForEditorReady(page: Page) {
  await page.goto('/');
  await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
  await page.waitForFunction(() => {
    return document.querySelector('#canopy-text-editor .cm-editor') !== null;
  }, { timeout: 10000 });
}

async function dispatchEditorEvent(
  page: Page,
  type: string,
  detail: Record<string, string>,
) {
  await page.evaluate(({ type, detail }) => {
    const editor = document.querySelector('#canopy-editor');
    if (!editor) throw new Error('Canopy editor host is not mounted');
    editor.dispatchEvent(new CustomEvent(type, {
      detail,
      bubbles: true,
      composed: true,
    }));
  }, { type, detail });
}

async function readPeerStyles(page: Page, dotSelector: string) {
  return page.evaluate((selector) => {
    const item = document.querySelector<HTMLElement>('.peer-item');
    const dot = document.querySelector<HTMLElement>(selector);
    if (!item || !dot) return null;

    const itemStyle = getComputedStyle(item);
    const dotStyle = getComputedStyle(dot);
    return {
      peerClassName: item.className,
      peerDisplay: itemStyle.display,
      peerAlignItems: itemStyle.alignItems,
      peerGap: itemStyle.gap,
      peerFontSize: itemStyle.fontSize,
      peerColor: itemStyle.color,
      peerPaddingTop: itemStyle.paddingTop,
      peerPaddingLeft: itemStyle.paddingLeft,
      dotClassName: dot.className,
      dotWidth: dotStyle.width,
      dotHeight: dotStyle.height,
      dotRadius: dotStyle.borderTopLeftRadius,
      dotFlexShrink: dotStyle.flexShrink,
      dotBackground: dotStyle.backgroundColor,
      dotBoxShadow: dotStyle.boxShadow,
      dotAnimationName: dotStyle.animationName,
      dotAnimationDuration: dotStyle.animationDuration,
      dotAnimationIterationCount: dotStyle.animationIterationCount,
    };
  }, dotSelector);
}

async function readInspectorEmptyStyles(page: Page) {
  return page.evaluate(() => {
    const empty = document.querySelector<HTMLElement>('.inspector-panel .empty-state');
    const text = empty?.querySelector<HTMLElement>('.empty-state-text');
    if (!empty || !text) return null;

    const emptyStyle = getComputedStyle(empty);
    const textStyle = getComputedStyle(text);
    return {
      emptyClassName: empty.className,
      emptyPaddingTop: emptyStyle.paddingTop,
      emptyPaddingLeft: emptyStyle.paddingLeft,
      textClassName: text.className,
      textFontSize: textStyle.fontSize,
      textColor: textStyle.color,
      textLineHeight: textStyle.lineHeight,
    };
  });
}

async function readNoTreeNoteStyles(page: Page) {
  return page.evaluate(() => {
    const note = document.querySelector<HTMLElement>('.inspector-panel .no-tree-note');
    if (!note) return null;

    const style = getComputedStyle(note);
    return {
      noteClassName: note.className,
      noteFontSize: style.fontSize,
      noteColor: style.color,
      notePaddingTop: style.paddingTop,
      notePaddingLeft: style.paddingLeft,
    };
  });
}

test.describe('Ideal Tailwind outline peer and empty-state class bundles', () => {
  test('Tailwind-owned peer item and status dot chrome styles connected/error states', async ({
    page,
  }) => {
    await waitForEditorReady(page);

    await dispatchEditorEvent(page, 'sync-status', { status: 'connected' });
    await expect(page.locator('.peer-dot.connected')).toBeVisible();
    const connected = await readPeerStyles(page, '.peer-dot.connected');

    expect(connected).not.toBeNull();
    expect(connected?.peerClassName).toMatch(/^peer-item\b/);
    expect(connected?.peerDisplay).toBe('flex');
    expect(connected?.peerAlignItems).toBe('center');
    expect(connected?.peerGap).toBe('8px');
    expect(connected?.peerFontSize).toBe('14px');
    expect(connected?.peerColor).toBe('rgb(184, 184, 208)');
    expect(connected?.peerPaddingTop).toBe('4px');
    expect(connected?.peerPaddingLeft).toBe('0px');
    expect(connected?.dotClassName).toMatch(/^peer-dot connected\b/);
    expect(connected?.dotWidth).toBe('7px');
    expect(connected?.dotHeight).toBe('7px');
    expect(Number.parseFloat(connected?.dotRadius ?? '0')).toBeGreaterThan(3);
    expect(connected?.dotFlexShrink).toBe('0');
    expect(connected?.dotBackground).toBe('rgb(195, 232, 141)');
    expect(connected?.dotBoxShadow).toContain('rgb(195, 232, 141)');
    expect(connected?.dotBoxShadow).toContain('6px');
    expect(connected?.dotAnimationName).toBe('pulse-connected');
    expect(connected?.dotAnimationDuration).toBe('2s');
    expect(connected?.dotAnimationIterationCount).toBe('infinite');

    await dispatchEditorEvent(page, 'sync-status', { status: 'error' });
    await expect(page.locator('.peer-dot.error')).toBeVisible();
    const error = await readPeerStyles(page, '.peer-dot.error');

    expect(error).not.toBeNull();
    expect(error?.dotClassName).toMatch(/^peer-dot error\b/);
    expect(error?.dotBackground).toBe('rgb(255, 83, 112)');
    expect(error?.dotBoxShadow).toContain('rgb(255, 83, 112)');
    expect(error?.dotBoxShadow).toContain('6px');
    expect(error?.dotAnimationName).toBe('none');
  });

  test('Tailwind-owned inspector empty and no-tree note chrome styles', async ({
    page,
  }) => {
    await waitForEditorReady(page);
    await expect(page.locator('.inspector-panel .empty-state-text')).toContainText(
      'Click a node in the outline or editor to inspect it',
    );

    const empty = await readInspectorEmptyStyles(page);

    expect(empty).not.toBeNull();
    expect(empty?.emptyClassName).toMatch(/^empty-state\b/);
    expect(empty?.emptyPaddingTop).toBe('16px');
    expect(empty?.emptyPaddingLeft).toBe('16px');
    expect(empty?.textClassName).toMatch(/^empty-state-text\b/);
    expect(empty?.textFontSize).toBe('14px');
    expect(empty?.textColor).toBe('rgb(138, 138, 170)');
    expect(Number.parseFloat(empty?.textLineHeight ?? '0')).toBeCloseTo(23.1, 1);

    await dispatchEditorEvent(page, 'node-selected', { nodeId: '__missing-node__' });
    await expect(page.locator('.inspector-panel .no-tree-note')).toHaveText(
      'No matching node',
    );

    const noTree = await readNoTreeNoteStyles(page);

    expect(noTree).not.toBeNull();
    expect(noTree?.noteClassName).toMatch(/^no-tree-note\b/);
    expect(noTree?.noteFontSize).toBe('14px');
    expect(noTree?.noteColor).toBe('rgb(136, 136, 168)');
    expect(noTree?.notePaddingTop).toBe('16px');
    expect(noTree?.notePaddingLeft).toBe('16px');
  });
});
