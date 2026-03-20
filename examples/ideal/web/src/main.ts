import './canopy-editor';
import type { CanopyEditor } from './canopy-editor';

// Import the CRDT module (handle-based FFI for the Web Component)
import * as crdt from '@moonbit/canopy';

// Import the ideal editor module — this runs MoonBit's main(),
// which mounts the Rabbita app and renders <canopy-editor> into the DOM.
import '@moonbit/ideal-editor';

// Expose CRDT module globally for MoonBit FFI bridge functions
(globalThis as any).__canopy_crdt = crdt;

// Wait for Rabbita to render <canopy-editor> into the DOM, then mount PM+CM6.
// Rabbita renders asynchronously, so we use MutationObserver instead of requestAnimationFrame.
function mountWhenReady() {
  const el = document.querySelector('canopy-editor') as CanopyEditor | null;
  if (el) {
    const handle = crdt.create_editor_with_undo('local', 500);
    const text = 'let id = \\x.x in let apply = \\f.\\x.f x in apply id 42';
    crdt.set_text(handle, text);
    el.mount(handle, crdt);
    return;
  }
  // Element not yet rendered — observe DOM for its appearance
  const observer = new MutationObserver((_mutations, obs) => {
    const found = document.querySelector('canopy-editor') as CanopyEditor | null;
    if (found) {
      obs.disconnect();
      const handle = crdt.create_editor_with_undo('local', 500);
      const text = 'let id = \\x.x in let apply = \\f.\\x.f x in apply id 42';
      crdt.set_text(handle, text);
      found.mount(handle, crdt);
    }
  });
  observer.observe(document.body, { childList: true, subtree: true });
}
mountWhenReady();
