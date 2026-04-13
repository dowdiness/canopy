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

/** Compute drop position from mouse Y relative to target element. */
function computeDropPosition(e: DragEvent, el: HTMLElement): "Before" | "After" | "Inside" {
  const rect = el.getBoundingClientRect();
  const y = e.clientY - rect.top;
  const ratio = y / rect.height;
  if (ratio < 0.25) return "Before";
  if (ratio > 0.75) return "After";
  return "Inside";
}

const DROP_CLASSES = ["drop-before", "drop-after", "drop-inside"] as const;

function clearDropClasses(el: HTMLElement) {
  el.classList.remove(...DROP_CLASSES);
}

function setDropClass(el: HTMLElement, position: "Before" | "After" | "Inside") {
  clearDropClasses(el);
  el.classList.add(`drop-${position.toLowerCase()}`);
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

  private view: PmView;

  constructor(node: PmNode, _view: PmView, _getPos: () => number | undefined) {
    this.view = _view;
    this.node = node;
    const typeName = node.type.name;
    this.dom = document.createElement("div");
    this.dom.className = `structure-block structure-${typeName}`;
    this.dom.style.borderColor = kindColors[typeName] || "var(--canopy-border)";

    // Header row: grip + badge + label
    const header = document.createElement("div");
    header.className = "structure-header";

    const grip = document.createElement("span");
    grip.className = "structure-grip";
    grip.textContent = "\u2261"; // ≡
    header.appendChild(grip);

    // Grip-only drag: enable draggable only while grip is held
    grip.addEventListener("mousedown", () => {
      this.dom.draggable = true;
      const reset = () => { this.dom.draggable = false; document.removeEventListener("mouseup", reset); };
      document.addEventListener("mouseup", reset, { once: true });
    });

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

    // Drag-and-drop handlers — read this.node.attrs.nodeId at event time
    // so the ID stays current after update() swaps in a new PM node.

    this.dom.addEventListener("dragstart", (e) => {
      if (!this.view.editable) { e.preventDefault(); return; }
      e.stopPropagation(); // prevent ancestor compound views from overwriting
      e.dataTransfer!.setData("application/x-canopy-node", String(this.node.attrs.nodeId));
      e.dataTransfer!.effectAllowed = "move";
      this.dom.classList.add("dragging");
    });

    this.dom.addEventListener("dragend", () => {
      this.dom.classList.remove("dragging");
      this.dom.draggable = false;
    });

    // Drop on header = exchange (Inside); drop on block edges = Before/After.
    // Children have their own handlers, so the block handler only fires on
    // the header or the block border — both should be exchange targets.
    this.dom.addEventListener("dragover", (e) => {
      e.preventDefault();
      e.stopPropagation();
      e.dataTransfer!.dropEffect = "move";
      // If the hover is within the header area, always show "Inside" (exchange)
      const headerRect = header.getBoundingClientRect();
      const inHeader = e.clientY <= headerRect.bottom;
      setDropClass(this.dom, inHeader ? "Inside" : computeDropPosition(e, this.dom));
    });

    this.dom.addEventListener("dragleave", () => {
      clearDropClasses(this.dom);
    });

    this.dom.addEventListener("drop", (e) => {
      e.preventDefault();
      e.stopPropagation();
      const headerRect = header.getBoundingClientRect();
      const inHeader = e.clientY <= headerRect.bottom;
      const position = inHeader ? "Inside" : computeDropPosition(e, this.dom);
      clearDropClasses(this.dom);
      if (!this.view.editable) return;
      const nid = this.node.attrs.nodeId as number;
      const sourceId = e.dataTransfer!.getData("application/x-canopy-node");
      if (!sourceId || sourceId === String(nid)) return;

      this.dom.dispatchEvent(new CustomEvent("structural-edit-request", {
        bubbles: true,
        composed: true, // cross shadow DOM boundary
        detail: {
          type: "Drop",
          source: Number(sourceId),
          target: nid,
          position,
        },
      }));
    });
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
  private node: PmNode;
  private nodeType: string;

  constructor(node: PmNode) {
    this.node = node;
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

    // Drop target handlers — leaf nodes accept drops for exchange
    this.dom.addEventListener("dragover", (e) => {
      e.preventDefault();
      e.stopPropagation();
      e.dataTransfer!.dropEffect = "move";
      setDropClass(this.dom, computeDropPosition(e, this.dom));
    });

    this.dom.addEventListener("dragleave", () => {
      clearDropClasses(this.dom);
    });

    this.dom.addEventListener("drop", (e) => {
      e.preventDefault();
      e.stopPropagation();
      const position = computeDropPosition(e, this.dom);
      clearDropClasses(this.dom);
      const nid = this.node.attrs.nodeId as number;
      const sourceId = e.dataTransfer!.getData("application/x-canopy-node");
      if (!sourceId || sourceId === String(nid)) return;

      this.dom.dispatchEvent(new CustomEvent("structural-edit-request", {
        bubbles: true,
        composed: true,
        detail: {
          type: "Drop",
          source: Number(sourceId),
          target: nid,
          position,
        },
      }));
    });
  }

  update(node: PmNode): boolean {
    if (node.type.name !== this.nodeType) return false;
    const valueEl = this.dom.querySelector(".structure-value");
    if (valueEl) valueEl.textContent = getLeafText(node);
    this.node = node;
    return true;
  }

  ignoreMutation() { return true; }
}
