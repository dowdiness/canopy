import './canopy-editor';
import type { CanopyEditor } from './canopy-editor';

// Import the ideal editor module — includes CRDT + Rabbita.
// This runs MoonBit's main() which mounts Rabbita and renders <canopy-editor>.
// IMPORTANT: We use this single module for everything (not @moonbit/canopy separately)
// to avoid loading 14MB of duplicated JS.
import * as idealEditor from '@moonbit/ideal-editor';

// The ideal-editor module re-exports all canopy functions.
// Use it as the CRDT module for the Web Component.
const crdt = idealEditor as any;

// Expose CRDT module globally for MoonBit FFI bridge functions
(globalThis as any).__canopy_crdt = crdt;

/**
 * After mounting the editor, wire the text-changed event to click
 * the hidden sync trigger button. This bridges CM6 edits → Rabbita update.
 */
function wireTextSync(el: CanopyEditor) {
  el.addEventListener('text-changed', () => {
    const btn = document.getElementById('canopy-text-sync-trigger');
    if (btn) btn.click();
  });
}

// Wait for Rabbita to render <canopy-editor> into the DOM, then mount PM+CM6.
function mountWhenReady() {
  const el = document.querySelector('canopy-editor') as CanopyEditor | null;
  if (el) {
    doMount(el);
    return;
  }
  const observer = new MutationObserver((_mutations, obs) => {
    const found = document.querySelector('canopy-editor') as CanopyEditor | null;
    if (found) {
      obs.disconnect();
      doMount(found);
    }
  });
  observer.observe(document.body, { childList: true, subtree: true });
}

function doMount(el: CanopyEditor) {
  // Create CRDT editor via the handle-based API.
  // Since we import @moonbit/ideal-editor (which includes canopy),
  // this creates the editor in the SAME module as MoonBit's SyncEditor.
  const handle = crdt.create_editor_with_undo('local', 500);
  const text = 'let id = \\x.x\nlet apply = \\f.\\x.f x\napply id 42';
  crdt.set_text(handle, text);
  el.mount(handle, crdt);
  wireTextSync(el);
}

mountWhenReady();
