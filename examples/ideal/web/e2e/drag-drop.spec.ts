// Drag-and-drop E2E tests for Before/After/Inside (exchange) moves.
// Validates that AST-level operations produce valid syntax (no empty RHS,
// no orphaned separators) by checking the resulting editor text.

import { test, expect, type Page } from '@playwright/test';
import { dispatchExternalCrdtChanged } from './support/dom-events';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Enter Structure mode and wait for structure blocks to render. */
async function setupStructureMode(page: Page) {
  await page.goto('/');
  await page.getByRole('button', { name: 'Structure' }).click();
  await expect(page.getByLabel('Code editor')).toBeVisible();
  await page.waitForFunction(() => {
    const ce = document.querySelector('canopy-editor');
    return ce?.shadowRoot?.querySelector('.structure-block') !== null;
  }, { timeout: 10_000 });
}

/** Read the current editor text via the CRDT global. */
async function getEditorText(page: Page): Promise<string> {
  return await page.evaluate(() => {
    const g = globalThis as any;
    if (g.__canopy_crdt && g.__canopy_crdt_handle != null) {
      return g.__canopy_crdt.get_text(g.__canopy_crdt_handle) as string;
    }
    return '';
  });
}

/** Read the visible CodeMirror document text. */
async function getCodeMirrorText(page: Page): Promise<string> {
  return await page.evaluate(() => {
    const content = document.querySelector('#canopy-text-editor .cm-content');
    return (content as HTMLElement | null)?.innerText ?? content?.textContent ?? '';
  });
}

function normalizeText(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}

async function setEditorText(page: Page, text: string) {
  await page.evaluate((source) => {
    const g = globalThis as any;
    g.__canopy_crdt.set_text(g.__canopy_crdt_handle, source);
  }, text);
  await dispatchExternalCrdtChanged(page);
  // Re-enter Structure mode so the structure PM view is rebuilt from the new
  // CRDT text; external text updates are primarily consumed by Text mode.
  await page.getByRole('button', { name: 'Text' }).click();
  await page.waitForFunction(() => {
    return document.querySelector('#canopy-text-editor .cm-content') !== null;
  });
  await page.getByRole('button', { name: 'Structure' }).click();
  await page.waitForFunction(() => {
    const ce = document.querySelector('canopy-editor');
    const labels = Array.from(
      ce?.shadowRoot?.querySelectorAll('.structure-let_def > .structure-header .structure-label') ?? [],
    ).map((el) => el.textContent);
    return labels[0] === 'x' && labels[1] === 'y';
  });
}

/** Count structure blocks of a given type inside the shadow DOM. */
async function countNodes(page: Page, type: string): Promise<number> {
  return await page.evaluate(
    (type) => {
      const ce = document.querySelector('canopy-editor');
      if (!ce?.shadowRoot) return 0;
      return ce.shadowRoot.querySelectorAll(`.structure-${type}`).length;
    },
    type,
  );
}

/**
 * Perform a drag-drop between two structure nodes using dispatched events.
 * HTML5 drag-and-drop requires DataTransfer which page.mouse can't provide,
 * so we synthesize the full dragstart/dragover/drop/dragend sequence.
 */
async function dragDrop(
  page: Page,
  srcSelector: string,
  srcNth: number,
  tgtSelector: string,
  tgtNth: number,
  position: 'Before' | 'After' | 'Inside',
) {
  await page.evaluate(
    ({ srcSelector, srcNth, tgtSelector, tgtNth, position }) => {
      const ce = document.querySelector('canopy-editor');
      if (!ce?.shadowRoot) throw new Error('canopy-editor not found');

      const srcBlocks = ce.shadowRoot.querySelectorAll(srcSelector);
      const tgtBlocks = ce.shadowRoot.querySelectorAll(tgtSelector);
      const src = srcBlocks[srcNth] as HTMLElement;
      const tgt = tgtBlocks[tgtNth] as HTMLElement;
      if (!src || !tgt) throw new Error(`Node not found: src=${srcSelector}[${srcNth}], tgt=${tgtSelector}[${tgtNth}]`);

      // Enable draggable (normally done by grip mousedown)
      src.draggable = true;

      const tgtRect = tgt.getBoundingClientRect();
      let clientY: number;
      switch (position) {
        case 'Before': clientY = tgtRect.top + tgtRect.height * 0.1; break;
        case 'After':  clientY = tgtRect.top + tgtRect.height * 0.9; break;
        case 'Inside': clientY = tgtRect.top + tgtRect.height * 0.5; break;
      }
      const clientX = tgtRect.left + tgtRect.width / 2;

      // Get source nodeId
      const srcNodeId = (src as any).__pmNode?.attrs?.nodeId
        ?? src.getAttribute('data-node-id')
        ?? '0';

      // Create DataTransfer with source node ID
      const dt = new DataTransfer();
      dt.setData('application/x-canopy-node', String(srcNodeId));
      dt.effectAllowed = 'move';

      // Dispatch drag sequence
      src.dispatchEvent(new DragEvent('dragstart', {
        bubbles: true, composed: true, dataTransfer: dt,
      }));

      tgt.dispatchEvent(new DragEvent('dragover', {
        bubbles: true, composed: true, dataTransfer: dt,
        clientX, clientY, cancelable: true,
      }));

      tgt.dispatchEvent(new DragEvent('drop', {
        bubbles: true, composed: true, dataTransfer: dt,
        clientX, clientY, cancelable: true,
      }));

      src.dispatchEvent(new DragEvent('dragend', {
        bubbles: true, composed: true, dataTransfer: dt,
      }));
    },
    { srcSelector, srcNth, tgtSelector, tgtNth, position },
  );

  // Wait for reparse after edit
  await page.waitForTimeout(500);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test.describe('Drag-Drop — Before/After/Inside', () => {

  test.beforeEach(async ({ page }) => {
    await setupStructureMode(page);
    // Load the "Basics" example: "let double = \x. { x + x } ..."
    await page.getByRole('button', { name: 'Basics' }).click();
    await page.waitForTimeout(500);
  });

  test('structure blocks render for default example', async ({ page }) => {
    const letDefs = await countNodes(page, 'let_def');
    expect(letDefs).toBeGreaterThanOrEqual(2);
  });

  test('grip element is visible on let_def blocks', async ({ page }) => {
    const gripVisible = await page.evaluate(() => {
      const ce = document.querySelector('canopy-editor');
      if (!ce?.shadowRoot) return false;
      const grip = ce.shadowRoot.querySelector('.structure-let_def .structure-grip');
      if (!grip) return false;
      const rect = grip.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    });
    expect(gripVisible).toBe(true);
  });

  test('CRDT text is accessible', async ({ page }) => {
    const text = await getEditorText(page);
    expect(text).toContain('let');
    expect(text.length).toBeGreaterThan(10);
  });

  test('exchange (Inside) moves whole let-definitions', async ({ page }) => {
    await setEditorText(page, 'let x = 1\nlet y = 2\nx');

    await dragDrop(page, '.structure-let_def', 0, '.structure-let_def', 1, 'Inside');

    const textAfter = await getEditorText(page);
    expect(textAfter).toEqual('let y = 2\nlet x = 1\nx');
  });

  test('drop syncs CM6 before returning to Text mode', async ({ page }) => {
    await dragDrop(page, '.structure-let_def', 0, '.structure-let_def', 1, 'Inside');

    const crdtText = await getEditorText(page);
    await page.getByRole('button', { name: 'Text' }).click();
    await page.waitForFunction(() => {
      return document.querySelector('#canopy-text-editor .cm-content') !== null;
    });

    const cmText = await getCodeMirrorText(page);
    expect(normalizeText(cmText)).toEqual(normalizeText(crdtText));
  });

  test('Before drop produces valid syntax with placeholder', async ({ page }) => {
    const textBefore = await getEditorText(page);

    await dragDrop(page, '.structure-let_def', 1, '.structure-let_def', 0, 'Before');

    const textAfter = await getEditorText(page);
    expect(textAfter).not.toEqual(textBefore);
    // Critical: no "let x = " with empty RHS — placeholder should fill it
    expect(textAfter).not.toMatch(/let \w+ = \s*\n/);
    const letCount = (textAfter.match(/let /g) || []).length;
    expect(letCount).toBeGreaterThanOrEqual(2);
  });

  test('After drop produces valid syntax with placeholder', async ({ page }) => {
    const textBefore = await getEditorText(page);

    await dragDrop(page, '.structure-let_def', 0, '.structure-let_def', 1, 'After');

    const textAfter = await getEditorText(page);
    expect(textAfter).not.toEqual(textBefore);
    expect(textAfter).not.toMatch(/let \w+ = \s*\n/);
    const letCount = (textAfter.match(/let /g) || []).length;
    expect(letCount).toBeGreaterThanOrEqual(2);
  });

  test('self-drop is rejected (no change)', async ({ page }) => {
    const textBefore = await getEditorText(page);

    await dragDrop(page, '.structure-let_def', 0, '.structure-let_def', 0, 'Inside');

    const textAfter = await getEditorText(page);
    expect(textAfter).toEqual(textBefore);
  });
});
