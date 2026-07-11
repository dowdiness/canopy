import { keymap } from "prosemirror-keymap";
import { NodeSelection, Plugin } from "prosemirror-state";
import { CanopyEvents } from "./events";

/**
 * ProseMirror keymap plugin for structural operations on AST nodes.
 *
 * Instead of calling the CRDT bridge directly, this fires CustomEvents
 * on the host element (the <canopy-editor> Web Component). The bridge
 * (wired in Task 5) will listen for these events and forward them.
 *
 * Keybindings:
 *   Backspace      — delete selected node
 *   Mod-l          — wrap selected node in lambda
 *   Mod-z          — undo
 *   Mod-Shift-z    — redo
 */
export function structuralKeymap(host: HTMLElement) {
  return keymap({
    "Backspace": (state) => {
      if (!(state.selection instanceof NodeSelection)) return false;
      const nodeId = state.selection.node.attrs.nodeId;
      if (nodeId == null) return false;
      host.dispatchEvent(new CustomEvent(CanopyEvents.STRUCTURAL_EDIT_REQUEST, {
        detail: { op: 'Delete', nodeId: String(nodeId) },
        bubbles: true, composed: true,
      }));
      return true;
    },
    "Mod-l": (state) => {
      if (!(state.selection instanceof NodeSelection)) return false;
      const nodeId = state.selection.node.attrs.nodeId;
      if (nodeId == null) return false;
      host.dispatchEvent(new CustomEvent(CanopyEvents.STRUCTURAL_EDIT_REQUEST, {
        detail: { op: 'WrapInLambda', nodeId: String(nodeId) },
        bubbles: true, composed: true,
      }));
      return true;
    },
    " ": (state) => {
      if (!(state.selection instanceof NodeSelection)) return false;
      const nodeId = state.selection.node.attrs.nodeId;
      if (nodeId == null) return false;
      host.dispatchEvent(new CustomEvent(CanopyEvents.ACTION_OVERLAY_OPEN, {
        detail: { nodeId: String(nodeId) },
        bubbles: true, composed: true,
      }));
      return true;
    },
    "Mod-z": () => {
      host.dispatchEvent(new CustomEvent(CanopyEvents.REQUEST_UNDO, {
        bubbles: true, composed: true,
      }));
      return true;
    },
    "Mod-Shift-z": () => {
      host.dispatchEvent(new CustomEvent(CanopyEvents.REQUEST_REDO, {
        bubbles: true, composed: true,
      }));
      return true;
    },
  });
}

export function actionKeyForwardPlugin(host: HTMLElement) {
  return new Plugin({
    props: {
      handleKeyDown(_view, event) {
        if (!(globalThis as any).__canopy_bridge?.overlayOpen) return false;
        // If the name prompt input has focus, let keys flow to it naturally.
        const nameInput = document.querySelector('.name-prompt-input');
        if (nameInput && document.activeElement === nameInput) return false;
        // Overlay is open — swallow all keys to prevent ProseMirror handling.
        // Only forward Escape and unmodified single-char keys (Shift allowed).
        if (event.key === 'Escape') {
          // Forward Escape
        } else if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
          // Forward printable character (Shift allowed for uppercase mnemonics)
        } else {
          // Swallow but don't forward (modifier combos, function keys, etc.)
          event.preventDefault();
          return true;
        }
        host.dispatchEvent(new CustomEvent(CanopyEvents.ACTION_KEY, {
          detail: event.key,
          bubbles: true,
          composed: true,
        }));
        event.preventDefault();
        return true;
      },
    },
  });
}
