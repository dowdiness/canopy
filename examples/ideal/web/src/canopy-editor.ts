import { CanopyEvents } from "./events";
import type { CrdtModule } from './types';
// Single source of truth for shadow-root styles. `?inline` yields the
// processed CSS as a string (no automatic <style> injection) so we can both
// adopt it as a constructable stylesheet and fall back to a <style> element.
import shadowStyles from '../styles/editor-shadow.css?inline';

// One constructable stylesheet shared across every <canopy-editor> instance.
// Lazily built; null if the engine lacks constructable-stylesheet support, in
// which case callers fall back to a per-instance <style> element.
let sharedShadowSheet: CSSStyleSheet | null = null;
let shadowSheetUnsupported = false;
function getShadowSheet(): CSSStyleSheet | null {
  if (shadowSheetUnsupported) return null;
  if (sharedShadowSheet) return sharedShadowSheet;
  try {
    const sheet = new CSSStyleSheet();
    sheet.replaceSync(shadowStyles);
    sharedShadowSheet = sheet;
    return sheet;
  } catch {
    shadowSheetUnsupported = true;
    return null;
  }
}

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

    const sheet = getShadowSheet();
    let adopted = false;
    if (sheet && 'adoptedStyleSheets' in this.shadow) {
      try {
        this.shadow.adoptedStyleSheets = [...this.shadow.adoptedStyleSheets, sheet];
        adopted = true;
      } catch {
        // If assignment is present but rejected, keep the editor styled via
        // the same inline CSS string rather than failing custom-element setup.
      }
    }
    if (!adopted) {
      const style = document.createElement('style');
      style.textContent = shadowStyles;
      this.shadow.appendChild(style);
    }

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
    if (this.structureSession) {
      this.structureSession.setSelectedNode(id);
    }
    if (!id || !this.crdt || this.crdtHandle === null) return;
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
