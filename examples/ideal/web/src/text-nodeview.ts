import { EditorView as PmView, NodeView } from "prosemirror-view";
import { Node as PmNode } from "prosemirror-model";
import { EditorView as CmView } from "@codemirror/view";
import { EditorState as CmState } from "@codemirror/state";
import type { CrdtBridge } from "./bridge";

/**
 * LambdaView renders: λ <param-editor> . <body>
 *
 * - The param name is a single-line CM6 inline editor
 * - The body (contentDOM) is managed by ProseMirror
 */
export class LambdaView implements NodeView {
  dom: HTMLElement;
  contentDOM: HTMLElement;
  paramCm: CmView;
  node: PmNode;
  updating = false;

  constructor(
    node: PmNode,
    _pmView: PmView,
    _getPos: () => number | undefined,
    private bridge: CrdtBridge | null,
  ) {
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

/**
 * LetDefView renders: let <name-editor> = <init>
 *
 * - The binding name is a single-line CM6 inline editor
 * - The init expression (contentDOM) is managed by ProseMirror
 */
export class LetDefView implements NodeView {
  dom: HTMLElement;
  contentDOM: HTMLElement;
  nameCm: CmView;
  node: PmNode;
  updating = false;

  constructor(
    node: PmNode,
    private pmView: PmView,
    private getPos: () => number | undefined,
    private bridge: CrdtBridge | null,
  ) {
    this.node = node;
    this.dom = document.createElement("div");
    this.dom.className = "pm-let-def";

    // "let" keyword
    const keyword = document.createElement("span");
    keyword.textContent = "let ";
    keyword.className = "pm-let-keyword";
    this.dom.appendChild(keyword);

    // CM6 for binding name
    const nameWrap = document.createElement("span");
    nameWrap.className = "pm-let-name";
    this.nameCm = new CmView({
      state: CmState.create({
        doc: node.attrs.name,
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
            const moduleNodeId = this.getModuleNodeId();
            if (moduleNodeId == null) return;
            const changes: { from: number; to: number; insert: string }[] = [];
            update.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
              changes.push({ from: fromA, to: toA, insert: inserted.toString() });
            });
            if (changes.length > 0) {
              const defIndex = this.getDefIndex();
              this.bridge.handleTokenEdit(moduleNodeId, "name:" + defIndex, changes);
            }
          }),
        ],
      }),
      parent: nameWrap,
    });
    this.dom.appendChild(nameWrap);

    // " = " separator
    const eq = document.createElement("span");
    eq.textContent = " = ";
    eq.className = "pm-let-eq";
    this.dom.appendChild(eq);

    // contentDOM -- PM manages the init expression child
    this.contentDOM = document.createElement("span");
    this.contentDOM.className = "pm-let-init";
    this.dom.appendChild(this.contentDOM);
  }

  /** Get this let_def's index among its sibling let_defs in the parent module */
  private getDefIndex(): number {
    const pos = this.getPos();
    if (pos == null) return 0;
    const resolved = this.pmView.state.doc.resolve(pos);
    return resolved.index(resolved.depth);
  }

  /** Walk up the PM doc to find the parent module node's nodeId */
  private getModuleNodeId(): number | null {
    const pos = this.getPos();
    if (pos == null) return null;
    const resolved = this.pmView.state.doc.resolve(pos);
    // The parent of a let_def should be a module node
    const parent = resolved.parent;
    if (parent && parent.type.name === "module") {
      return parent.attrs.nodeId;
    }
    return null;
  }

  update(node: PmNode): boolean {
    if (node.type.name !== "let_def") return false;
    this.updating = true;
    const newName = node.attrs.name;
    const oldName = this.nameCm.state.doc.toString();
    if (newName !== oldName) {
      this.nameCm.dispatch({
        changes: { from: 0, to: oldName.length, insert: newName },
      });
    }
    this.node = node;
    this.updating = false;
    return true;
  }

  ignoreMutation(mutation: { target: Node }) {
    // Let PM observe mutations inside contentDOM (init expression)
    // but ignore mutations in the name editor and outer structure
    return !this.contentDOM.contains(mutation.target);
  }

  destroy() { this.nameCm.destroy(); }
}
