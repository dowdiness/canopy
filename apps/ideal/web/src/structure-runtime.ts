import { EditorState as PmState, NodeSelection } from "prosemirror-state";
import { EditorView as PmView } from "prosemirror-view";
import { Node as PmNode } from "prosemirror-model";
import { editorSchema } from "./schema";
import { StructureCompoundView, StructureLeafView } from "./structure-nodeview";
import { structuralKeymap, actionKeyForwardPlugin } from "./keymap";
import { CanopyEvents } from "./events";
import { CrdtBridge } from "./bridge";
import { projNodeToDoc } from "./convert";
import {
  peerCursorPlugin,
  errorDecoPlugin,
  evalGhostPlugin,
} from "./decorations";
import type {
  StructureHistoryCallback,
  StructureTreeEditCallback,
} from "./types";

export type StructureModeSession = {
  destroy(): void;
  notifyLocalChange(): void;
  reconcile(snapshot: string): void;
  setBroadcast(fn: (() => void) | null): void;
  setReadonly(readonly: boolean): void;
  setSelectedNode(id: string | null): void;
  setStructureHistoryCallback(callback: StructureHistoryCallback | null): void;
  setStructureTreeEditCallback(callback: StructureTreeEditCallback | null): void;
};

/**
 * Build the initial Structure-mode document from a ProjNode JSON string.
 *
 * When the projection is unavailable (`"null"` — e.g. a transient
 * protected-read failure while switching into Structure mode) or conversion
 * throws, fall back to a schema-valid placeholder.
 *
 * The placeholder MUST satisfy the editor schema: `doc` content is
 * `module | term` and `module` content is `let_def* term`, so an empty
 * `module` is invalid — it threw `RangeError: Invalid content for node
 * module: <>` (#428) and aborted the whole mount. A bare `unit` term is the
 * minimal valid empty document; a later application-supplied snapshot
 * replaces it. There is no renderer-side polling or CRDT read.
 *
 * Exported for regression testing of the fallback path.
 */
export function buildStructureDoc(projJsonStr: string): PmNode {
  if (projJsonStr && projJsonStr !== "null") {
    try {
      return projNodeToDoc(JSON.parse(projJsonStr));
    } catch (error) {
      console.error("[canopy-editor] Failed to build PM doc:", error);
    }
  }
  return editorSchema.node("doc", null, [editorSchema.node("unit")]);
}

function createStructureNodeViews(onEdit: StructureTreeEditCallback) {
  return {
    module: (node: PmNode, view: PmView, getPos: () => number | undefined) =>
      new StructureCompoundView(node, view, getPos, onEdit),
    let_def: (node: PmNode, view: PmView, getPos: () => number | undefined) =>
      new StructureCompoundView(node, view, getPos, onEdit),
    lambda: (node: PmNode, view: PmView, getPos: () => number | undefined) =>
      new StructureCompoundView(node, view, getPos, onEdit),
    application: (node: PmNode, view: PmView, getPos: () => number | undefined) =>
      new StructureCompoundView(node, view, getPos, onEdit),
    binary_op: (node: PmNode, view: PmView, getPos: () => number | undefined) =>
      new StructureCompoundView(node, view, getPos, onEdit),
    if_expr: (node: PmNode, view: PmView, getPos: () => number | undefined) =>
      new StructureCompoundView(node, view, getPos, onEdit),
    int_literal: (node: PmNode, view: PmView) =>
      new StructureLeafView(node, view, onEdit),
    var_ref: (node: PmNode, view: PmView) =>
      new StructureLeafView(node, view, onEdit),
    unbound_ref: (node: PmNode, view: PmView) =>
      new StructureLeafView(node, view, onEdit),
    error_node: (node: PmNode, view: PmView) =>
      new StructureLeafView(node, view, onEdit),
    unit: (node: PmNode, view: PmView) =>
      new StructureLeafView(node, view, onEdit),
  };
}

function setSelectedNode(pmView: PmView, id: string | null): void {
  if (!id) return;
  let targetPos: number | null = null;
  pmView.state.doc.descendants((node, pos) => {
    if (String(node.attrs.nodeId) === id && NodeSelection.isSelectable(node)) {
      targetPos = pos;
      return false;
    }
    return true;
  });
  if (targetPos === null) return;
  let selectionUnchanged = false;
  const currentSelection = pmView.state.selection;
  if (currentSelection instanceof NodeSelection) {
    selectionUnchanged = currentSelection.from === targetPos;
  }
  if (selectionUnchanged) return;
  const tr = pmView.state.tr
    .setSelection(NodeSelection.create(pmView.state.doc, targetPos))
    .scrollIntoView();
  tr.setMeta("fromExternal", true);
  pmView.dispatch(tr);
  pmView.focus();
}

export function createStructureModeSession(
  parent: HTMLDivElement,
  host: HTMLElement,
  initialSnapshot: string,
  initialOnEdit: StructureTreeEditCallback = () => {},
  initialOnHistory: StructureHistoryCallback = () => {},
): StructureModeSession {
  let onEdit = initialOnEdit;
  let onHistory = initialOnHistory;
  const bridge = new CrdtBridge();
  const pmView = new PmView(parent, {
    state: PmState.create({
      doc: buildStructureDoc(initialSnapshot),
      plugins: [
        structuralKeymap(
          host,
          edit => onEdit(edit),
          direction => onHistory(direction),
        ),
        actionKeyForwardPlugin(host),
        peerCursorPlugin(),
        errorDecoPlugin(),
        evalGhostPlugin(),
      ],
    }),
    nodeViews: createStructureNodeViews(edit => onEdit(edit)),
    dispatchTransaction: (tr) => {
      pmView.updateState(pmView.state.apply(tr));
      if (tr.getMeta("fromExternal")) return;
      if (tr.selectionSet) {
        const sel = tr.selection;
        if (sel instanceof NodeSelection) {
          host.dispatchEvent(new CustomEvent(CanopyEvents.NODE_SELECTED, {
            detail: {
              nodeId: String(sel.node.attrs.nodeId),
              kind: sel.node.type.name,
              label: sel.node.attrs.name ?? sel.node.attrs.param ?? String(sel.node.attrs.value ?? ""),
            },
            bubbles: true, composed: true,
          }));
        }
      }
    },
  });

  bridge.setPmView(pmView);

  // Long-press detection for touch devices
  let longPressTimer: ReturnType<typeof setTimeout> | null = null;
  const gestureController = new AbortController();

  parent.addEventListener('pointerdown', (e) => {
    if (e.pointerType !== 'touch') return;
    const startX = e.clientX, startY = e.clientY;
    longPressTimer = setTimeout(() => {
      const sel = pmView.state.selection;
      if (sel instanceof NodeSelection) {
        host.dispatchEvent(new CustomEvent(CanopyEvents.LONG_PRESS, {
          detail: { nodeId: String(sel.node.attrs.nodeId) },
          bubbles: true, composed: true,
        }));
      }
    }, 500);
    const onMove = (me: PointerEvent) => {
      if (Math.abs(me.clientX - startX) > 10 || Math.abs(me.clientY - startY) > 10) cleanup();
    };
    const cleanup = () => {
      if (longPressTimer) { clearTimeout(longPressTimer); longPressTimer = null; }
      parent.removeEventListener('pointermove', onMove);
      parent.removeEventListener('pointerup', cleanup);
      parent.removeEventListener('pointercancel', cleanup);
    };
    parent.addEventListener('pointermove', onMove);
    parent.addEventListener('pointerup', cleanup, { once: true });
    parent.addEventListener('pointercancel', cleanup, { once: true });
  }, { passive: true, signal: gestureController.signal });

  return {
    destroy(): void {
      gestureController.abort();
      bridge.destroy();
      pmView.destroy();
    },
    notifyLocalChange(): void {
      bridge.notifyLocalChange();
    },
    reconcile(snapshot: string): void {
      bridge.reconcile(snapshot);
    },
    setBroadcast(fn: (() => void) | null): void {
      bridge.setBroadcast(fn);
    },
    setReadonly(readonly: boolean): void {
      pmView.setProps({ editable: () => !readonly });
    },
    setSelectedNode(id: string | null): void {
      setSelectedNode(pmView, id);
    },
    setStructureHistoryCallback(callback: StructureHistoryCallback | null): void {
      onHistory = callback ?? (() => {});
    },
    setStructureTreeEditCallback(callback: StructureTreeEditCallback | null): void {
      onEdit = callback ?? (() => {});
    },
  };
}
