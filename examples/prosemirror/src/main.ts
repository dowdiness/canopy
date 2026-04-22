// Canopy ProseMirror example — structural editor powered by EditorProtocol.

import * as crdt from "@moonbit/canopy";
import { EditorState as PmState } from "prosemirror-state";
import { PMAdapter } from "@canopy/editor-adapter";
import type { ViewPatch, ViewNode, UserIntent } from "@canopy/editor-adapter";
import { connectWebSocket } from "./ws-glue";
import { structuralKeymap } from "./keymap";

// ── CRDT setup ──────────────────────────────────────────────

const agentId = "pm-agent-" + Math.random().toString(36).slice(2, 8);
const handle = crdt.create_editor_with_undo(agentId, 300);
crdt.set_text(handle, "let double = \u03BBx.x + x\ndouble 5");

// ── PMAdapter setup ─────────────────────────────────────────

const container = document.getElementById("editor")!;
const adapter = new PMAdapter(container);

// ── Intent dispatch ─────────────────────────────────────────

function handleIntent(intent: UserIntent): void {
  const ts = Date.now();

  switch (intent.type) {
    case "TextEdit": {
      const deleteLen = intent.to - intent.from;
      crdt.handle_text_intent(handle, intent.from, deleteLen, intent.insert, ts);
      break;
    }

    case "StructuralEdit": {
      const paramsJson = Object.keys(intent.params).length > 0
        ? JSON.stringify(intent.params)
        : "";
      const result = crdt.handle_structural_intent(
        handle,
        intent.op,
        String(intent.node_id),
        ts,
        paramsJson,
      );
      if (result !== "ok") {
        console.error("[protocol] structural edit failed:", result);
        return;
      }
      break;
    }

    case "Undo": {
      const didUndo = crdt.handle_undo(handle);
      if (!didUndo) return;
      break;
    }

    case "Redo": {
      const didRedo = crdt.handle_redo(handle);
      if (!didRedo) return;
      break;
    }

    case "SelectNode":
    case "SetCursor":
    case "CommitEdit":
      return;
  }

  reconcile();
  if (broadcastEdit) broadcastEdit();
}

adapter.onIntent(handleIntent);

// ── Reconciliation ──────────────────────────────────────────

function reconcile(): void {
  const patchesJson = crdt.compute_view_patches_json(handle);
  const patches: ViewPatch[] = JSON.parse(patchesJson);
  if (patches.length > 0) {
    adapter.applyPatches(patches);
  }
  updateDebug();
}

// ── Initial render ──────────────────────────────────────────

const viewTreeJson = crdt.get_view_tree_json(handle);
const viewTree: ViewNode | null = JSON.parse(viewTreeJson);
adapter.applyPatches([{ type: "FullTree", root: viewTree }]);
updateDebug();

// ── Structural keymap ───────────────────────────────────────

// Install structural keymap by creating a new PM state with the plugin.
// PMAdapter's view is non-editable but needs tabindex for keyboard focus.
const pmView = adapter.getView();
const oldState = pmView.state;
const newState = PmState.create({
  doc: oldState.doc,
  selection: oldState.selection,
  plugins: [...oldState.plugins, structuralKeymap(handleIntent)],
});
pmView.updateState(newState);

// Allow keyboard focus on the non-editable PM view
pmView.dom.setAttribute("tabindex", "0");

// ── Debug panel ─────────────────────────────────────────────

function updateDebug(): void {
  const debugEl = document.getElementById("debug");
  if (!debugEl) return;

  const errors = JSON.parse(crdt.get_errors_json(handle)) as string[];
  const pretty = crdt.get_ast_pretty(handle);

  debugEl.textContent = errors.length > 0
    ? `Errors:\n${errors.join("\n")}\n\n${pretty}`
    : pretty;
}

// ── WebSocket sync ──────────────────────────────────────────

let broadcastEdit: (() => void) | null = null;

const WS_URL = "ws://localhost:8787?room=main&peer_id=" + encodeURIComponent(agentId);
const sync = connectWebSocket(
  handle,
  crdt as any,
  WS_URL,
  () => {
    reconcile();
  },
);
broadcastEdit = sync.broadcastEdit;

// ── Undo/Redo keybindings ───────────────────────────────────

document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "z") {
    e.preventDefault();
    if (e.shiftKey) {
      handleIntent({ type: "Redo" });
    } else {
      handleIntent({ type: "Undo" });
    }
  }
});

console.log("ProseMirror structural editor ready. Text:", crdt.get_text(handle));
