import { EditorState, NodeSelection } from "prosemirror-state";
import { EditorView } from "prosemirror-view";
import { editorSchema } from "./schema";
import { TermLeafView } from "./leaf-editor";
import { LambdaView, LetDefView } from "./text-nodeview";
import { structuralKeymap } from "./keymap";
import type { CrdtModule } from './types';

export class CanopyEditor extends HTMLElement {
  private shadow: ShadowRoot;
  private editorContainer: HTMLDivElement;
  private pmView: EditorView | null = null;
  private _mode: 'text' | 'structure' = 'text';
  private _crdtHandle: number | null = null;
  private _crdt: CrdtModule | null = null;

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
    if (this.pmView) {
      this.pmView.destroy();
      this.pmView = null;
    }
  }

  attributeChangedCallback(name: string, _old: string | null, val: string | null) {
    if (name === 'mode' && val) {
      this._mode = val as 'text' | 'structure';
    }
  }

  // Called by Rabbita's raw_effect(AfterRender)
  mount(crdtHandle: number, crdt: CrdtModule): void {
    this._crdtHandle = crdtHandle;
    this._crdt = crdt;

    // For now, create an empty doc — reconciler (Task 5) will handle conversion
    const doc = editorSchema.node("doc", null, [
      editorSchema.node("module", { nodeId: 0 }),
    ]);

    const pmState = EditorState.create({
      doc,
      plugins: [
        structuralKeymap(this),
      ],
    });

    this.pmView = new EditorView(this.editorContainer, {
      state: pmState,
      nodeViews: {
        int_literal: (node, view, getPos) => new TermLeafView(node, view, getPos, null),
        var_ref: (node, view, getPos) => new TermLeafView(node, view, getPos, null),
        unbound_ref: (node, view, getPos) => new TermLeafView(node, view, getPos, null),
        lambda: (node, view, getPos) => new LambdaView(node, view, getPos, null),
        let_def: (node, view, getPos) => new LetDefView(node, view, getPos, null),
      },
      dispatchTransaction: (tr) => {
        if (!this.pmView) return;
        this.pmView.updateState(this.pmView.state.apply(tr));
        // Loop prevention: suppress events for external reconciliation
        if (tr.getMeta('fromExternal')) return;
        // Node selection events
        if (tr.selectionSet) {
          const sel = tr.selection;
          if (sel instanceof NodeSelection) {
            this.dispatchEvent(new CustomEvent('node-selected', {
              detail: {
                nodeId: String(sel.node.attrs.nodeId),
                kind: sel.node.type.name,
                label: sel.node.attrs.name || sel.node.attrs.param || String(sel.node.attrs.value) || '',
              },
              bubbles: true, composed: true,
            }));
          }
        }
      },
    });
  }

  // --- Properties (Rabbita -> PM) ---

  set projNode(json: string) {
    // Task 5: reconcile PM from new ProjNode
  }

  set sourceMap(json: string) {
    // Task 5: update source map for position mapping
  }

  set peers(json: string) {
    // Task 12: update peer cursor decorations
  }

  set errors(json: string) {
    // Task 9: update error squiggly decorations
  }

  set selectedNode(id: string | null) {
    // Task 8: highlight/scroll to node in PM
  }

  get mode(): 'text' | 'structure' {
    return this._mode;
  }

  set mode(m: 'text' | 'structure') {
    this._mode = m;
    this.setAttribute('mode', m);
    // Task 10: re-render NodeViews in new style
  }
}

customElements.define('canopy-editor', CanopyEditor);
