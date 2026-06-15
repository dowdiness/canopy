import type { Page } from '@playwright/test';
import { dispatchExternalCrdtChanged } from './dom-events';

export async function setEditorText(page: Page, text: string) {
  await page.evaluate((source) => {
    const b = (globalThis as any).__canopy_bridge;
    if (b?.crdt && b.crdtHandle != null) b.crdt.set_text(b.crdtHandle, source);
  }, text);
  await dispatchExternalCrdtChanged(page);
}

export async function getEditorText(page: Page): Promise<string> {
  return await page.evaluate(() => {
    const b = (globalThis as any).__canopy_bridge;
    if (b?.crdt && b.crdtHandle != null) return b.crdt.get_text(b.crdtHandle) as string;
    return '';
  });
}

export async function getCodeMirrorText(page: Page): Promise<string> {
  return await page.evaluate(() => {
    const content = document.querySelector('#canopy-text-editor .cm-content');
    return (content as HTMLElement | null)?.innerText ?? '';
  });
}
