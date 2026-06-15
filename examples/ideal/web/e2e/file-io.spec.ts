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
    const b = (globalThis as any).__canopy_bridge;
    return (
      document.querySelector('#canopy-text-editor .cm-editor') !== null &&
      b?.crdt &&
      b.crdtHandle != null
    );
  }, { timeout: 15_000 });
}

/** Read the current document text straight from the CRDT. */
async function getEditorText(page: Page): Promise<string> {
  return await page.evaluate(() => {
    const b = (globalThis as any).__canopy_bridge;
    return b.crdt.get_text(b.crdtHandle) as string;
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
        const b = (globalThis as any).__canopy_bridge;
        return b.crdt.get_text(b.crdtHandle) === want;
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
        const b = (globalThis as any).__canopy_bridge;
        return b.crdt.get_text(b.crdtHandle) === want;
      },
      initial,
      { timeout: 10_000 },
    );
    expect(await getEditorText(page)).toBe(initial);
  });

  test('Save calls window.showSaveFilePicker (receiver preserved)', async ({ page }) => {
    // Stub the API as a real Window method that rejects a lost receiver — the
    // exact failure mode of an extracted-and-called reference in Chrome/Edge.
    // The host must invoke it as window.showSaveFilePicker(...) or this throws
    // "Illegal invocation" and silently falls back to a download.
    await page.addInitScript(() => {
      const w = window as unknown as Record<string, unknown>;
      w.__nativeSaved = null;
      w.showSaveFilePicker = function (this: unknown) {
        if (this !== window) throw new TypeError('Illegal invocation');
        return Promise.resolve({
          createWritable: () =>
            Promise.resolve({
              write: (d: string) => {
                (window as unknown as Record<string, unknown>).__nativeSaved = d;
                return Promise.resolve();
              },
              close: () => Promise.resolve(),
            }),
        });
      };
    });
    await page.goto('/');
    await waitReady(page);
    const expected = await getEditorText(page);

    let downloaded = false;
    page.on('download', () => { downloaded = true; });
    await page.getByRole('button', { name: 'Save' }).click();

    await page.waitForFunction(
      () => (window as unknown as Record<string, unknown>).__nativeSaved !== null,
      { timeout: 5_000 },
    );
    expect(
      await page.evaluate(() => (window as unknown as Record<string, unknown>).__nativeSaved),
    ).toBe(expected);
    expect(downloaded).toBe(false); // native path used, not the fallback
  });

  test('Open calls window.showOpenFilePicker (receiver preserved)', async ({ page }) => {
    const loaded = 'fn from_native_picker(q : Int) { q }';
    await page.addInitScript((text) => {
      const w = window as unknown as Record<string, unknown>;
      w.showOpenFilePicker = function (this: unknown) {
        if (this !== window) throw new TypeError('Illegal invocation');
        return Promise.resolve([
          { getFile: () => Promise.resolve({ text: () => Promise.resolve(text) }) },
        ]);
      };
    }, loaded);
    await page.goto('/');
    await waitReady(page);

    let chooserShown = false;
    page.on('filechooser', () => { chooserShown = true; });
    await page.getByRole('button', { name: 'Open' }).click();

    await page.waitForFunction(
      (want) => {
        const b = (globalThis as any).__canopy_bridge as {
          crdt: { get_text: (h: number) => string };
          crdtHandle: number;
        };
        return b.crdt.get_text(b.crdtHandle) === want;
      },
      loaded,
      { timeout: 10_000 },
    );
    expect(await getEditorText(page)).toBe(loaded);
    expect(chooserShown).toBe(false); // native path used, not the <input> fallback
  });
});
