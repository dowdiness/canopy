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
    await textarea.press('End');
    await textarea.press('Enter');
    await page.waitForTimeout(300);

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
