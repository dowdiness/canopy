import { test, expect, type Page } from '@playwright/test';

/**
 * Collaboration E2E tests using two browser contexts.
 *
 * The relay server is auto-started by Playwright config (webServer).
 */

/** Wait for the editor to fully load in a page. */
async function waitForEditor(page: Page, room?: string) {
  await page.goto(room ? `/#${room}` : '/');
  await expect(page).toHaveTitle('Canopy Editor');
  await expect(page.getByRole('button', { name: 'Text' })).toBeVisible();
  await page.waitForFunction(() => {
    return document.querySelector('#canopy-text-editor .cm-editor') !== null;
  }, { timeout: 15000 });
}

function testRoom(label: string): string {
  const slug = label.replace(/[^a-z0-9]+/gi, '-').toLowerCase();
  return `e2e-${slug}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

/** Focus the CM6 editor and type text. */
async function typeInEditor(page: Page, text: string) {
  await page.evaluate(() => {
    const cm = document.querySelector('#canopy-text-editor .cm-content') as HTMLElement;
    cm?.focus();
  });
  await page.keyboard.type(text, { delay: 30 });
}

/** Get the text content from the CM6 editor. */
async function getEditorText(page: Page): Promise<string> {
  return page.evaluate(() => {
    const cm = document.querySelector('#canopy-text-editor .cm-content');
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
    const cursors = document.querySelectorAll('#canopy-text-editor .peer-cursor-widget');
    return cursors.length > 0;
  });
}

/** Get the count of peer cursor widgets. */
async function getPeerCursorCount(page: Page): Promise<number> {
  return page.evaluate(() => {
    return document.querySelectorAll('#canopy-text-editor .peer-cursor-widget').length;
  });
}

// ── Without relay: basic sync status tests ───────────────────

test.describe('Collaboration - Offline', () => {
  test('no peer cursors without collaboration', async ({ page }) => {
    await waitForEditor(page, testRoom('offline'));
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
    const room = testRoom('connect');

    try {
      await Promise.all([waitForEditor(pageA, room), waitForEditor(pageB, room)]);

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
    const room = testRoom('text-sync');

    try {
      await Promise.all([waitForEditor(pageA, room), waitForEditor(pageB, room)]);

      // Wait for connection
      await expect.poll(async () => {
        const s = await getSyncStatus(pageA);
        return s.includes('connected');
      }, { timeout: 10000 }).toBeTruthy();

      // Peer A loads an example
      await pageA.getByRole('button', { name: 'Basics' }).click();
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
    const room = testRoom('peer-cursors');

    try {
      await Promise.all([waitForEditor(pageA, room), waitForEditor(pageB, room)]);

      // Wait for connection
      await expect.poll(async () => {
        const s = await getSyncStatus(pageA);
        return s.includes('connected');
      }, { timeout: 10000 }).toBeTruthy();

      // Peer A clicks in the editor to set cursor position
      await pageA.evaluate(() => {
        const cm = document.querySelector('#canopy-text-editor .cm-content') as HTMLElement;
        cm?.focus();
      });
      await pageA.keyboard.press('Home');
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
    const room = testRoom('outline-sync');

    try {
      await Promise.all([waitForEditor(pageA, room), waitForEditor(pageB, room)]);

      // Wait for connection
      await expect.poll(async () => {
        const s = await getSyncStatus(pageA);
        return s.includes('connected');
      }, { timeout: 10000 }).toBeTruthy();

      // Peer A loads the currying example
      await pageA.getByRole('button', { name: 'Currying' }).click();

      // Peer A's outline should show the loaded module bindings
      await expect.poll(async () => {
        const text = await pageA.getByLabel('AST outline').innerText();
        return text.includes('module [add, add5, sum]');
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
