import { test, expect, type Page } from '@playwright/test';
import {
  getCodeMirrorText,
  getEditorText,
  setEditorText,
} from './support/editor-state';

async function waitForEditor(page: Page) {
  await page.goto('/', { waitUntil: 'domcontentloaded' });
  await expect(page).toHaveTitle('Canopy Editor');
  await expect(page.getByLabel('AST outline')).toBeVisible();
  await page.waitForFunction(() => {
    return document.querySelector('#canopy-text-editor .cm-editor') !== null;
  }, { timeout: 10000 });
}

function outline(page: Page) {
  return page.getByLabel('AST outline');
}

async function dragOutlineLetDefInside(
  page: Page,
  sourceIndex: number,
  targetIndex: number,
) {
  await page.evaluate(async ({ sourceIndex, targetIndex }) => {
    const rows = Array.from(
      document.querySelectorAll('.outline-panel .tree-row.kind-let-def'),
    ) as HTMLElement[];
    const source = rows[sourceIndex];
    const target = rows[targetIndex];
    if (!source || !target) {
      throw new Error(
        `Outline let rows not found: source=${sourceIndex}, target=${targetIndex}`,
      );
    }

    const transfer = new DataTransfer();
    const dragEvent = (type: string, element: HTMLElement) => {
      const rect = element.getBoundingClientRect();
      return new DragEvent(type, {
        bubbles: true,
        cancelable: true,
        composed: true,
        dataTransfer: transfer,
        clientX: rect.left + rect.width / 2,
        clientY: rect.top + rect.height / 2,
      });
    };
    const nextFrame = () =>
      new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));

    source.dispatchEvent(dragEvent('dragstart', source));
    await nextFrame();
    target.dispatchEvent(dragEvent('dragover', target));
    await nextFrame();
    target.dispatchEvent(dragEvent('drop', target));
    source.dispatchEvent(dragEvent('dragend', source));
  }, { sourceIndex, targetIndex });
}

test.describe('Outline tree drag and drop', () => {
  test.beforeEach(async ({ page }) => {
    await waitForEditor(page);
  });

  test('light-DOM row drag/drop reorders let definitions and syncs editor text', async ({ page }) => {
    await setEditorText(page, 'let x = 1\nlet y = 2\nx');

    const letRows = outline(page).locator('.tree-row.kind-let-def');
    await expect(
      outline(page).locator('.tree-row').first().locator('.tree-label-text'),
    ).toHaveText('module [x, y]');
    await expect(letRows).toHaveCount(2);
    await expect(letRows.nth(0).locator('.tree-label-text')).toHaveText('let x');
    await expect(letRows.nth(1).locator('.tree-label-text')).toHaveText('let y');

    await dragOutlineLetDefInside(page, 0, 1);

    await expect.poll(() => getEditorText(page)).toBe('let y = 2\nlet x = 1\nx');
    await expect
      .poll(() => getCodeMirrorText(page))
      .toBe('let y = 2\nlet x = 1\nx');
    await expect(letRows.nth(0).locator('.tree-label-text')).toHaveText('let y');
    await expect(letRows.nth(1).locator('.tree-label-text')).toHaveText('let x');
    await expect(
      outline(page).locator('.tree-row.outline-dragging'),
    ).toHaveCount(0);
    await expect(
      outline(page).locator('.tree-row.outline-drop-inside'),
    ).toHaveCount(0);
  });
});
