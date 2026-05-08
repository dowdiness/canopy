// PMAdapter: ProseMirror adapter for the EditorProtocol.
//
// Generic schema (tree_node/leaf_node) works for any ViewNode tree.
// Language-specific presentation is handled upstream by proj_to_view_node.
// The PM view is non-editable — all mutations come through applyPatches.

import { EditorView as PmView } from "prosemirror-view";
import { EditorState as PmState, Selection, NodeSelection } from "prosemirror-state";
import type { Transaction } from "prosemirror-state";
import { Schema } from "prosemirror-model";
import type { Node as PmNode, NodeSpec } from "prosemirror-model";
import type { EditorAdapter } from './adapter';
import type { ViewPatch, ViewNode, UserIntent } from './types';

// ── Generic PM Schema ───────────────────────────────────────

const nodeAttrs = {
  node_id: { default: null as number | null },
  kind_tag: { default: "" },
  label: { default: "" },
  css_class: { default: "" },
};

const leafAttrs = {
  ...nodeAttrs,
  text: { default: "" },
};

const nodeSpecs: Record<string, NodeSpec> = {
  doc: {
    content: "tree_node | leaf_node",
  },
  tree_node: {
    content: "(tree_node | leaf_node)*",
    attrs: nodeAttrs,
    toDOM(node) {
      return [
        "div",
        {
          class: `pm-tree-node ${node.attrs.css_class || ""}`.trim(),
          "data-node-id": String(node.attrs.node_id ?? ""),
          "data-kind-tag": node.attrs.kind_tag,
        },
        0,
      ] as const;
    },
  },
  leaf_node: {
    atom: true,
    attrs: leafAttrs,
    toDOM(node) {
      return [
        "span",
        {
          class: `pm-leaf-node ${node.attrs.css_class || ""}`.trim(),
          "data-node-id": String(node.attrs.node_id ?? ""),
          "data-kind-tag": node.attrs.kind_tag,
        },
        node.attrs.text || node.attrs.label || "",
      ] as const;
    },
  },
  text: {},
};

export const pmAdapterSchema = new Schema({
  nodes: nodeSpecs,
  marks: {},
});

// ── ViewNode → PM Node Conversion ──────────────────────────

function viewNodeToPmNode(
  schema: Schema,
  node: ViewNode,
): PmNode {
  if (node.children.length === 0) {
    return schema.node("leaf_node", {
      node_id: node.id,
      kind_tag: node.kind_tag,
      label: node.label,
      css_class: node.css_class,
      text: node.text ?? node.label,
    });
  }

  const children = node.children.map(child => viewNodeToPmNode(schema, child));
  return schema.node("tree_node", {
    node_id: node.id,
    kind_tag: node.kind_tag,
    label: node.label,
    css_class: node.css_class,
  }, children);
}

function viewNodeToDoc(
  schema: Schema,
  root: ViewNode,
): PmNode {
  const content = viewNodeToPmNode(schema, root);
  return schema.node("doc", null, [content]);
}

// ── Node Index ──────────────────────────────────────────────

interface NodeEntry {
  pos: number;
  node: PmNode;
}

function buildNodeIndex(doc: PmNode): Map<number, NodeEntry> {
  const index = new Map<number, NodeEntry>();

  doc.descendants((node, pos) => {
    const nodeId = node.attrs?.node_id;
    if (nodeId != null) {
      index.set(nodeId, { pos, node });
    }
    return true;
  });

  return index;
}

// ── PMAdapter ───────────────────────────────────────────────

export class PMAdapter implements EditorAdapter {
  private view: PmView;
  private schema: Schema;
  private intentCallback: ((intent: UserIntent) => void) | null = null;
  private updating = false;
  private nodeIndex: Map<number, NodeEntry> = new Map();

  constructor(container: HTMLElement, schema?: Schema) {
    this.schema = schema ?? pmAdapterSchema;

    const emptyDoc = this.schema.node("doc", null, [
      this.schema.node("leaf_node", {
        node_id: 0,
        kind_tag: "empty",
        label: "",
        css_class: "",
        text: "",
      }),
    ]);

    this.view = new PmView(container, {
      state: PmState.create({
        doc: emptyDoc,
        schema: this.schema,
      }),
      editable: () => false,
      dispatchTransaction: (tr: Transaction) => {
        const newState = this.view.state.apply(tr);
        this.view.updateState(newState);

        if (tr.docChanged) {
          this.nodeIndex = buildNodeIndex(newState.doc);
        }

        if (this.updating || !this.intentCallback) return;
        if (tr.getMeta("fromAdapter")) return;

        if (tr.selectionSet) {
          const sel = newState.selection;
          const $anchor = sel.$anchor;
          const nodeAfter = $anchor.nodeAfter;
          if (nodeAfter && nodeAfter.attrs?.node_id != null) {
            this.intentCallback({
              type: "SelectNode",
              node_id: nodeAfter.attrs.node_id,
            });
          } else {
            this.intentCallback({
              type: "SetCursor",
              position: sel.anchor,
            });
          }
        }
      },
    });

    this.nodeIndex = buildNodeIndex(this.view.state.doc);
  }

  applyPatches(patches: ViewPatch[]): void {
    for (const patch of patches) {
      this.applyPatch(patch);
    }
  }

  onIntent(callback: (intent: UserIntent) => void): void {
    this.intentCallback = callback;
  }

  destroy(): void {
    this.intentCallback = null;
    this.nodeIndex.clear();
    this.view.destroy();
  }

  getView(): PmView {
    return this.view;
  }

  getSchema(): Schema {
    return this.schema;
  }

  private applyPatch(patch: ViewPatch): void {
    switch (patch.type) {
      case "FullTree":
        this.applyFullTree(patch.root);
        break;

      case "ReplaceNode":
        this.applyReplaceNode(patch.node_id, patch.node);
        break;

      case "InsertChild":
        this.applyInsertChild(patch.parent_id, patch.index, patch.child);
        break;

      case "RemoveChild":
        this.applyRemoveChild(patch.parent_id, patch.child_id);
        break;

      case "UpdateNode":
        this.applyUpdateNode(patch.node_id, patch.label, patch.css_class, patch.text ?? null);
        break;

      case "SelectNode":
        this.applySelectNode(patch.node_id);
        break;

      case "TextChange":
      case "SetDecorations":
      case "SetSelection":
      case "SetDiagnostics":
        break;
    }
  }

  private applyFullTree(root: ViewNode | null): void {
    this.updating = true;
    try {
      let newDoc: PmNode;
      if (root) {
        newDoc = viewNodeToDoc(this.schema, root);
      } else {
        newDoc = this.schema.node("doc", null, [
          this.schema.node("leaf_node", {
            node_id: 0,
            kind_tag: "empty",
            label: "No structure available",
            css_class: "",
            text: "No structure available",
          }),
        ]);
      }

      const tr = this.view.state.tr;
      tr.replaceWith(0, this.view.state.doc.content.size, newDoc.content);
      tr.setMeta("fromAdapter", true);
      this.view.dispatch(tr);
    } finally {
      this.updating = false;
    }
  }

  private applyReplaceNode(nodeId: number, newViewNode: ViewNode): void {
    const entry = this.nodeIndex.get(nodeId);
    if (!entry) return;

    this.updating = true;
    try {
      const newPmNode = viewNodeToPmNode(this.schema, newViewNode);
      const tr = this.view.state.tr;
      const from = entry.pos;
      const to = from + entry.node.nodeSize;
      tr.replaceWith(from, to, newPmNode);
      tr.setMeta("fromAdapter", true);
      this.view.dispatch(tr);
    } finally {
      this.updating = false;
    }
  }

  private applyInsertChild(parentId: number, index: number, childViewNode: ViewNode): void {
    const entry = this.nodeIndex.get(parentId);
    if (!entry) return;

    this.updating = true;
    try {
      const newChild = viewNodeToPmNode(this.schema, childViewNode);
      const tr = this.view.state.tr;

      const parentNode = entry.node;
      let insertPos = entry.pos + 1;

      let childIdx = 0;
      parentNode.forEach((child, offset) => {
        if (childIdx < index) {
          insertPos = entry.pos + 1 + offset + child.nodeSize;
        }
        childIdx++;
      });

      tr.insert(insertPos, newChild);
      tr.setMeta("fromAdapter", true);
      this.view.dispatch(tr);
    } finally {
      this.updating = false;
    }
  }

  private applyRemoveChild(_parentId: number, childId: number): void {
    const childEntry = this.nodeIndex.get(childId);
    if (!childEntry) return;

    this.updating = true;
    try {
      const tr = this.view.state.tr;
      const from = childEntry.pos;
      const to = from + childEntry.node.nodeSize;
      tr.delete(from, to);
      tr.setMeta("fromAdapter", true);
      this.view.dispatch(tr);
    } finally {
      this.updating = false;
    }
  }

  private applyUpdateNode(
    nodeId: number,
    label: string,
    cssClass: string,
    text: string | null,
  ): void {
    const entry = this.nodeIndex.get(nodeId);
    if (!entry) return;

    this.updating = true;
    try {
      const tr = this.view.state.tr;
      const newAttrs = {
        ...entry.node.attrs,
        label,
        css_class: cssClass,
        ...(text != null ? { text } : {}),
      };
      tr.setNodeMarkup(entry.pos, null, newAttrs);
      tr.setMeta("fromAdapter", true);
      this.view.dispatch(tr);
    } finally {
      this.updating = false;
    }
  }

  private applySelectNode(nodeId: number): void {
    const entry = this.nodeIndex.get(nodeId);
    if (!entry) return;

    this.updating = true;
    try {
      const tr = this.view.state.tr;
      const sel = entry.node.isAtom
        ? NodeSelection.create(this.view.state.doc, entry.pos)
        : Selection.near(this.view.state.doc.resolve(entry.pos));
      tr.setSelection(sel);
      tr.setMeta("fromAdapter", true);
      this.view.dispatch(tr);
    } catch (e) {
      console.warn("[PMAdapter] SelectNode failed for node_id", nodeId, e);
    } finally {
      this.updating = false;
    }
  }
}
