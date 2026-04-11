// Markdown block editor — fundamental invariant tests.
// Tests the editor's contract, not UI surface details.
// Uses built-in example presets to avoid text-sync timing issues.

import { test, expect, type Page } from '@playwright/test';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Get all visible block texts from the block-mode container. */
async function blockTexts(page: Page): Promise<string[]> {
  return page.locator('#block-container .block-text').allTextContents();
}

/** Switch to a mode tab and wait for the pane to appear. */
async function switchMode(page: Page, mode: 'Block' | 'Raw' | 'Preview') {
  await page.locator(`button.mode-tab:has-text("${mode}")`).click();
  const paneId =
    mode === 'Block' ? '#block-pane' :
    mode === 'Raw' ? '#raw-pane' :
    '#preview-pane';
  await expect(page.locator(paneId)).toBeVisible();
}

/** Load an example preset and wait for blocks to render. */
async function loadExample(page: Page, name: 'Hello' | 'Blog' | 'List' | 'Code') {
  await page.locator(`button.example-btn:has-text("${name}")`).click();
  await expect(page.locator('#block-container .block-text').first()).toBeVisible();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test.beforeEach(async ({ page }) => {
  await page.goto('/markdown.html');
  await expect(page.locator('#block-container .block-text').first()).toBeVisible();
});

test.describe('Markdown Block Editor', () => {

  test('blocks render from Markdown source', async ({ page }) => {
    // Default text loads blocks with content
    const texts = await blockTexts(page);
    expect(texts.length).toBeGreaterThanOrEqual(2);
    // Every block has non-empty text
    for (const t of texts) {
      expect(t.trim().length).toBeGreaterThan(0);
    }
  });

  test('block edit round-trips through raw', async ({ page }) => {
    // Load a simple example
    await loadExample(page, 'Hello');
    const originalTexts = await blockTexts(page);
    const originalSecond = originalTexts[1]; // a paragraph

    // Click the second block and edit it
    await page.locator('#block-container .block').nth(1).click();
    await expect(page.locator('.block-textarea')).toBeVisible();
    const textarea = page.locator('.block-textarea');
    await textarea.fill('Edited paragraph.');

    // Switch to Raw — verify the Markdown source reflects the edit
    await switchMode(page, 'Raw');
    const raw = await page.locator('#raw-editor').inputValue();
    expect(raw).toContain('Edited paragraph.');
    // Original heading should still be present
    expect(raw).toContain('# Hello World');
    // Original paragraph text should NOT be present
    expect(raw).not.toContain(originalSecond);
  });

  test('mode switching is lossless', async ({ page }) => {
    // Load the List example (has heading + paragraph + list items)
    await loadExample(page, 'List');
    const originalTexts = await blockTexts(page);

    // Cycle through all modes: Block → Raw → Preview → Block
    await switchMode(page, 'Raw');
    const raw = await page.locator('#raw-editor').inputValue();
    // Raw should contain Markdown syntax
    expect(raw).toContain('#');

    await switchMode(page, 'Preview');
    await switchMode(page, 'Block');

    // Same block texts after full cycle
    const afterCycle = await blockTexts(page);
    expect(afterCycle).toEqual(originalTexts);
  });

  test('structural edit produces valid Markdown', async ({ page }) => {
    // Load Hello example (heading + paragraphs)
    await loadExample(page, 'Hello');

    // Get raw source before edit
    await switchMode(page, 'Raw');
    const rawBefore = await page.locator('#raw-editor').inputValue();
    await switchMode(page, 'Block');

    // Click a paragraph block and edit: type new text, then press Enter to split
    await page.locator('#block-container .block').nth(1).click();
    await expect(page.locator('.block-textarea')).toBeVisible();
    const textarea = page.locator('.block-textarea');
    const originalText = await textarea.inputValue();

    // Press Enter at end → inserts new block (raw source grows)
    const countBefore = await page.locator('#block-container .block').count();
    await textarea.press('End');
    await textarea.press('Enter');
    await expect(page.locator('#block-container .block')).toHaveCount(countBefore + 1);

    // Verify the raw source changed and is valid Markdown
    await switchMode(page, 'Raw');
    const rawAfter = await page.locator('#raw-editor').inputValue();
    // Source should have grown (extra blank line for the new block)
    expect(rawAfter.length).toBeGreaterThan(rawBefore.length);
    // Original content preserved
    expect(rawAfter).toContain('# Hello World');
    expect(rawAfter).toContain(originalText);
    // No garbled output
    expect(rawAfter).not.toContain('undefined');
    expect(rawAfter).not.toContain('null');
  });

  test('clicking different blocks activates each one', async ({ page }) => {
    await loadExample(page, 'Hello');
    const texts = await blockTexts(page);
    const textarea = page.locator('.block-textarea');

    // Click each block in sequence — each should activate the textarea
    for (let i = 0; i < texts.length; i++) {
      await page.locator('#block-container .block').nth(i).click();
      await expect(textarea).toBeVisible();
      const value = await textarea.inputValue();
      expect(value).toBe(texts[i]);
    }
  });

  test('multiple Enter presses create blocks with unique IDs and typing works', async ({ page }) => {
    await loadExample(page, 'Hello');
    const initialCount = await page.locator('#block-container .block').count();
    await page.locator('#block-container .block').first().click();
    const textarea = page.locator('.block-textarea');
    await expect(textarea).toBeVisible();
    await textarea.press('End');

    // Create 3 empty blocks, waiting for each to appear
    for (let i = 1; i <= 3; i++) {
      await textarea.press('Enter');
      await expect(page.locator('#block-container .block')).toHaveCount(initialCount + i);
    }

    // All block IDs should be unique
    const ids = await page.locator('#block-container .block').evaluateAll(
      els => els.map(el => el.dataset.nodeId),
    );
    const unique = new Set(ids).size;
    expect(unique).toBe(ids.length);

    // Typing in the last new block should work and round-trip through raw
    await expect(textarea).toBeVisible();
    await textarea.fill('Typed here');
    await switchMode(page, 'Raw');
    const raw = await page.locator('#raw-editor').inputValue();
    expect(raw).toContain('Typed here');
  });

  test('Backspace on non-empty block moves focus without merging', async ({ page }) => {
    await loadExample(page, 'Hello');
    const textsBefore = await blockTexts(page);

    // Click second block, Backspace at start
    await page.locator('#block-container .block').nth(1).click();
    const textarea = page.locator('.block-textarea');
    await expect(textarea).toBeVisible();
    await textarea.press('Home');
    await textarea.press('Backspace');
    // Wait for focus to move — textarea value should become the first block's text
    await expect(textarea).toHaveValue(textsBefore[0]);

    // Blocks unchanged (no merge)
    const textsAfter = await blockTexts(page);
    expect(textsAfter).toEqual(textsBefore);
    // Cursor moved to previous block
    const value = await textarea.inputValue();
    expect(value).toBe(textsBefore[0]);
  });

  test('Backspace on empty block deletes it', async ({ page }) => {
    await loadExample(page, 'Hello');
    const textsBefore = await blockTexts(page);

    // Create empty block then delete it
    const countBefore = await page.locator('#block-container .block').count();
    await page.locator('#block-container .block').first().click();
    await expect(page.locator('.block-textarea')).toBeVisible();
    await page.locator('.block-textarea').press('End');
    await page.locator('.block-textarea').press('Enter');
    await expect(page.locator('#block-container .block')).toHaveCount(countBefore + 1);
    await page.locator('.block-textarea').press('Backspace');
    await expect(page.locator('#block-container .block')).toHaveCount(countBefore);

    // Back to original blocks
    const textsAfter = await blockTexts(page);
    expect(textsAfter).toEqual(textsBefore);
  });

  test('ArrowLeft at start moves to end of previous block', async ({ page }) => {
    await loadExample(page, 'Hello');
    const texts = await blockTexts(page);
    const textarea = page.locator('.block-textarea');

    // Click second block, press ArrowLeft at position 0
    await page.locator('#block-container .block').nth(1).click();
    await expect(textarea).toBeVisible();
    await textarea.press('Home');
    await textarea.press('ArrowLeft');
    // Wait for focus to move to previous block
    await expect(textarea).toHaveValue(texts[0]);
    const pos = await textarea.evaluate(el => (el as HTMLTextAreaElement).selectionStart);
    expect(pos).toBe(texts[0].length);
  });

  test('ArrowRight at end moves to start of next block', async ({ page }) => {
    await loadExample(page, 'Hello');
    const texts = await blockTexts(page);
    const textarea = page.locator('.block-textarea');

    // Click first block, press ArrowRight at end
    await page.locator('#block-container .block').first().click();
    await expect(textarea).toBeVisible();
    await textarea.press('End');
    await textarea.press('ArrowRight');
    // Wait for focus to move to next block
    await expect(textarea).toHaveValue(texts[1]);
    const pos = await textarea.evaluate(el => (el as HTMLTextAreaElement).selectionStart);
    expect(pos).toBe(0);
  });

  test('code block has no leading/trailing newlines', async ({ page }) => {
    await loadExample(page, 'Code');

    // Block mode: code block text should not start or end with newline
    const texts = await blockTexts(page);
    const codeText = texts.find(t => t.includes('npm'));
    expect(codeText).toBeDefined();
    expect(codeText!.startsWith('\n')).toBe(false);
    expect(codeText!.endsWith('\n')).toBe(false);

    // Preview mode: <code> content should match
    await switchMode(page, 'Preview');
    const previewCode = await page.locator('#preview-container pre code').textContent();
    expect(previewCode!.startsWith('\n')).toBe(false);
    expect(previewCode!.endsWith('\n')).toBe(false);
  });

  test('preview produces semantic HTML', async ({ page }) => {
    // Load Code example — has heading, paragraphs, code block, and list
    await loadExample(page, 'Code');
    await switchMode(page, 'Preview');
    const container = page.locator('#preview-container');

    // Heading renders as <h1> or <h2>
    const headings = await container.locator('h1, h2').count();
    expect(headings).toBeGreaterThanOrEqual(1);
    // Paragraph renders as <p>
    await expect(container.locator('p').first()).toBeVisible();
    // List renders as <ul> with <li> children
    await expect(container.locator('ul')).toBeVisible();
    await expect(container.locator('li').first()).toBeVisible();
    // Code block renders as <pre>
    await expect(container.locator('pre')).toBeVisible();
  });

});
