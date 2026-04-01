// Canopy ProseMirror example — structural editor powered by EditorProtocol.
//
// Architecture:
//   MoonBit CRDT ──ViewPatch──→ PMAdapter ──renders──→ ProseMirror
//   ProseMirror ──UserIntent──→ MoonBit CRDT (via FFI)
//
// No local convert.ts, reconciler.ts, bridge.ts, or schema.ts needed.
// All tree conversion and diffing happens in MoonBit; PMAdapter renders.

import * as crdt from "@moonbit/canopy";
import { PMAdapter } from "../../../lib/editor-adapter";
import type { ViewPatch, ViewNode, UserIntent } from "../../../lib/editor-adapter";
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
      crdt.handle_structural_intent(
        handle,
        intent.op,
        String(intent.node_id),
        ts,
      );
      break;
    }

    case "Undo":
      crdt.handle_undo(handle);
      break;

    case "Redo":
      crdt.handle_redo(handle);
      break;

    case "SelectNode":
    case "SetCursor":
    case "CommitEdit":
      // Selection/cursor intents — no CRDT mutation needed
      return;
  }

  // After any CRDT mutation, compute patches and apply
  reconcile();

  // Broadcast to peers
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

// Install the structural keymap plugin on the PM view
const pmView = adapter.getView();
const newState = pmView.state.reconfigure({
  plugins: [...pmView.state.plugins, structuralKeymap(handleIntent)],
});
pmView.updateState(newState);

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
    // After remote ops arrive, recompute patches and apply
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
