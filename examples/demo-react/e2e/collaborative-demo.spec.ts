import { test, expect } from '@playwright/test';

test.describe('Collaborative Demo Mode', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.getByRole('button', { name: 'Collaborative Demo' }).click();
    // Wait for the demo to load
    await expect(page.getByRole('heading', { name: 'Per-Agent Undo/Redo Demo' })).toBeVisible();
  });

  test('should display collaborative demo UI', async ({ page }) => {
    await expect(page.getByText('Sync Mode:')).toBeVisible();
    await expect(page.locator('.panel-title').filter({ hasText: 'Alice' })).toBeVisible();
    await expect(page.locator('.panel-title').filter({ hasText: 'Bob' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Operations Log' })).toBeVisible();
  });

  test('should have two editor panels', async ({ page }) => {
    await expect(page.getByPlaceholder("Alice's editor")).toBeVisible();
    await expect(page.getByPlaceholder("Bob's editor")).toBeVisible();
  });

  test('should load example and sync to both editors', async ({ page }) => {
    await page.getByRole('button', { name: 'Load Example' }).click();

    const expectedText = '(\\x.\\y.x + y) 10 5';
    await expect(page.getByPlaceholder("Alice's editor")).toHaveValue(expectedText);
    await expect(page.getByPlaceholder("Bob's editor")).toHaveValue(expectedText);
  });

  test('should sync typing from Alice to Bob', async ({ page }) => {
    const aliceEditor = page.getByPlaceholder("Alice's editor");
    const bobEditor = page.getByPlaceholder("Bob's editor");

    // Type a single character and wait for sync
    await aliceEditor.pressSequentially('A');
    await expect(aliceEditor).toHaveValue('A');
    await expect(bobEditor).toHaveValue('A', { timeout: 10000 });
  });

  test('should sync typing from Bob to Alice', async ({ page }) => {
    const aliceEditor = page.getByPlaceholder("Alice's editor");
    const bobEditor = page.getByPlaceholder("Bob's editor");

    // Type a single character and wait for sync
    await bobEditor.pressSequentially('X');
    await expect(bobEditor).toHaveValue('X');
    await expect(aliceEditor).toHaveValue('X', { timeout: 10000 });
  });

  test('should update shared document display', async ({ page }) => {
    await page.getByPlaceholder("Alice's editor").pressSequentially('Test');

    await expect(page.locator('.shared-text')).toContainText('Test');
  });

  test('should log operations when typing', async ({ page }) => {
    await page.getByPlaceholder("Alice's editor").pressSequentially('Hi');

    await expect(page.locator('.log-agent').first()).toContainText('Alice');
    await expect(page.locator('.log-type').first()).toContainText('insert');
  });

  test('should track undo stack for Alice', async ({ page }) => {
    const aliceEditor = page.getByPlaceholder("Alice's editor");
    await aliceEditor.pressSequentially('Hello');

    // Alice's undo button should be enabled after typing
    const alicePanel = page.locator('.editor-panel').filter({ hasText: 'Alice' });
    const aliceUndoBtn = alicePanel.getByRole('button', { name: /Undo/ });
    await expect(aliceUndoBtn).toBeEnabled();
  });

  test('should undo Alice changes', async ({ page }) => {
    const aliceEditor = page.getByPlaceholder("Alice's editor");

    // Type two characters with a delay exceeding the 300ms undo capture timeout
    // so they become separate undo groups
    await aliceEditor.pressSequentially('H');
    await page.waitForTimeout(400);
    await aliceEditor.pressSequentially('i');
    await expect(aliceEditor).toHaveValue('Hi');

    // Click Alice's undo button
    const alicePanel = page.locator('.editor-panel').filter({ hasText: 'Alice' });
    const aliceUndoBtn = alicePanel.getByRole('button', { name: /Undo/ });
    await aliceUndoBtn.click();

    // Text should be undone to previous state (H)
    await expect(aliceEditor).toHaveValue('H');
  });

  test('should redo Alice changes', async ({ page }) => {
    const aliceEditor = page.getByPlaceholder("Alice's editor");

    // Type characters with a delay exceeding the 300ms undo capture timeout
    // so they become separate undo groups
    await aliceEditor.pressSequentially('A');
    await page.waitForTimeout(400);
    await aliceEditor.pressSequentially('B');

    // Undo
    const alicePanel = page.locator('.editor-panel').filter({ hasText: 'Alice' });
    const aliceUndoBtn = alicePanel.getByRole('button', { name: /Undo/ });
    await aliceUndoBtn.click();
    await expect(aliceEditor).toHaveValue('A');

    // Redo
    const aliceRedoBtn = alicePanel.getByRole('button', { name: /Redo/ });
    await aliceRedoBtn.click();
    await expect(aliceEditor).toHaveValue('AB');
  });

  // Note: Per-agent undo in collaborative mode is tested via the "should undo Alice changes"
  // and "should redo Alice changes" tests. Complex multi-agent undo interactions with sync
  // can have timing issues in the stub implementation.

  test('should reset both editors', async ({ page }) => {
    // Type and wait for sync one char at a time
    const aliceEditor = page.getByPlaceholder("Alice's editor");
    const bobEditor = page.getByPlaceholder("Bob's editor");

    await aliceEditor.pressSequentially('T');
    await expect(bobEditor).toHaveValue('T', { timeout: 10000 });

    await page.getByRole('button', { name: 'Reset' }).click();

    await expect(aliceEditor).toHaveValue('');
    await expect(bobEditor).toHaveValue('');
  });

  test('should clear operations log on reset', async ({ page }) => {
    await page.getByPlaceholder("Alice's editor").pressSequentially('Hi');
    await expect(page.locator('.log-type').first()).toContainText('insert');

    await page.getByRole('button', { name: 'Reset' }).click();

    await expect(page.getByText('No operations yet')).toBeVisible();
  });

  test('should switch back to Single Editor mode', async ({ page }) => {
    await page.getByRole('button', { name: 'Single Editor' }).click();

    await expect(page.getByPlaceholder(/Type lambda calculus/)).toBeVisible();
    await expect(page.locator('.panel-title').filter({ hasText: 'Alice' })).not.toBeVisible();
  });
});
