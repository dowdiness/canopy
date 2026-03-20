import { EditorView as CmView, keymap as cmKeymap, lineNumbers } from "@codemirror/view";
import { EditorState as CmState } from "@codemirror/state";
import { defaultKeymap } from "@codemirror/commands";
import { syntaxHighlighting, HighlightStyle } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";
import { lambda } from "./lang/lambda-language";
import { CanopyEvents } from "./events";
import type { CrdtModule } from './types';

/** Syntax highlighting colors matching the Canopy design tokens */
const lambdaHighlightStyle = HighlightStyle.define([
  { tag: t.keyword, color: "#c792ea" },                        // --canopy-keyword
  { tag: t.definition(t.variableName), color: "#e4e4f0", fontWeight: "600" }, // definition name (bold fg)
  { tag: t.variableName, color: "#82aaff" },                   // --canopy-identifier
  { tag: t.number, color: "#f78c6c" },                         // --canopy-number
  { tag: t.arithmeticOperator, color: "#ff5370" },             // --canopy-operator
  { tag: t.definitionOperator, color: "#787896" },             // --canopy-text-dim (=)
  { tag: t.paren, color: "#787896" },                          // --canopy-text-dim
  { tag: t.punctuation, color: "#787896" },                    // --canopy-text-dim (.)
]);

type StructureModeSession = {
  applyRemote(syncJson: string): void;
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
  // Text Mode: single CM6 editor showing raw source text
  private cmView: CmView | null = null;
  // Structure Mode: lazily loaded PM editor showing AST as blocks
  private structureSession: StructureModeSession | null = null;
  private structureRuntimePromise: Promise<StructureModeModule> | null = null;
  private structureLoadVersion = 0;
  private crdtHandle: number | null = null;
  private crdt: CrdtModule | null = null;
  private mountAbortController: AbortController | null = null;
  private broadcastFn: (() => void) | null = null;
  private pendingSelectedNode: string | null = null;
  private updating = false;

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
    this.destroyCm();
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
      if (this.cmView) {
        // Remount CM6 to apply readonly (no hot reconfigure API for editable)
        this.destroyCm();
        this.editorContainer.innerHTML = '';
        this.mountTextMode();
      }
    }
  }

  mount(crdtHandle: number, crdt: CrdtModule): void {
    if (this.mountAbortController) this.mountAbortController.abort();
    this.mountAbortController = new AbortController();

    this.destroyCm();
    this.destroyPm();

    this.crdtHandle = crdtHandle;
    this.crdt = crdt;

    // Wire sync-received
    const { signal } = this.mountAbortController;
    this.addEventListener('sync-received', ((e: CustomEvent) => {
      if (this.structureSession) {
        this.structureSession.applyRemote(e.detail.data);
      } else if (this.crdt && this.crdtHandle !== null) {
        this.crdt.apply_sync_json(this.crdtHandle, e.detail.data);
      }
      this.syncCmFromCrdt();
      this.dispatchEvent(new CustomEvent(CanopyEvents.TEXT_CHANGE, {
        bubbles: true, composed: true,
      }));
    }) as EventListener, { signal });

    if (this.mode === 'text') {
      this.mountTextMode();
    } else {
      void this.mountStructureMode();
    }
  }

  // ── Text Mode: single CM6 showing raw source text ──────

  private mountTextMode(): void {
    this.destroyPm();
    if (this.cmView) return; // already mounted

    const text = this.crdt!.get_text(this.crdtHandle!);

    this.cmView = new CmView({
      state: CmState.create({
        doc: text,
        extensions: [
          CmView.theme({
            "&": {
              backgroundColor: "transparent",
              color: "var(--canopy-fg, #e4e4f0)",
              fontFamily: "var(--canopy-font-mono, 'Iosevka', monospace)",
              fontSize: "18px",
              height: "100%",
            },
            ".cm-scroller": {
              overflow: "auto",
              height: "100%",
            },
            ".cm-content": {
              caretColor: "var(--canopy-fg, #e4e4f0)",
              padding: "16px",
              minHeight: "100%",
            },
            "&.cm-focused": {
              outline: "none",
            },
            ".cm-cursor": {
              borderLeftColor: "var(--canopy-fg, #e4e4f0)",
            },
            ".cm-gutters": {
              backgroundColor: "transparent",
              color: "var(--canopy-muted, #8888a8)",
              border: "none",
            },
            ".cm-activeLineGutter": {
              backgroundColor: "transparent",
              color: "var(--canopy-fg, #e4e4f0)",
            },
            ".cm-activeLine": {
              backgroundColor: "rgba(255,255,255,0.03)",
            },
          }),
          cmKeymap.of([
            // Keep undo/redo on the CRDT timeline instead of CM local history.
            {
              key: "Mod-z",
              run: () => {
                this.dispatchEvent(new CustomEvent(CanopyEvents.REQUEST_UNDO, {
                  bubbles: true, composed: true,
                }));
                return true;
              },
            },
            {
              key: "Mod-Shift-z",
              run: () => {
                this.dispatchEvent(new CustomEvent(CanopyEvents.REQUEST_REDO, {
                  bubbles: true, composed: true,
                }));
                return true;
              },
            },
            ...defaultKeymap,
          ]),
          CmView.lineWrapping,
          lineNumbers(),
          lambda(),
          syntaxHighlighting(lambdaHighlightStyle),
          // Forward text changes to CRDT
          CmView.updateListener.of(update => {
            if (this.updating || !update.docChanged || !this.crdt || this.crdtHandle === null) return;
            // Get old and new text, compute diff, apply to CRDT
            const newText = update.state.doc.toString();
            // Use set_text_and_record so changes go into undo stack
            if (this.crdt.set_text_and_record) {
              this.crdt.set_text_and_record(this.crdtHandle, newText, Date.now());
            } else {
              this.crdt.set_text(this.crdtHandle, newText);
            }
            // Notify Rabbita
            this.notifyLocalChange();
            this.dispatchEvent(new CustomEvent(CanopyEvents.TEXT_CHANGE, {
              bubbles: true, composed: true,
            }));
          }),
        ],
      }),
      parent: this.editorContainer,
      root: this.shadow,
    });
  }

  private destroyCm(): void {
    if (this.cmView) {
      this.cmView.destroy();
      this.cmView = null;
    }
  }

  /** Sync CM6 content from CRDT (after external changes) */
  private syncCmFromCrdt(): void {
    if (!this.cmView || !this.crdt || this.crdtHandle === null) return;
    this.updating = true;
    const newText = this.crdt.get_text(this.crdtHandle);
    const oldText = this.cmView.state.doc.toString();
    if (newText !== oldText) {
      this.cmView.dispatch({
        changes: { from: 0, to: oldText.length, insert: newText },
      });
    }
    this.updating = false;
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
    this.destroyCm();
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
      this.mountTextMode();
    } else {
      this.destroyCm();
      this.editorContainer.innerHTML = '';
      await this.mountStructureMode();
    }
  }

  // ── Properties (Rabbita → editor) ──────────────────────

  set projNode(_json: string) {
    if (this.mode === 'text') {
      this.syncCmFromCrdt();
    } else if (this.structureSession) {
      this.structureSession.reconcile();
    }
  }

  set sourceMap(_json: string) { /* bridge reads on demand */ }

  set peers(_json: string) { /* TODO: CM6 peer cursor decorations */ }
  set errors(_json: string) { /* TODO: CM6 lint decorations */ }
  set evalResults(_json: string) { /* TODO: CM6 eval ghost decorations */ }

  set selectedNode(id: string | null) {
    this.pendingSelectedNode = id;
    if (!id || !this.crdt || this.crdtHandle === null) return;
    if (this.cmView) {
      // Text mode: find node's span in source map and select it in CM6
      try {
        const smJson = JSON.parse(this.crdt.get_source_map_json(this.crdtHandle));
        const entry = smJson.find((r: any) => String(r.node_id) === id);
        if (entry) {
          const from = entry.start;
          const to = entry.end;
          this.cmView.dispatch({
            selection: { anchor: from, head: to },
            scrollIntoView: true,
          });
          this.cmView.focus();
        }
      } catch { /* source map parse failure — ignore */ }
    } else if (this.structureSession) {
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
`;
