import type { Page } from '@playwright/test';
import { dispatchExternalCrdtChanged } from './dom-events';

export async function setEditorText(page: Page, text: string) {
  await page.evaluate((source) => {
    const g = globalThis as any;
    g.__canopy_crdt.set_text(g.__canopy_crdt_handle, source);
  }, text);
  await dispatchExternalCrdtChanged(page);
}

export async function getEditorText(page: Page): Promise<string> {
  return await page.evaluate(() => {
    const g = globalThis as any;
    return g.__canopy_crdt.get_text(g.__canopy_crdt_handle) as string;
  });
}

export async function getCodeMirrorText(page: Page): Promise<string> {
  return await page.evaluate(() => {
    const content = document.querySelector('#canopy-text-editor .cm-content');
    return (content as HTMLElement | null)?.innerText ?? '';
  });
}
