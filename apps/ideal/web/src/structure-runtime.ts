import { EditorState as PmState, NodeSelection, Selection, AllSelection } from "prosemirror-state";
import { EditorView as PmView } from "prosemirror-view";
import { Node as PmNode } from "prosemirror-model";
import { editorSchema } from "./schema";
import { StructureCompoundView, StructureLeafView } from "./structure-nodeview";
import { structuralKeymap, actionKeyForwardPlugin } from "./keymap";
import { CanopyEvents } from "./events";
import { projNodeToDoc } from "./convert";
import { reconcile } from "./reconciler";
import type { ProjNodeJson } from "./types";
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
  reconcile(snapshot: string): void;
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

// Resolve semantic identity without dispatching, focusing, or scrolling. Shared
// by intentional navigation and snapshot reconciliation's single transaction.
function nodeSelectionForId(doc: PmNode, id: string | null): NodeSelection | null {
  if (!id) return null;
  let targetPos: number | null = null;
  doc.descendants((node, pos) => {
    if (String(node.attrs.nodeId) === id && NodeSelection.isSelectable(node)) {
      targetPos = pos;
      return false;
    }
    return true;
  });
  return targetPos === null ? null : NodeSelection.create(doc, targetPos);
}

function setSelectedNode(pmView: PmView, id: string | null): void {
  const selection = nodeSelectionForId(pmView.state.doc, id);
  if (!selection || selection.eq(pmView.state.selection)) return;
  const tr = pmView.state.tr
    .setSelection(selection)
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
  initialSelectedNode: string | null = null,
): StructureModeSession {
  let onEdit = initialOnEdit;
  let onHistory = initialOnHistory;
  const doc = buildStructureDoc(initialSnapshot);
  const pmView = new PmView(parent, {
    state: PmState.create({
      doc,
      selection: new AllSelection(doc),
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
      // Document reconciliation can change selection through mapping without
      // selectionSet. Report the actual rendered target, including deselection;
      // this event updates selection only and never publishes another snapshot.
      if (tr.selectionSet || tr.docChanged) publishSelection();
    },
  });

  function publishSelection(): void {
    const sel = pmView.state.selection;
    const node = sel instanceof NodeSelection ? sel.node : null;
    host.dispatchEvent(new CustomEvent(CanopyEvents.NODE_SELECTED, {
      detail: {
        nodeId: node?.attrs.nodeId == null ? "" : String(node.attrs.nodeId),
        kind: node?.type.name ?? "",
        label: node?.attrs.name ?? node?.attrs.param ?? String(node?.attrs.value ?? ""),
      },
      bubbles: true, composed: true,
    }));
  }
  // PM's constructor does not synchronize the node-selection DOM class. Apply
  // initial selection through a normal transaction from the neutral state,
  // without focusing the editor or scrolling away from the mode button.
  pmView.dispatch(pmView.state.tr.setSelection(
    nodeSelectionForId(doc, initialSelectedNode) ?? Selection.atStart(doc),
  ).setMeta('fromExternal', true));

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
      pmView.destroy();
    },
    reconcile(snapshot: string): void {
      if (pmView.isDestroyed || !snapshot || snapshot === "null") return;
      const selected = pmView.state.selection;
      const tr = reconcile(pmView.state, JSON.parse(snapshot) as ProjNodeJson);
      if (!tr) return;
      if (selected instanceof NodeSelection && selected.node.attrs.nodeId != null) {
        const surviving = nodeSelectionForId(tr.doc, String(selected.node.attrs.nodeId));
        if (surviving) tr.setSelection(surviving);
      }
      // If the node disappeared, retain PM's mapped fallback and report it.
      // Never replay setSelectedNode here: it intentionally focuses/scrolls.
      pmView.dispatch(tr);
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
