import type { Page } from '@playwright/test';
import { CanopyEvents } from '../../src/events';

export async function dispatchExternalCrdtChanged(page: Page) {
  await page.evaluate((eventName) => {
    const editor = document.querySelector('#canopy-editor');
    if (!editor) {
      throw new Error('Canopy editor host is not mounted');
    }
    editor.dispatchEvent(new CustomEvent(eventName, {
      detail: { autosave: false },
      bubbles: true,
      composed: true,
    }));
  }, CanopyEvents.EXTERNAL_CRDT_CHANGE);
}
