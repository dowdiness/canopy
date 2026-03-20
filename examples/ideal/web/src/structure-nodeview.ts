import { EditorView as PmView, NodeView } from "prosemirror-view";
import { Node as PmNode } from "prosemirror-model";

// Kind tag to display badge
const kindBadges: Record<string, string> = {
  module: "MODULE",
  let_def: "LET",
  lambda: "LAMBDA",
  application: "APP",
  binary_op: "BINOP",
  if_expr: "IF",
  int_literal: "INT",
  var_ref: "VAR",
  unbound_ref: "UNBOUND",
  error_node: "ERROR",
  unit: "UNIT",
};

// Kind tag to border color
const kindColors: Record<string, string> = {
  let_def: "var(--canopy-accent, #8250df)",
  lambda: "var(--canopy-keyword, #c792ea)",
  application: "var(--canopy-muted, #5a5a7a)",
  binary_op: "var(--canopy-operator, #ff5370)",
  if_expr: "var(--canopy-keyword, #c792ea)",
  int_literal: "var(--canopy-number, #f78c6c)",
  var_ref: "var(--canopy-identifier, #82aaff)",
  unbound_ref: "var(--canopy-error, #cf222e)",
  error_node: "var(--canopy-error, #cf222e)",
};

function getStructureLabel(node: PmNode): string | null {
  switch (node.type.name) {
    case "lambda": return `\u03BB${node.attrs.param}`;
    case "let_def": return node.attrs.name;
    case "binary_op": return node.attrs.op;
    default: return null;
  }
}

function getLeafText(node: PmNode): string {
  switch (node.type.name) {
    case "int_literal": return String(node.attrs.value);
    case "var_ref":
    case "unbound_ref": return node.attrs.name;
    case "error_node": return node.attrs.message || "error";
    case "unit": return "()";
    default: return "";
  }
}

/**
 * StructureCompoundView renders compound AST nodes (module, let_def, lambda,
 * application, binary_op, if_expr) as bordered, draggable blocks with a header
 * badge and a contentDOM area for ProseMirror-managed children.
 */
export class StructureCompoundView implements NodeView {
  dom: HTMLElement;
  contentDOM: HTMLElement;
  private node: PmNode;

  constructor(node: PmNode, _view: PmView, _getPos: () => number | undefined) {
    this.node = node;
    const typeName = node.type.name;
    this.dom = document.createElement("div");
    this.dom.className = `structure-block structure-${typeName}`;
    this.dom.draggable = true;
    this.dom.style.borderColor = kindColors[typeName] || "var(--canopy-border)";

    // Header row: grip + badge + label
    const header = document.createElement("div");
    header.className = "structure-header";

    const grip = document.createElement("span");
    grip.className = "structure-grip";
    grip.textContent = "\u2261"; // ≡
    header.appendChild(grip);

    const badge = document.createElement("span");
    badge.className = "structure-badge";
    badge.textContent = kindBadges[typeName] || typeName.toUpperCase();
    badge.style.color = kindColors[typeName] || "var(--canopy-muted)";
    header.appendChild(badge);

    // Show relevant attr as label
    const label = getStructureLabel(node);
    if (label) {
      const labelEl = document.createElement("span");
      labelEl.className = "structure-label";
      labelEl.textContent = label;
      header.appendChild(labelEl);
    }

    this.dom.appendChild(header);

    // Content area for children (PM manages)
    this.contentDOM = document.createElement("div");
    this.contentDOM.className = "structure-children";
    this.dom.appendChild(this.contentDOM);
  }

  update(node: PmNode): boolean {
    if (node.type !== this.node.type) return false;

    // Update label if attrs changed
    const labelEl = this.dom.querySelector(".structure-label");
    const newLabel = getStructureLabel(node);
    if (labelEl && newLabel) {
      labelEl.textContent = newLabel;
    } else if (!labelEl && newLabel) {
      const el = document.createElement("span");
      el.className = "structure-label";
      el.textContent = newLabel;
      this.dom.querySelector(".structure-header")?.appendChild(el);
    } else if (labelEl && !newLabel) {
      labelEl.remove();
    }

    this.node = node;
    return true;
  }
}

/**
 * StructureLeafView renders leaf AST nodes (int_literal, var_ref, unbound_ref,
 * error_node, unit) as compact, non-editable blocks with a badge and value.
 */
export class StructureLeafView implements NodeView {
  dom: HTMLElement;
  private nodeType: string;

  constructor(node: PmNode) {
    this.nodeType = node.type.name;
    const typeName = node.type.name;
    this.dom = document.createElement("div");
    this.dom.className = `structure-block structure-leaf structure-${typeName}`;
    this.dom.style.borderColor = kindColors[typeName] || "var(--canopy-border)";

    const badge = document.createElement("span");
    badge.className = "structure-badge";
    badge.textContent = kindBadges[typeName] || typeName;
    badge.style.color = kindColors[typeName] || "var(--canopy-muted)";
    this.dom.appendChild(badge);

    const value = document.createElement("span");
    value.className = "structure-value";
    value.textContent = getLeafText(node);
    this.dom.appendChild(value);
  }

  update(node: PmNode): boolean {
    if (node.type.name !== this.nodeType) return false;
    const valueEl = this.dom.querySelector(".structure-value");
    if (valueEl) valueEl.textContent = getLeafText(node);
    return true;
  }

  ignoreMutation() { return true; }
}
