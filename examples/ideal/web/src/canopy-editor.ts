import { CanopyEvents } from "./events";
import type { CrdtModule } from './types';

type StructureModeSession = {
  applyRemote(syncJson: string): string;
  destroy(): void;
  notifyLocalChange(): void;
  reconcile(): void;
  setBroadcast(fn: (() => void) | null): void;
  setReadonly(readonly: boolean): void;
  setSelectedNode(id: string | null): void;
};

type StructureModeModule = {
  createStructureModeSession(
    parent: HTMLDivElement,
    host: HTMLElement,
    crdtHandle: number,
    crdt: CrdtModule,
  ): StructureModeSession;
};

export class CanopyEditor extends HTMLElement {
  private shadow: ShadowRoot;
  private editorContainer: HTMLDivElement;
  // Structure Mode: lazily loaded PM editor showing AST as blocks
  private structureSession: StructureModeSession | null = null;
  private structureRuntimePromise: Promise<StructureModeModule> | null = null;
  private structureLoadVersion = 0;
  private crdtHandle: number | null = null;
  private crdt: CrdtModule | null = null;
  private mountAbortController: AbortController | null = null;
  private broadcastFn: (() => void) | null = null;
  private pendingSelectedNode: string | null = null;

  static get observedAttributes() {
    return ['mode', 'readonly'];
  }

  constructor() {
    super();
    this.shadow = this.attachShadow({ mode: 'open' });

    const style = document.createElement('style');
    style.textContent = SHADOW_STYLES;
    this.shadow.appendChild(style);

    this.editorContainer = document.createElement('div');
    this.editorContainer.id = 'editor-root';
    this.shadow.appendChild(this.editorContainer);
  }

  connectedCallback() {}

  disconnectedCallback() {
    if (this.mountAbortController) {
      this.mountAbortController.abort();
      this.mountAbortController = null;
    }
    this.destroyPm();
  }

  attributeChangedCallback(name: string, _old: string | null, val: string | null) {
    if (name === 'mode' && val && this.crdt) {
      void this.switchMode(val as 'text' | 'structure');
    }
    if (name === 'readonly') {
      const ro = val !== null && val !== 'false';
      if (this.structureSession) {
        this.structureSession.setReadonly(ro);
      }
    }
  }

  mount(crdtHandle: number, crdt: CrdtModule): void {
    if (this.mountAbortController) this.mountAbortController.abort();
    this.mountAbortController = new AbortController();

    this.destroyPm();

    this.crdtHandle = crdtHandle;
    this.crdt = crdt;

    // Wire sync-received
    const { signal } = this.mountAbortController;
    this.addEventListener('sync-received', ((e: CustomEvent) => {
      let result = "ok";
      if (this.structureSession) {
        result = this.structureSession.applyRemote(e.detail.data);
      } else if (this.crdt && this.crdtHandle !== null) {
        result = this.crdt.apply_sync_json(this.crdtHandle, e.detail.data);
      }
      if (result !== "ok") {
        console.warn("[sync] apply_sync_json failed:", result);
        this.dispatchEvent(new CustomEvent('sync-error', {
          detail: { error: result },
          bubbles: true, composed: true,
        }));
        return;
      }
      this.dispatchEvent(new CustomEvent(CanopyEvents.EXTERNAL_CRDT_CHANGE, {
        bubbles: true, composed: true,
      }));
    }) as EventListener, { signal });

    if (this.mode === 'structure') {
      void this.mountStructureMode();
    } else {
      this.editorContainer.innerHTML = '';
    }
  }

  // ── Structure Mode: PM with block NodeViews ────────────

  private loadStructureRuntime(): Promise<StructureModeModule> {
    if (!this.structureRuntimePromise) {
      this.structureRuntimePromise = (
        import('./structure-runtime') as Promise<StructureModeModule>
      ).catch((error) => {
        this.structureRuntimePromise = null;
        throw error;
      });
    }
    return this.structureRuntimePromise;
  }

  private isReadonly(): boolean {
    const val = this.getAttribute('readonly');
    return val !== null && val !== 'false';
  }

  private async mountStructureMode(): Promise<void> {
    if (this.structureSession || !this.crdt || this.crdtHandle === null) return;

    const loadVersion = ++this.structureLoadVersion;
    try {
      const { createStructureModeSession } = await this.loadStructureRuntime();
      if (
        loadVersion !== this.structureLoadVersion ||
        !this.crdt ||
        this.crdtHandle === null ||
        this.mode !== 'structure'
      ) {
        return;
      }
      const session = createStructureModeSession(
        this.editorContainer,
        this,
        this.crdtHandle,
        this.crdt,
      );
      if (loadVersion !== this.structureLoadVersion || this.mode !== 'structure') {
        session.destroy();
        return;
      }
      this.structureSession = session;
      session.setReadonly(this.isReadonly());
      session.setBroadcast(this.broadcastFn);
      session.setSelectedNode(this.pendingSelectedNode);
    } catch (error) {
      if (loadVersion === this.structureLoadVersion) {
        console.error('[canopy-editor] Failed to load structure mode:', error);
      }
    }
  }

  private destroyPm(): void {
    this.structureLoadVersion += 1;
    if (this.structureSession) {
      this.structureSession.destroy();
      this.structureSession = null;
    }
  }

  // ── Mode switching ─────────────────────────────────────

  private async switchMode(m: 'text' | 'structure'): Promise<void> {
    if (m === 'text') {
      this.destroyPm();
      this.editorContainer.innerHTML = '';
    } else {
      this.editorContainer.innerHTML = '';
      await this.mountStructureMode();
    }
  }

  // ── Properties (Rabbita → editor) ──────────────────────

  set projNode(_json: string) {
    if (this.structureSession) {
      this.structureSession.reconcile();
    }
  }

  set sourceMap(_json: string) { /* bridge reads on demand */ }

  set peers(_json: string) { /* text-mode peer cursors are binding-owned */ }
  set errors(_json: string) { /* TODO: CM6 lint decorations */ }
  set evalResults(_json: string) { /* TODO: CM6 eval ghost decorations */ }

  set selectedNode(id: string | null) {
    this.pendingSelectedNode = id;
    if (!id || !this.crdt || this.crdtHandle === null) return;
    if (this.structureSession) {
      this.structureSession.setSelectedNode(id);
    }
  }

  get mode(): 'text' | 'structure' {
    return (this.getAttribute('mode') as 'text' | 'structure') || 'text';
  }

  set mode(m: 'text' | 'structure') {
    if (m === this.getAttribute('mode')) return;
    this.setAttribute('mode', m);
  }

  setBroadcast(fn: (() => void) | null): void {
    this.broadcastFn = fn;
    this.structureSession?.setBroadcast(fn);
  }

  notifyLocalChange(): void {
    if (this.structureSession) {
      this.structureSession.notifyLocalChange();
      return;
    }
    if (this.broadcastFn) this.broadcastFn();
  }

  setAgentIdentity(name: string, color: string): void {
    void name;
    void color;
  }

  /** Sync CM6 content from CRDT after an external change (undo, redo, structural edit). */
  syncAfterExternalChange(): void {
    if (this.structureSession) {
      this.structureSession.reconcile();
    }
  }
}

customElements.define('canopy-editor', CanopyEditor);

// ── Shadow DOM Styles ─────────────────────────────────────

const SHADOW_STYLES = `
  :host {
    display: block;
    width: 100%;
    height: 100%;
    font-family: var(--canopy-font-mono, 'Iosevka', monospace);
    background: var(--canopy-bg, #161625);
    color: var(--canopy-fg, #e4e4f0);
  }
  #editor-root {
    width: 100%;
    height: 100%;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }

  /* ProseMirror base (structure mode) */
  .ProseMirror {
    position: relative;
    word-wrap: break-word;
    white-space: pre-wrap;
    font-family: var(--canopy-font-mono, 'Iosevka', monospace);
    font-size: var(--text-code, 1.125rem);
    line-height: 1.6;
    outline: none;
    min-height: 200px;
  }

  /* Structure mode blocks */
  .structure-block {
    border: 1px solid var(--canopy-border, #28283e);
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
    color: var(--canopy-muted, #8888a8);
    cursor: grab;
    font-size: 0.6875rem;
  }
  .structure-badge {
    font-size: 0.6875rem;
    font-weight: 600;
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
    color: var(--canopy-fg, #e4e4f0);
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
    color: var(--canopy-fg, #e4e4f0);
  }
  .structure-block.drop-before {
    border-top: 2px solid var(--canopy-accent, #8250df);
  }
  .structure-block.drop-after {
    border-bottom: 2px solid var(--canopy-accent, #8250df);
  }
  .structure-block.drop-inside {
    outline: 2px solid var(--canopy-accent, #8250df);
    outline-offset: -2px;
  }
  .structure-block.dragging {
    opacity: 0.4;
  }

  /* Peer cursor decorations (CM6 text mode) */
  .peer-cursor-widget {
    position: relative;
    display: inline;
    border-left: 2px solid var(--color);
    margin-left: -1px;
    pointer-events: none;
  }
  .peer-cursor-label {
    position: absolute;
    bottom: 100%;
    left: -1px;
    background: var(--color);
    color: #fff;
    font-size: 10px;
    font-family: system-ui, sans-serif;
    padding: 1px 4px;
    border-radius: 2px 2px 2px 0;
    white-space: nowrap;
    pointer-events: none;
    opacity: 0.9;
  }
  .peer-selection {
    background-color: var(--color);
    opacity: 0.2;
  }

  /* Action overlay (which-key / action sheet) */
  .action-overlay-scrim {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.35);
    z-index: 100;
    opacity: 1;
    transition: opacity 100ms cubic-bezier(0.25, 1, 0.5, 1);
  }
  @starting-style {
    .action-overlay-scrim { opacity: 0; }
  }
  .action-overlay-panel {
    position: fixed;
    z-index: 101;
    min-width: 200px;
    max-width: 320px;
    background: var(--canopy-panel-bg, #1a1a2c);
    border: 1px solid var(--canopy-border, #28283e);
    border-radius: 6px;
    padding: 4px 0;
    box-shadow: 0 8px 32px var(--canopy-shadow-heavy, rgba(0, 0, 0, 0.5));
    font-family: var(--canopy-font-mono, 'Iosevka', monospace);
    font-size: var(--text-small, 0.875rem);
    outline: none;
    opacity: 1;
    transform: translateY(0);
    transition: opacity 120ms cubic-bezier(0.25, 1, 0.5, 1),
                transform 120ms cubic-bezier(0.25, 1, 0.5, 1);
  }
  @starting-style {
    .action-overlay-panel { opacity: 0; transform: translateY(4px); }
  }
  @media (prefers-reduced-motion: reduce) {
    .action-overlay-scrim,
    .action-overlay-panel {
      transition: none;
    }
  }
  .action-overlay-list {
    display: flex;
    flex-direction: column;
  }
  .action-overlay-item {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    min-height: 44px;
    box-sizing: border-box;
    cursor: pointer;
    color: var(--canopy-fg, #e4e4f0);
    transition: background 0.1s;
    outline: none;
  }
  .action-overlay-item:hover,
  .action-overlay-item:focus-visible {
    background: var(--canopy-accent-hover, rgba(130, 80, 223, 0.12));
  }
  .action-overlay-item:focus-visible {
    outline: 2px solid var(--canopy-focus-ring, #a070ef);
    outline-offset: -2px;
  }
  .action-overlay-item.danger {
    color: var(--canopy-error-text, #ef4444);
  }
  .action-overlay-item.danger:hover,
  .action-overlay-item.danger:focus-visible {
    background: var(--canopy-error-bg, rgba(207, 34, 46, 0.1));
  }
  .action-overlay-item.danger .action-mnemonic {
    background: var(--canopy-error-bg, rgba(207, 34, 46, 0.1));
    color: var(--canopy-error-text, #ef4444);
  }
  .action-mnemonic {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 20px;
    height: 20px;
    padding: 0 4px;
    border-radius: 3px;
    background: var(--canopy-scrollbar, rgba(255, 255, 255, 0.08));
    color: var(--canopy-keyword, #c792ea);
    font-size: var(--text-label, 0.6875rem);
    font-weight: var(--weight-semibold, 600);
  }
  .action-label-text {
    color: inherit;
  }
  .action-group-label {
    padding: 4px 12px 2px;
    font-size: var(--text-label, 0.6875rem);
    font-weight: var(--weight-semibold, 600);
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--canopy-text-dim, #8a8aaa);
  }

  /* Name prompt */
  .name-prompt-container {
    padding: 8px 12px;
  }
  .name-prompt-label {
    font-size: var(--text-label, 0.6875rem);
    color: var(--canopy-muted, #8888a8);
    margin-bottom: 4px;
  }
  .name-prompt-input-row {
    display: flex;
    gap: 8px;
  }
  .name-prompt-input {
    flex: 1;
    background: var(--canopy-hover-overlay, rgba(255, 255, 255, 0.03));
    border: 1px solid var(--canopy-border, #28283e);
    border-radius: 4px;
    padding: 4px 8px;
    color: var(--canopy-fg, #e4e4f0);
    font-family: var(--canopy-font-mono, 'Iosevka', monospace);
    font-size: var(--text-small, 0.875rem);
    outline: none;
  }
  .name-prompt-input:focus {
    border-color: var(--canopy-focus-ring, #a070ef);
  }
  .name-prompt-error {
    font-size: var(--text-label, 0.6875rem);
    color: var(--canopy-error-text, #ef4444);
    margin-top: 4px;
  }

  /* Mobile: bottom sheet instead of positioned popover */
  @media (max-width: 767px) {
    .action-overlay-scrim {
      background: rgba(0, 0, 0, 0.5);
    }
    .action-overlay-panel {
      top: auto !important;
      left: 0 !important;
      right: 0;
      bottom: 0;
      max-width: none;
      width: 100%;
      border-radius: 12px 12px 0 0;
      padding-top: 12px;
      padding-bottom: env(safe-area-inset-bottom, 8px);
      max-height: 60vh;
      transform: translateY(0);
      overflow-y: auto;
      -webkit-overflow-scrolling: touch;
    }
    /* Drag handle — visual affordance for bottom sheet */
    .action-overlay-panel::before {
      content: '';
      display: block;
      width: 32px;
      height: 4px;
      border-radius: 2px;
      background: var(--canopy-scrollbar, rgba(255, 255, 255, 0.08));
      margin: 0 auto 8px;
    }
    .action-overlay-item {
      padding: 12px 16px;
      min-height: 48px;
      gap: 12px;
    }
    .action-mnemonic {
      min-width: 24px;
      height: 24px;
      font-size: var(--text-caption, 0.8125rem);
    }
    .action-label-text {
      font-size: var(--text-body, 1rem);
    }
    .action-group-label {
      padding: 8px 16px 4px;
    }
    .name-prompt-container {
      padding: 12px 16px;
    }
    .name-prompt-input {
      padding: 8px 12px;
      font-size: var(--text-body, 1rem);
    }
  }
`;
