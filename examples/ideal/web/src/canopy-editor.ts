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
} from "./decorations";
import type { PeerCursor, ErrorRange } from "./decorations";
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

  static get observedAttributes() {
    return ['mode', 'readonly'];
  }

  constructor() {
    super();
    this.shadow = this.attachShadow({ mode: 'open' });

    // Inject styles that read CSS custom properties from host
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
    if (this.bridge) {
      this.bridge.destroy();
      this.bridge = null;
    }
    if (this.pmView) {
      this.pmView.destroy();
      this.pmView = null;
    }
  }

  attributeChangedCallback(_name: string, _old: string | null, _val: string | null) {
    // Mode is always read from the attribute via the getter; no internal state to sync.
  }

  // Called by Rabbita's raw_effect(AfterRender)
  mount(crdtHandle: number, crdt: CrdtModule): void {
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

    // Wire keymap: structural-edit-request → bridge
    this.addEventListener(CanopyEvents.STRUCTURAL_EDIT_REQUEST, ((e: CustomEvent) => {
      if (!this.bridge) return;
      e.stopPropagation(); // Don't bubble to Rabbita — bridge handles this
      const { op, nodeId } = e.detail;
      this.bridge.handleStructuralEdit(op, Number(nodeId));
    }) as EventListener);
    // Note: request-undo / request-redo already bubble with composed:true
    // so Rabbita (which owns undo via SyncEditor) can listen for them.

    // Wire sync-received: apply remote CRDT ops through the bridge
    this.addEventListener('sync-received', ((e: CustomEvent) => {
      if (!this.bridge) return;
      this.bridge.applyRemote(e.detail.data);
    }) as EventListener);
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

  set selectedNode(id: string | null) {
    // Task 8: highlight/scroll to node in PM
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
    return {
      int_literal: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new TermLeafView(node, view, getPos, bridge),
      var_ref: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new TermLeafView(node, view, getPos, bridge),
      unbound_ref: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new TermLeafView(node, view, getPos, bridge),
      lambda: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new LambdaView(node, view, getPos, bridge),
      let_def: (node: PmNode, view: EditorView, getPos: () => number | undefined) =>
        new LetDefView(node, view, getPos, bridge),
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
