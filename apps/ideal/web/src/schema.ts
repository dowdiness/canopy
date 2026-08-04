import { Schema } from "prosemirror-model";

export const editorSchema = new Schema({
  nodes: {
    doc: {
      content: "module | term",
    },
    module: {
      content: "let_def* term",
      attrs: { nodeId: { default: null } },
      toDOM() { return ["div", { class: "pm-module" }, 0] as const; },
    },
    let_def: {
      content: "term",
      attrs: { name: { default: "x" }, nodeId: { default: null } },
      // Rendered by LetDefView NodeView — toDOM is fallback
      toDOM(node) { return ["div", { class: "pm-let-def" }, 0] as const; },
    },
    lambda: {
      content: "term",
      group: "term",
      attrs: { param: { default: "x" }, nodeId: { default: null } },
      // Rendered by LambdaView NodeView — toDOM is fallback
      toDOM(node) { return ["span", { class: "pm-lambda" }, 0] as const; },
    },
    application: {
      content: "term term",
      group: "term",
      attrs: { nodeId: { default: null } },
      toDOM() { return ["span", { class: "pm-application" }, 0] as const; },
    },
    binary_op: {
      content: "term term",
      group: "term",
      attrs: { op: { default: "Plus" }, nodeId: { default: null } },
      toDOM(node) {
        return ["span", { class: "pm-binary-op", "data-op": node.attrs.op }, 0] as const;
      },
    },
    if_expr: {
      content: "term term term",
      group: "term",
      attrs: { nodeId: { default: null } },
      toDOM() { return ["span", { class: "pm-if-expr" }, 0] as const; },
    },
    int_literal: {
      group: "term",
      atom: true,
      attrs: { value: { default: 0 }, nodeId: { default: null } },
      // Rendered by TermLeafView NodeView — toDOM is fallback
      toDOM(node) { return ["span", { class: "pm-int-literal" }, String(node.attrs.value)] as const; },
    },
    var_ref: {
      group: "term",
      atom: true,
      attrs: { name: { default: "x" }, nodeId: { default: null } },
      // Rendered by TermLeafView NodeView — toDOM is fallback
      toDOM(node) { return ["span", { class: "pm-var-ref" }, node.attrs.name] as const; },
    },
    unbound_ref: {
      group: "term",
      atom: true,
      attrs: { name: { default: "x" }, nodeId: { default: null } },
      // Rendered by TermLeafView NodeView — toDOM is fallback
      toDOM(node) { return ["span", { class: "pm-unbound-ref" }, node.attrs.name] as const; },
    },
    error_node: {
      group: "term",
      atom: true,
      attrs: { message: { default: "" }, nodeId: { default: null } },
      toDOM(node) { return ["span", { class: "pm-error-node", title: node.attrs.message }, "⚠"] as const; },
    },
    unit: {
      group: "term",
      atom: true,
      attrs: { nodeId: { default: null } },
      toDOM() { return ["span", { class: "pm-unit" }, "()"] as const; },
    },
    text: {},
  },
  marks: {},
});
