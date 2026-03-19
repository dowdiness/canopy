import type { CrdtModule } from './types';

export class CanopyEditor extends HTMLElement {
  private shadow: ShadowRoot;
  private editorContainer: HTMLDivElement;
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
    // Cleanup PM + CM6 if needed
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
    // Will be filled in Task 4 (PM EditorView creation)
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
