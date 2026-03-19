import { keymap } from "prosemirror-keymap";
import { NodeSelection } from "prosemirror-state";

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
      host.dispatchEvent(new CustomEvent('structural-edit-request', {
        detail: { op: 'Delete', nodeId: String(nodeId) },
        bubbles: true, composed: true,
      }));
      return true;
    },
    "Mod-l": (state) => {
      if (!(state.selection instanceof NodeSelection)) return false;
      const nodeId = state.selection.node.attrs.nodeId;
      if (nodeId == null) return false;
      host.dispatchEvent(new CustomEvent('structural-edit-request', {
        detail: { op: 'WrapInLambda', nodeId: String(nodeId) },
        bubbles: true, composed: true,
      }));
      return true;
    },
    "Mod-z": () => {
      host.dispatchEvent(new CustomEvent('request-undo', {
        bubbles: true, composed: true,
      }));
      return true;
    },
    "Mod-Shift-z": () => {
      host.dispatchEvent(new CustomEvent('request-redo', {
        bubbles: true, composed: true,
      }));
      return true;
    },
  });
}
