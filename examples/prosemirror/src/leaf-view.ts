import { EditorView as PmView, NodeView } from "prosemirror-view";
import { Node as PmNode } from "prosemirror-model";
import { EditorView as CmView } from "@codemirror/view";
import { EditorState as CmState } from "@codemirror/state";
import type { CrdtBridge } from "./bridge";

export class TermLeafView implements NodeView {
  dom: HTMLElement;
  cm: CmView;
  node: PmNode;
  updating = false;

  constructor(node: PmNode, _pmView: PmView, _getPos: () => number | undefined, private bridge?: CrdtBridge) {
    this.node = node;
    this.dom = document.createElement("span");
    this.dom.className = `pm-leaf pm-${node.type.name}`;

    const text = this.getTextFromNode(node);
    this.cm = new CmView({
      state: CmState.create({
        doc: text,
        extensions: [
          // Minimal inline editor: no gutters, no line numbers
          CmView.theme({
            "&": { display: "inline-block", padding: "0 2px" },
            ".cm-content": { padding: "0" },
            ".cm-line": { padding: "0" },
            ".cm-editor": { display: "inline" },
            "&.cm-focused": { outline: "1px solid #66f" },
          }),
          // Single-line: prevent Enter from creating newlines
          CmState.transactionFilter.of(tr => {
            if (tr.newDoc.lines > 1) return [];
            return tr;
          }),
          // Forward edits to CRDT bridge
          CmView.updateListener.of(update => {
            if (this.updating || !update.docChanged || !this.bridge) return;
            const changes: { from: number; to: number; insert: string }[] = [];
            update.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
              changes.push({ from: fromA, to: toA, insert: inserted.toString() });
            });
            if (changes.length > 0) {
              this.bridge.handleLeafEdit(this.node.attrs.nodeId, changes);
            }
          }),
        ],
      }),
      parent: this.dom,
    });
  }

  private getTextFromNode(node: PmNode): string {
    switch (node.type.name) {
      case "int_literal": return String(node.attrs.value);
      case "var_ref":
      case "unbound_ref": return node.attrs.name;
      default: return "";
    }
  }

  update(node: PmNode): boolean {
    if (node.type !== this.node.type) return false;
    this.updating = true;
    const newText = this.getTextFromNode(node);
    const oldText = this.cm.state.doc.toString();
    if (newText !== oldText) {
      this.cm.dispatch({
        changes: { from: 0, to: oldText.length, insert: newText },
      });
    }
    this.node = node;
    this.updating = false;
    return true;
  }

  selectNode() { this.cm.focus(); }
  stopEvent() { return true; }
  ignoreMutation() { return true; }
  destroy() { this.cm.destroy(); }
}
