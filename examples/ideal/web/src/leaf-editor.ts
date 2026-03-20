import { EditorView as PmView, NodeView } from "prosemirror-view";
import { Node as PmNode } from "prosemirror-model";
import { EditorView as CmView } from "@codemirror/view";
import { createInlineCm } from "./cm-inline";
import type { CrdtBridge } from "./bridge";

/**
 * CM6 inline editor for leaf nodes: int_literal, var_ref, unbound_ref.
 *
 * Each instance is a single-line CodeMirror editor embedded inside a
 * ProseMirror NodeView. Text edits are forwarded to the CrdtBridge
 * (when wired — null until Task 5).
 */
export class TermLeafView implements NodeView {
  dom: HTMLElement;
  cm: CmView;
  node: PmNode;
  updating = false;
  private slider: HTMLInputElement | null = null;

  constructor(
    node: PmNode,
    _pmView: PmView,
    _getPos: () => number | undefined,
    private bridge: CrdtBridge | null,
    private shadowRoot?: ShadowRoot,
  ) {
    this.node = node;
    this.dom = document.createElement("span");
    this.dom.className = `pm-leaf pm-${node.type.name}`;

    const text = this.getTextFromNode(node);
    this.cm = createInlineCm({
      doc: text,
      parent: this.dom,
      root: this.shadowRoot,
      onEdit: this.bridge
        ? (changes) => this.bridge!.handleLeafEdit(this.node.attrs.nodeId, changes)
        : undefined,
      isUpdating: () => this.updating,
    });

    // Add inline range slider for integer literals
    if (node.type.name === "int_literal") {
      const slider = document.createElement("input");
      slider.type = "range";
      slider.min = "0";
      slider.max = "100";
      slider.value = String(node.attrs.value);
      slider.className = "canopy-slider";
      slider.style.width = "60px";
      slider.style.height = "4px";
      slider.style.verticalAlign = "middle";
      slider.style.marginLeft = "4px";
      slider.addEventListener("input", (e) => {
        const newVal = (e.target as HTMLInputElement).value;
        const oldText = this.cm.state.doc.toString();
        this.cm.dispatch({
          changes: { from: 0, to: oldText.length, insert: newVal },
        });
      });
      this.dom.appendChild(slider);
      this.slider = slider;
    }
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
    // Keep slider in sync with the integer value
    if (this.slider && node.type.name === "int_literal") {
      this.slider.value = String(node.attrs.value);
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
