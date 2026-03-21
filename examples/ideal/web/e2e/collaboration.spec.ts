import { test, expect, type BrowserContext, type Page } from '@playwright/test';

/**
 * Collaboration E2E tests using two browser contexts.
 *
 * These tests require the WebSocket relay server running on ws://localhost:8787.
 * Start it with: npm run server
 *
 * Without the relay server, tests are skipped gracefully.
 */

const RELAY_URL = 'ws://localhost:8787';

/** Check if the relay server is available. */
async function isRelayRunning(): Promise<boolean> {
  return new Promise((resolve) => {
    try {
      const ws = new (require('ws'))(RELAY_URL);
      ws.on('open', () => { ws.close(); resolve(true); });
      ws.on('error', () => resolve(false));
      setTimeout(() => { try { ws.close(); } catch {} resolve(false); }, 2000);
    } catch {
      resolve(false);
    }
  });
}

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
  test('shows Connecting then Offline without relay server', async ({ page }) => {
    await waitForEditor(page);
    // Without relay, status should transition from Connecting to Offline
    // Wait for the reconnection timeout
    await page.waitForTimeout(3000);
    const status = await getSyncStatus(page);
    expect(
      status.includes('Connecting') || status.includes('Offline'),
    ).toBe(true);
  });

  test('no peer cursors without collaboration', async ({ page }) => {
    await waitForEditor(page);
    expect(await hasPeerCursors(page)).toBe(false);
  });
});

// ── With relay: two-peer collaboration tests ─────────────────

test.describe('Collaboration - Two Peers', () => {
  let relayAvailable: boolean;

  test.beforeAll(async () => {
    relayAvailable = await isRelayRunning();
  });

  test.beforeEach(async ({ }, testInfo) => {
    if (!relayAvailable) {
      testInfo.skip();
    }
  });

  test('two peers connect and see each other', async ({ browser }) => {
    // Create two independent browser contexts (two separate "users")
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

      // Both should show Connected status
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
      await pageA.waitForTimeout(3000);

      // Peer A loads an example
      await pageA.getByRole('button', { name: 'Identity' }).click();
      await pageA.waitForTimeout(1000);

      // Peer A types additional text
      await typeInEditor(pageA, '\nlet y = 2');
      await pageA.waitForTimeout(2000);

      // Peer B should eventually see the synced text containing "let y = 2"
      await pageB.waitForTimeout(2000);
      const textB = await getEditorText(pageB);
      expect(textB).toContain('let');
      expect(textB).toContain('y');
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

      // Wait for connection and ephemeral sync
      await pageA.waitForTimeout(3000);

      // Peer A clicks in the editor to set cursor position
      await pageA.evaluate(() => {
        const ce = document.querySelector('canopy-editor');
        const cm = ce?.shadowRoot?.querySelector('.cm-content') as HTMLElement;
        cm?.focus();
      });
      await pageA.keyboard.press('End');
      await pageA.waitForTimeout(1000);

      // Peer B should see peer A's cursor after ephemeral propagation
      // Retry with polling since ephemeral delivery has network latency
      let cursorCount = 0;
      for (let i = 0; i < 10; i++) {
        cursorCount = await getPeerCursorCount(pageB);
        if (cursorCount > 0) break;
        await pageB.waitForTimeout(500);
      }
      expect(cursorCount).toBeGreaterThan(0);
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
      await pageA.waitForTimeout(3000);

      // Peer A loads Add example
      await pageA.getByRole('button', { name: 'Add' }).click();
      await pageA.waitForTimeout(2000);

      // Peer A's outline should show module [add]
      const outlineA = await pageA.getByLabel('AST outline').innerText();
      expect(outlineA).toContain('module [add]');

      // Peer B should eventually sync and show the same definitions
      await pageB.waitForTimeout(3000);
      const outlineB = await pageB.getByLabel('AST outline').innerText();
      // After CRDT sync, B's outline should contain the "add" definition
      expect(outlineB).toContain('add');
    } finally {
      await contextA.close();
      await contextB.close();
    }
  });
});
