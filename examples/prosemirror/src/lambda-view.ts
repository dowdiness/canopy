import { EditorView as PmView, NodeView } from "prosemirror-view";
import { Node as PmNode } from "prosemirror-model";
import { EditorView as CmView } from "@codemirror/view";
import { EditorState as CmState } from "@codemirror/state";
import type { CrdtBridge } from "./bridge";

export class LambdaView implements NodeView {
  dom: HTMLElement;
  contentDOM: HTMLElement;
  paramCm: CmView;
  node: PmNode;
  updating = false;

  constructor(node: PmNode, _pmView: PmView, _getPos: () => number | undefined, private bridge?: CrdtBridge) {
    this.node = node;
    this.dom = document.createElement("span");
    this.dom.className = "pm-lambda";

    // lambda prefix
    const prefix = document.createElement("span");
    prefix.textContent = "\u03BB";
    prefix.className = "pm-lambda-prefix";
    this.dom.appendChild(prefix);

    // CM6 for param name
    const paramWrap = document.createElement("span");
    paramWrap.className = "pm-lambda-param";
    this.paramCm = new CmView({
      state: CmState.create({
        doc: node.attrs.param,
        extensions: [
          CmView.theme({
            "&": { display: "inline-block", padding: "0 2px" },
            ".cm-content": { padding: "0" },
            ".cm-line": { padding: "0" },
            "&.cm-focused": { outline: "1px solid #66f" },
          }),
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
              this.bridge.handleTokenEdit(this.node.attrs.nodeId, "param", changes);
            }
          }),
        ],
      }),
      parent: paramWrap,
    });
    this.dom.appendChild(paramWrap);

    // dot separator
    const dot = document.createElement("span");
    dot.textContent = ".";
    dot.className = "pm-lambda-dot";
    this.dom.appendChild(dot);

    // contentDOM -- PM manages the body child here
    this.contentDOM = document.createElement("span");
    this.contentDOM.className = "pm-lambda-body";
    this.dom.appendChild(this.contentDOM);
  }

  update(node: PmNode): boolean {
    if (node.type.name !== "lambda") return false;
    this.updating = true;
    const newParam = node.attrs.param;
    const oldParam = this.paramCm.state.doc.toString();
    if (newParam !== oldParam) {
      this.paramCm.dispatch({
        changes: { from: 0, to: oldParam.length, insert: newParam },
      });
    }
    this.node = node;
    this.updating = false;
    return true;
  }

  ignoreMutation(mutation: { target: Node }) {
    // Let PM observe mutations inside contentDOM (lambda body)
    // but ignore mutations in the param editor and outer structure
    return !this.contentDOM.contains(mutation.target);
  }
  destroy() { this.paramCm.destroy(); }
}
