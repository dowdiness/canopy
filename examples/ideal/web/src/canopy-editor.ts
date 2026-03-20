import { EditorState, NodeSelection } from "prosemirror-state";
import { EditorView } from "prosemirror-view";
import { Node as PmNode } from "prosemirror-model";
import { editorSchema } from "./schema";
import { TermLeafView } from "./leaf-editor";
import { LambdaView, LetDefView } from "./text-nodeview";
import { StructureCompoundView, StructureLeafView } from "./structure-nodeview";
import { structuralKeymap } from "./keymap";
import { CanopyEvents } from "./events";
import { CrdtBridge } from "./bridge";
import { projNodeToDoc } from "./convert";
import {
  peerCursorPlugin,
  peerCursorKey,
  errorDecoPlugin,
  errorDecoKey,
  evalGhostPlugin,
  evalGhostKey,
} from "./decorations";
import type { PeerCursor, ErrorRange, EvalResult } from "./decorations";
import type { CrdtModule, ProjNodeJson } from './types';

/** Extract a human-readable label from a PM node based on its type */
function getNodeLabel(node: PmNode): string {
  switch (node.type.name) {
    case 'int_literal': return String(node.attrs.value);
    case 'var_ref':
    case 'unbound_ref': return node.attrs.name ?? '';
    case 'lambda': return node.attrs.param ?? '';
    case 'let_def': return node.attrs.name ?? '';
    default: return node.type.name;
  }
}

export class CanopyEditor extends HTMLElement {
  private shadow: ShadowRoot;
  private editorContainer: HTMLDivElement;
  private pmView: EditorView | null = null;
  private bridge: CrdtBridge | null = null;
  private mountAbortController: AbortController | null = null;

  static get observedAttributes() {
    return ['mode', 'readonly'];
  }

  constructor() {
    super();
    this.shadow = this.attachShadow({ mode: 'open' });

    // Inject styles into Shadow DOM — host styles don't penetrate
    const style = document.createElement('style');
    style.textContent = `
      :host {
        display: block;
        width: 100%;
        height: 100%;
        font-family: var(--canopy-font-mono, 'JetBrains Mono', monospace);
        background: var(--canopy-bg, #1a1a2e);
        color: var(--canopy-fg, #e8e8f0);
      }
      #editor-root {
        width: 100%;
        height: 100%;
        overflow: auto;
        padding: 16px;
      }

      /* ProseMirror base styles (required for contenteditable to work) */
      .ProseMirror {
        position: relative;
        word-wrap: break-word;
        white-space: pre-wrap;
        white-space: break-spaces;
        font-family: var(--canopy-font-mono, 'JetBrains Mono', monospace);
        font-size: 14px;
        line-height: 1.6;
        outline: none;
        min-height: 200px;
      }
      .ProseMirror-focused {
        outline: none;
      }
      .ProseMirror [contenteditable="false"] {
        white-space: normal;
      }

      /* PM NodeView styles */
      .pm-module {
        padding: 4px 0;
      }
      .pm-let-def {
        padding: 2px 0;
      }
      .pm-let-keyword {
        color: var(--canopy-keyword, #c792ea);
      }
      .pm-let-name .cm-editor {
        color: var(--canopy-identifier, #82aaff);
      }
      .pm-let-eq {
        color: var(--canopy-muted, #5a5a7a);
      }
      .pm-lambda {
        display: inline;
      }
      .pm-lambda-prefix {
        color: var(--canopy-keyword, #c792ea);
      }
      .pm-lambda-param .cm-editor {
        color: var(--canopy-fg, #e8e8f0);
      }
      .pm-lambda-dot {
        color: var(--canopy-muted, #5a5a7a);
      }
      .pm-leaf {
        display: inline;
      }
      .pm-int-literal .cm-editor {
        color: var(--canopy-number, #f78c6c);
      }
      .pm-var-ref .cm-editor {
        color: var(--canopy-identifier, #82aaff);
      }
      .pm-unbound-ref .cm-editor {
        color: var(--canopy-error, #cf222e);
      }
      .pm-binary-op, .pm-application, .pm-if-expr {
        display: inline;
      }
      .pm-error-node {
        color: var(--canopy-error, #cf222e);
      }
      .pm-unit {
        color: var(--canopy-muted, #5a5a7a);
      }

      /* CM6 inline editor overrides inside Shadow DOM */
      .cm-editor {
        display: inline-block !important;
        background: transparent;
      }
      .cm-editor.cm-focused {
        outline: 1px solid var(--canopy-accent, #8250df);
      }
      .cm-content {
        padding: 0 !important;
        caret-color: var(--canopy-fg, #e8e8f0);
      }
      .cm-line {
        padding: 0 2px !important;
      }
      .cm-cursor {
        border-left-color: var(--canopy-fg, #e8e8f0);
      }

      /* Slider */
      .canopy-slider {
        display: inline-flex;
        align-items: center;
        margin-left: 4px;
      }
      .canopy-slider input[type="range"] {
        width: 50px;
        height: 3px;
        accent-color: var(--canopy-number, #f78c6c);
        vertical-align: middle;
      }

      /* Structure mode blocks */
      .structure-block {
        border: 1px solid var(--canopy-border, #2a2a48);
        border-radius: 6px;
        margin: 4px 0;
        padding: 8px 12px;
        background: rgba(255, 255, 255, 0.02);
      }
      .structure-header {
        display: flex;
        align-items: center;
        gap: 6px;
      }
      .structure-grip {
        color: var(--canopy-muted, #5a5a7a);
        cursor: grab;
        font-size: 11px;
      }
      .structure-badge {
        font-size: 10px;
        font-weight: 500;
        letter-spacing: 0.06em;
        text-transform: uppercase;
        padding: 1px 5px;
        border-radius: 3px;
        background: rgba(255, 255, 255, 0.04);
      }
      .structure-label {
        font-family: var(--canopy-font-mono, monospace);
        font-size: 13px;
        font-weight: 600;
        color: var(--canopy-fg, #e8e8f0);
      }
      .structure-children {
        margin-left: 20px;
        margin-top: 6px;
      }
      .structure-leaf {
        display: flex;
        align-items: center;
        gap: 6px;
        padding: 4px 8px;
      }
      .structure-value {
        font-family: var(--canopy-font-mono, monospace);
        font-size: 13px;
        color: var(--canopy-fg, #e8e8f0);
      }

      /* Peer cursors */
      .peer-cursor {
        display: inline-block;
        width: 2px;
        height: 16px;
        border-left: 2px solid;
        position: relative;
        vertical-align: text-bottom;
      }
      .peer-cursor-label {
        position: absolute;
        top: -16px;
        left: -2px;
        font-size: 9px;
        padding: 1px 4px;
        border-radius: 2px;
        color: #fff;
        white-space: nowrap;
      }

      /* Error squigglies */
      .error-squiggly {
        text-decoration: wavy underline var(--canopy-error, #cf222e);
        text-underline-offset: 2px;
      }

      /* Eval ghosts */
      .eval-ghost {
        font-size: 11px;
        color: var(--canopy-muted, #5a5a7a);
        opacity: 0.6;
        margin-left: 12px;
      }
    `;
    this.shadow.appendChild(style);

    this.editorContainer = document.createElement('div');
    this.editorContainer.id = 'editor-root';
    this.shadow.appendChild(this.editorContainer);
  }

  connectedCallback() {
    // PM + CM6 mounted later via mount() call
  }

  disconnectedCallback() {
    if (this.mountAbortController) {
      this.mountAbortController.abort();
      this.mountAbortController = null;
    }
    if (this.bridge) {
      this.bridge.destroy();
      this.bridge = null;
    }
    if (this.pmView) {
      this.pmView.destroy();
      this.pmView = null;
    }
  }

  attributeChangedCallback(name: string, _old: string | null, val: string | null) {
    if (!this.pmView) return; // Not yet mounted
    if (name === 'mode' && val) {
      const m = val as 'text' | 'structure';
      if (this.pmView && this.bridge) {
        this.pmView.setProps({
          nodeViews: m === 'text'
            ? this.createTextNodeViews()
            : this.createStructureNodeViews(),
        });
      }
    }
    if (name === 'readonly') {
      const isReadonly = val !== null && val !== 'false';
      if (this.pmView) {
        this.pmView.setProps({ editable: () => !isReadonly });
      }
    }
  }

  // Called by main.ts after Rabbita renders the element
  mount(crdtHandle: number, crdt: CrdtModule): void {
    // Clean up existing event listeners from previous mount
    if (this.mountAbortController) {
      this.mountAbortController.abort();
    }
    this.mountAbortController = new AbortController();
    const { signal } = this.mountAbortController;

    // Clean up existing instances if mount() is called again
    if (this.bridge) {
      this.bridge.destroy();
      this.bridge = null;
    }
    if (this.pmView) {
      this.pmView.destroy();
      this.pmView = null;
    }

    // Create the bridge
    this.bridge = new CrdtBridge(crdtHandle, crdt);

    // Get initial ProjNode from the CRDT and build PM doc from it
    let doc: PmNode;
    const projJsonStr = crdt.get_proj_node_json(crdtHandle);
    if (projJsonStr && projJsonStr !== "null") {
      const projJson: ProjNodeJson = JSON.parse(projJsonStr);
      doc = projNodeToDoc(projJson);
    } else {
      // Fallback: empty module
      doc = editorSchema.node("doc", null, [
        editorSchema.node("module", { nodeId: 0 }),
      ]);
    }

    const pmState = EditorState.create({
      doc,
      plugins: [
        structuralKeymap(this),
        peerCursorPlugin(),
        errorDecoPlugin(),
        evalGhostPlugin(),
      ],
    });

    this.pmView = new EditorView(this.editorContainer, {
      state: pmState,
      nodeViews: this.mode === 'text'
        ? this.createTextNodeViews()
        : this.createStructureNodeViews(),
      dispatchTransaction: (tr) => {
        if (!this.pmView) return;
        this.pmView.updateState(this.pmView.state.apply(tr));
        // Loop prevention: suppress events for external reconciliation
        if (tr.getMeta('fromExternal')) return;
        // Notify Rabbita that text changed so outline can sync
        if (tr.docChanged) {
          this.dispatchEvent(new CustomEvent('text-changed', {
            bubbles: true, composed: true,
          }));
        }
        // Node selection events
        if (tr.selectionSet) {
          const sel = tr.selection;
          if (sel instanceof NodeSelection) {
            this.dispatchEvent(new CustomEvent(CanopyEvents.NODE_SELECTED, {
              detail: {
                nodeId: String(sel.node.attrs.nodeId),
                kind: sel.node.type.name,
                label: getNodeLabel(sel.node),
              },
              bubbles: true, composed: true,
            }));
          }
        }
      },
    });

    this.bridge.setPmView(this.pmView);

    // Wire keymap: structural-edit-request -> bridge (with abort signal for cleanup)
    this.addEventListener(CanopyEvents.STRUCTURAL_EDIT_REQUEST, ((e: CustomEvent) => {
      if (!this.bridge) return;
      e.stopPropagation(); // Don't bubble to Rabbita -- bridge handles this
      const { op, nodeId } = e.detail;
      this.bridge.handleStructuralEdit(op, Number(nodeId));
    }) as EventListener, { signal });
    // Note: request-undo / request-redo already bubble with composed:true
    // so Rabbita (which owns undo via SyncEditor) can listen for them.

    // Wire sync-received: apply remote CRDT ops through the bridge (with abort signal)
    this.addEventListener('sync-received', ((e: CustomEvent) => {
      if (!this.bridge) return;
      this.bridge.applyRemote(e.detail.data);
    }) as EventListener, { signal });
  }

  // --- Properties (Rabbita -> PM) ---

  set projNode(json: string) {
    // Bridge reads ProjNode directly from CRDT — just trigger reconcile
    if (this.bridge) {
      this.bridge.reconcile();
    }
  }

  set sourceMap(_json: string) {
    // No-op: bridge reads source map from CRDT on demand
  }

  set peers(json: string) {
    if (!this.pmView) return;
    try {
      const peers: PeerCursor[] = JSON.parse(json);
      const tr = this.pmView.state.tr;
      tr.setMeta(peerCursorKey, peers);
      tr.setMeta('fromExternal', true);
      this.pmView.dispatch(tr);
    } catch (err) {
      console.error("[canopy-editor] Failed to parse peers JSON:", err);
    }
  }

  set errors(json: string) {
    if (!this.pmView) return;
    try {
      const errors: ErrorRange[] = JSON.parse(json);
      const tr = this.pmView.state.tr;
      tr.setMeta(errorDecoKey, errors);
      tr.setMeta('fromExternal', true);
      this.pmView.dispatch(tr);
    } catch (err) {
      console.error("[canopy-editor] Failed to parse errors JSON:", err);
    }
  }

  set evalResults(json: string) {
    if (!this.pmView) return;
    try {
      const results: EvalResult[] = JSON.parse(json);
      const tr = this.pmView.state.tr;
      tr.setMeta(evalGhostKey, results);
      tr.setMeta('fromExternal', true);
      this.pmView.dispatch(tr);
    } catch (err) {
      console.error("[canopy-editor] Failed to parse evalResults JSON:", err);
    }
  }

  set selectedNode(id: string | null) {
    if (!this.pmView || !id) return;
    // Walk the PM doc to find the node with matching nodeId attr
    const state = this.pmView.state;
    let targetPos: number | null = null;
    state.doc.descendants((node, pos) => {
      if (targetPos !== null) return false; // already found
      if (node.attrs.nodeId != null && String(node.attrs.nodeId) === id) {
        targetPos = pos;
        return false;
      }
      return true; // keep searching children
    });
    if (targetPos !== null) {
      const tr = state.tr.setSelection(
        NodeSelection.create(state.doc, targetPos)
      ).scrollIntoView();
      tr.setMeta('fromExternal', true);
      this.pmView.dispatch(tr);
    }
  }

  get mode(): 'text' | 'structure' {
    return (this.getAttribute('mode') as 'text' | 'structure') || 'text';
  }

  set mode(m: 'text' | 'structure') {
    if (m === this.getAttribute('mode')) return;
    this.setAttribute('mode', m);
    if (this.pmView && this.bridge) {
      // Force PM to re-create all NodeViews by updating props
      this.pmView.setProps({
        nodeViews: m === 'text'
          ? this.createTextNodeViews()
          : this.createStructureNodeViews(),
      });
    }
  }

  // --- NodeView factories per mode ---

  private createTextNodeViews() {
    const bridge = this.bridge;
    const sr = this.shadow;
    return {
      int_literal: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new TermLeafView(node, view, getPos, bridge, sr),
      var_ref: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new TermLeafView(node, view, getPos, bridge, sr),
      unbound_ref: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new TermLeafView(node, view, getPos, bridge, sr),
      lambda: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new LambdaView(node, view, getPos, bridge, sr),
      let_def: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new LetDefView(node, view, getPos, bridge, sr),
    };
  }

  private createStructureNodeViews() {
    return {
      module: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new StructureCompoundView(node, view, getPos),
      let_def: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new StructureCompoundView(node, view, getPos),
      lambda: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new StructureCompoundView(node, view, getPos),
      application: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new StructureCompoundView(node, view, getPos),
      binary_op: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new StructureCompoundView(node, view, getPos),
      if_expr: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new StructureCompoundView(node, view, getPos),
      int_literal: (node: PmNode) =>
        new StructureLeafView(node),
      var_ref: (node: PmNode) =>
        new StructureLeafView(node),
      unbound_ref: (node: PmNode) =>
        new StructureLeafView(node),
      error_node: (node: PmNode) =>
        new StructureLeafView(node),
      unit: (node: PmNode) =>
        new StructureLeafView(node),
    };
  }

  /** Expose the bridge for external consumers (e.g. Rabbita host for sync) */
  getBridge(): CrdtBridge | null {
    return this.bridge;
  }
}

customElements.define('canopy-editor', CanopyEditor);
