import { keymap } from "prosemirror-keymap";
import { NodeSelection } from "prosemirror-state";
import type { UserIntent } from "@canopy/editor-adapter";

/**
 * ProseMirror keymap plugin for structural operations on AST nodes.
 * Only active when a node is selected (NodeSelection).
 *
 * Dispatches UserIntent objects through the provided callback
 * instead of calling CrdtBridge methods directly.
 */
export function structuralKeymap(onIntent: (intent: UserIntent) => void) {
  return keymap({
    "Backspace": (state) => {
      if (!(state.selection instanceof NodeSelection)) return false;
      const nodeId = state.selection.node.attrs.node_id;
      if (nodeId == null) return false;
      onIntent({
        type: "StructuralEdit",
        node_id: nodeId,
        op: "Delete",
        params: {},
      });
      return true;
    },
    "Mod-l": (state) => {
      if (!(state.selection instanceof NodeSelection)) return false;
      const nodeId = state.selection.node.attrs.node_id;
      if (nodeId == null) return false;
      onIntent({
        type: "StructuralEdit",
        node_id: nodeId,
        op: "WrapInLambda",
        params: { var_name: "x" },
      });
      return true;
    },
  });
}
