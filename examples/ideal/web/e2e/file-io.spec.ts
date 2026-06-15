// E2E for the file read/write feature (Open / Save toolbar buttons).
//
// The host prefers the File System Access API (showOpen/SaveFilePicker), which
// opens a native dialog Playwright cannot drive. Each test deletes that API
// before load to force the automatable fallbacks: a <input type=file> for Open
// (a 'filechooser' event) and an <a download> blob for Save (a 'download'
// event). Both fallbacks run the exact same MoonBit path as the native one.

import { test, expect, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';

/** Wait until the CRDT editor is mounted and its handle is published. */
async function waitReady(page: Page) {
  await page.waitForFunction(() => {
    const g = globalThis as any;
    return (
      document.querySelector('#canopy-text-editor .cm-editor') !== null &&
      g.__canopy_crdt &&
      g.__canopy_crdt_handle != null
    );
  }, { timeout: 15_000 });
}

/** Read the current document text straight from the CRDT. */
async function getEditorText(page: Page): Promise<string> {
  return await page.evaluate(() => {
    const g = globalThis as any;
    return g.__canopy_crdt.get_text(g.__canopy_crdt_handle) as string;
  });
}

test.describe('File I/O', () => {
  test('Save writes the editor text to canopy.lambda', async ({ page }) => {
    // Force the download fallback.
    await page.addInitScript(() => {
      delete (window as any).showSaveFilePicker;
    });
    await page.goto('/');
    await waitReady(page);

    const expected = await getEditorText(page);
    expect(expected.length).toBeGreaterThan(0);

    const [download] = await Promise.all([
      page.waitForEvent('download'),
      page.getByRole('button', { name: 'Save' }).click(),
    ]);

    expect(download.suggestedFilename()).toBe('canopy.lambda');
    const path = await download.path();
    expect(readFileSync(path, 'utf-8')).toBe(expected);
  });

  test('Open loads a picked file and the load is undoable', async ({ page }) => {
    // Force the <input type=file> fallback.
    await page.addInitScript(() => {
      delete (window as any).showOpenFilePicker;
    });
    await page.goto('/');
    await waitReady(page);

    const initial = await getEditorText(page);
    const loaded = 'fn loaded_from_file(z : Int) { z }\nloaded_from_file 7';

    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      page.getByRole('button', { name: 'Open' }).click(),
    ]);
    await chooser.setFiles({
      name: 'loaded.lambda',
      mimeType: 'text/plain',
      buffer: Buffer.from(loaded, 'utf-8'),
    });

    // The "file-loaded" event must flow into the CRDT via FileLoaded → set_text.
    await page.waitForFunction(
      (want) => {
        const g = globalThis as any;
        return g.__canopy_crdt.get_text(g.__canopy_crdt_handle) === want;
      },
      loaded,
      { timeout: 10_000 },
    );
    expect(await getEditorText(page)).toBe(loaded);

    // The load was recorded (set_text_and_record), so Undo restores the
    // previous document — the core reason load routes through the undo path.
    await page.getByRole('button', { name: 'Undo' }).click();
    await page.waitForFunction(
      (want) => {
        const g = globalThis as any;
        return g.__canopy_crdt.get_text(g.__canopy_crdt_handle) === want;
      },
      initial,
      { timeout: 10_000 },
    );
    expect(await getEditorText(page)).toBe(initial);
  });
});
