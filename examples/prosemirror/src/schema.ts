import { Schema } from "prosemirror-model";

export const editorSchema = new Schema({
  nodes: {
    doc: { content: "module | term" },
    module: {
      content: "let_def* term",
      attrs: { nodeId: { default: null } },
    },
    let_def: {
      content: "term",
      attrs: { name: { default: "x" }, nodeId: { default: null } },
    },
    lambda: {
      content: "term",
      group: "term",
      attrs: { param: { default: "x" }, nodeId: { default: null } },
    },
    application: {
      content: "term term",
      group: "term",
      attrs: { nodeId: { default: null } },
    },
    binary_op: {
      content: "term term",
      group: "term",
      attrs: { op: { default: "Plus" }, nodeId: { default: null } },
    },
    if_expr: {
      content: "term term term",
      group: "term",
      attrs: { nodeId: { default: null } },
    },
    int_literal: {
      group: "term",
      atom: true,
      attrs: { value: { default: 0 }, nodeId: { default: null } },
    },
    var_ref: {
      group: "term",
      atom: true,
      attrs: { name: { default: "x" }, nodeId: { default: null } },
    },
    unbound_ref: {
      group: "term",
      atom: true,
      attrs: { name: { default: "x" }, nodeId: { default: null } },
    },
    error_node: {
      group: "term",
      atom: true,
      attrs: { message: { default: "" }, nodeId: { default: null } },
    },
    unit: {
      group: "term",
      atom: true,
      attrs: { nodeId: { default: null } },
    },
    text: {},
  },
  marks: {},
});
