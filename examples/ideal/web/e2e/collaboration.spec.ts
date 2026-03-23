import { test, expect, type Page } from '@playwright/test';

/**
 * Collaboration E2E tests using two browser contexts.
 *
 * The relay server is auto-started by Playwright config (webServer).
 */

/** Wait for the editor to fully load in a page. */
async function waitForEditor(page: Page) {
  await page.goto('/');
  await expect(page).toHaveTitle('Canopy Editor');
  await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
  await page.waitForFunction(() => {
    const ce = document.querySelector('canopy-editor');
    return ce?.shadowRoot?.querySelector('.cm-editor') !== null;
  }, { timeout: 15000 });
}

/** Focus the CM6 editor and type text. */
async function typeInEditor(page: Page, text: string) {
  await page.evaluate(() => {
    const ce = document.querySelector('canopy-editor');
    const cm = ce?.shadowRoot?.querySelector('.cm-content') as HTMLElement;
    cm?.focus();
  });
  await page.keyboard.type(text, { delay: 30 });
}

/** Get the text content from the CM6 editor. */
async function getEditorText(page: Page): Promise<string> {
  return page.evaluate(() => {
    const ce = document.querySelector('canopy-editor');
    const cm = ce?.shadowRoot?.querySelector('.cm-content');
    return cm?.textContent ?? '';
  });
}

/** Get the sync status text from the PEERS section. */
async function getSyncStatus(page: Page): Promise<string> {
  return page.locator('.peer-item').innerText();
}

/** Check if peer cursor decorations are present in the CM6 editor. */
async function hasPeerCursors(page: Page): Promise<boolean> {
  return page.evaluate(() => {
    const ce = document.querySelector('canopy-editor');
    if (!ce?.shadowRoot) return false;
    const cursors = ce.shadowRoot.querySelectorAll('.peer-cursor-widget');
    return cursors.length > 0;
  });
}

/** Get the count of peer cursor widgets. */
async function getPeerCursorCount(page: Page): Promise<number> {
  return page.evaluate(() => {
    const ce = document.querySelector('canopy-editor');
    if (!ce?.shadowRoot) return 0;
    return ce.shadowRoot.querySelectorAll('.peer-cursor-widget').length;
  });
}

// ── Without relay: basic sync status tests ───────────────────

test.describe('Collaboration - Offline', () => {
  test('no peer cursors without collaboration', async ({ page }) => {
    await waitForEditor(page);
    expect(await hasPeerCursors(page)).toBe(false);
  });
});

// ── With relay: two-peer collaboration tests ─────────────────

test.describe('Collaboration - Two Peers', () => {
  test('two peers connect and see each other', async ({ browser }) => {
    const contextA = await browser.newContext();
    const contextB = await browser.newContext();
    const pageA = await contextA.newPage();
    const pageB = await contextB.newPage();

    try {
      await Promise.all([waitForEditor(pageA), waitForEditor(pageB)]);

      // Wait for both to connect to the relay
      await Promise.all([
        pageA.waitForFunction(
          () => document.querySelector('.peer-dot.connected') !== null,
          { timeout: 10000 },
        ).catch(() => {}),
        pageB.waitForFunction(
          () => document.querySelector('.peer-dot.connected') !== null,
          { timeout: 10000 },
        ).catch(() => {}),
      ]);

      const statusA = await getSyncStatus(pageA);
      const statusB = await getSyncStatus(pageB);
      expect(statusA).toContain('connected');
      expect(statusB).toContain('connected');
    } finally {
      await contextA.close();
      await contextB.close();
    }
  });

  test('text typed by peer A appears in peer B', async ({ browser }) => {
    const contextA = await browser.newContext();
    const contextB = await browser.newContext();
    const pageA = await contextA.newPage();
    const pageB = await contextB.newPage();

    try {
      await Promise.all([waitForEditor(pageA), waitForEditor(pageB)]);

      // Wait for connection
      await expect.poll(async () => {
        const s = await getSyncStatus(pageA);
        return s.includes('connected');
      }, { timeout: 10000 }).toBeTruthy();

      // Peer A loads an example
      await pageA.getByRole('button', { name: 'Identity' }).click();
      await expect.poll(async () => {
        return (await getEditorText(pageA)).length > 0;
      }, { timeout: 5000 }).toBeTruthy();

      // Peer A types additional text
      await typeInEditor(pageA, '\nlet y = 2');

      // Peer B should eventually see the synced text
      await expect.poll(async () => {
        const textB = await getEditorText(pageB);
        return textB.includes('let') && textB.includes('y');
      }, { timeout: 10000 }).toBeTruthy();
    } finally {
      await contextA.close();
      await contextB.close();
    }
  });

  test('peer cursors appear in remote editor', async ({ browser }) => {
    const contextA = await browser.newContext();
    const contextB = await browser.newContext();
    const pageA = await contextA.newPage();
    const pageB = await contextB.newPage();

    try {
      await Promise.all([waitForEditor(pageA), waitForEditor(pageB)]);

      // Wait for connection
      await expect.poll(async () => {
        const s = await getSyncStatus(pageA);
        return s.includes('connected');
      }, { timeout: 10000 }).toBeTruthy();

      // Peer A clicks in the editor to set cursor position
      await pageA.evaluate(() => {
        const ce = document.querySelector('canopy-editor');
        const cm = ce?.shadowRoot?.querySelector('.cm-content') as HTMLElement;
        cm?.focus();
      });
      await pageA.keyboard.press('End');

      // Peer B should see peer A's cursor
      await expect.poll(async () => {
        return await getPeerCursorCount(pageB);
      }, { timeout: 10000 }).toBeGreaterThan(0);
    } finally {
      await contextA.close();
      await contextB.close();
    }
  });

  test('outline updates on both peers after text change', async ({ browser }) => {
    const contextA = await browser.newContext();
    const contextB = await browser.newContext();
    const pageA = await contextA.newPage();
    const pageB = await contextB.newPage();

    try {
      await Promise.all([waitForEditor(pageA), waitForEditor(pageB)]);

      // Wait for connection
      await expect.poll(async () => {
        const s = await getSyncStatus(pageA);
        return s.includes('connected');
      }, { timeout: 10000 }).toBeTruthy();

      // Peer A loads Add example
      await pageA.getByRole('button', { name: 'Add' }).click();

      // Peer A's outline should show module [add]
      await expect.poll(async () => {
        const text = await pageA.getByLabel('AST outline').innerText();
        return text.includes('module [add]');
      }, { timeout: 5000 }).toBeTruthy();

      // Peer B should eventually sync and show the same
      await expect.poll(async () => {
        const text = await pageB.getByLabel('AST outline').innerText();
        return text.includes('add');
      }, { timeout: 10000 }).toBeTruthy();
    } finally {
      await contextA.close();
      await contextB.close();
    }
  });
});
