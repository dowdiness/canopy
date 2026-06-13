import { EditorView as PmView, NodeView } from "prosemirror-view";
import { Node as PmNode } from "prosemirror-model";
import { EditorView as CmView } from "@codemirror/view";
import { createInlineCm } from "./cm-inline";
import type { CrdtBridge } from "./bridge";

/**
 * LambdaView renders: (<param-editor>) => <body>
 *
 * - The param name is a single-line CM6 inline editor
 * - The body (contentDOM) is managed by ProseMirror
 */
export class LambdaView implements NodeView {
  dom: HTMLElement;
  contentDOM: HTMLElement;
  paramCm: CmView;
  private paramWrap: HTMLElement;
  node: PmNode;
  updating = false;

  constructor(
    node: PmNode,
    _pmView: PmView,
    _getPos: () => number | undefined,
    private bridge: CrdtBridge | null,
    private shadowRoot?: ShadowRoot,
  ) {
    this.node = node;
    this.dom = document.createElement("span");
    this.dom.className = "pm-lambda";

    // opening paren before the lambda parameter
    const prefix = document.createElement("span");
    prefix.textContent = "(";
    prefix.className = "pm-lambda-prefix";
    this.dom.appendChild(prefix);

    // CM6 for param name
    this.paramWrap = document.createElement("span");
    const paramWrap = this.paramWrap;
    paramWrap.className = "pm-lambda-param";
    this.paramCm = createInlineCm({
      doc: node.attrs.param,
      parent: paramWrap,
      root: this.shadowRoot,
      onEdit: this.bridge
        ? (changes) => this.bridge!.handleTokenEdit(this.node.attrs.nodeId, "param", changes)
        : undefined,
      isUpdating: () => this.updating,
    });
    this.dom.appendChild(paramWrap);

    // arrow separator after the lambda parameter
    const dot = document.createElement("span");
    dot.textContent = ") => ";
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

  stopEvent(event: Event) {
    return this.paramWrap.contains(event.target as Node);
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
  private nameWrap: HTMLElement;
  node: PmNode;
  updating = false;

  constructor(
    node: PmNode,
    _pmView: PmView,
    _getPos: () => number | undefined,
    private bridge: CrdtBridge | null,
    private shadowRoot?: ShadowRoot,
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
    this.nameWrap = document.createElement("span");
    const nameWrap = this.nameWrap;
    nameWrap.className = "pm-let-name";
    this.nameCm = createInlineCm({
      doc: node.attrs.name,
      parent: nameWrap,
      root: this.shadowRoot,
      onEdit: this.bridge
        ? (changes) => this.bridge!.handleTokenEdit(this.node.attrs.nodeId, "name", changes)
        : undefined,
      isUpdating: () => this.updating,
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

  stopEvent(event: Event) {
    return this.nameWrap.contains(event.target as Node);
  }

  ignoreMutation(mutation: { target: Node }) {
    // Let PM observe mutations inside contentDOM (init expression)
    // but ignore mutations in the name editor and outer structure
    return !this.contentDOM.contains(mutation.target);
  }

  destroy() { this.nameCm.destroy(); }
}

// ── Compound NodeViews with proper spacing ─────────────────

const OP_DISPLAY: Record<string, string> = {
  Plus: "+",
  Minus: "-",
};

/**
 * ApplicationView renders: <func> <arg>
 * Adds a space between function and argument.
 */
export class ApplicationView implements NodeView {
  dom: HTMLElement;
  contentDOM: HTMLElement;

  constructor(node: PmNode, _view: PmView, _getPos: () => number | undefined) {
    this.dom = document.createElement("span");
    this.dom.className = "pm-application";
    // PM manages children inside contentDOM.
    // We use CSS gap for spacing between children.
    this.contentDOM = this.dom;
  }

  update(node: PmNode): boolean {
    return node.type.name === "application";
  }
}

/**
 * BinaryOpView renders: <left> <op> <right>
 * Inserts the operator symbol between the two operands.
 */
export class BinaryOpView implements NodeView {
  dom: HTMLElement;
  contentDOM: HTMLElement;
  private node: PmNode;

  constructor(node: PmNode, _view: PmView, _getPos: () => number | undefined) {
    this.node = node;
    this.dom = document.createElement("span");
    this.dom.className = "pm-binary-op";
    // PM places children sequentially in contentDOM.
    // Operator spacing handled via CSS (word-spacing on .pm-binary-op).
    this.contentDOM = this.dom;
  }

  update(node: PmNode): boolean {
    if (node.type.name !== "binary_op") return false;
    this.node = node;
    return true;
  }
}

/**
 * IfExprView renders: if <cond> then <then> else <else>
 * Adds keywords between the three children.
 */
export class IfExprView implements NodeView {
  dom: HTMLElement;
  contentDOM: HTMLElement;

  constructor(node: PmNode, _view: PmView, _getPos: () => number | undefined) {
    this.dom = document.createElement("span");
    this.dom.className = "pm-if-expr";
    this.contentDOM = this.dom;
  }

  update(node: PmNode): boolean {
    return node.type.name === "if_expr";
  }
}

/**
 * ModuleView renders children vertically (one let_def per line).
 */
export class ModuleView implements NodeView {
  dom: HTMLElement;
  contentDOM: HTMLElement;

  constructor(node: PmNode, _view: PmView, _getPos: () => number | undefined) {
    this.dom = document.createElement("div");
    this.dom.className = "pm-module";
    this.contentDOM = this.dom;
  }

  update(node: PmNode): boolean {
    return node.type.name === "module";
  }
}
