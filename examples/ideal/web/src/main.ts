import './canopy-editor';
import * as cmCommands from '@codemirror/commands';
import { HighlightStyle, syntaxHighlighting } from '@codemirror/language';
import * as cmState from '@codemirror/state';
import * as cmView from '@codemirror/view';
import { tags as t } from '@lezer/highlight';
import type { CanopyEditor } from './canopy-editor';
import { peerCursors, updatePeerCursorsFromJson } from './cm6-peer-cursors';
import { canopyEditTimestampMs } from './edit-clock';
import { CanopyEvents } from './events';
import { lambda } from './lang/lambda-language';
import { SyncClient } from './sync';
import type { CrdtModule } from './types';

type StructuralEditDetail = {
  op?: string;
  nodeId?: string;
  position?: string;
  source?: string | number;
  target?: string | number;
  type?: string;
};

type ExternalCrdtChangedDetail = {
  autosave?: boolean;
};

type CmExtensionFactory = (cm: Record<string, any>) => any | any[];

interface CanopyBridgeShape {
  agentId: string;
  sessionStartMs: number;
  createLambdaExtensions: CmExtensionFactory;
  createPeerCursorExtension: CmExtensionFactory;
  crdt?: CrdtModule;
  crdtHandle?: number;
  triggerAutosave?: () => void;
  onSelectionChanged?: (from: number, to: number) => void;
  scheduleWatchdog?: (handle: number, requestId: number, timeoutMs: number) => void;
  onStatusChange?: (handle: number, encoded: string) => void;
  overlayOpen?: boolean;
  perfCurrent?: { spans: Record<string, number>; _starts?: Record<string, number> } | null;
  updateCmPeerCursors?: () => void;
}

type CanopyGlobal = typeof globalThis & {
  __canopy_bridge?: CanopyBridgeShape;
  __canopy_codemirror?: Record<string, any>;
};

const canopyGlobal = globalThis as CanopyGlobal;
const AGENT_ID_STORAGE_KEY = 'canopy-ideal-agent-id';
const STORAGE_KEY_PREFIX = 'canopy-doc-';
const SKIP_SYNC = import.meta.env.VITE_CANOPY_SKIP_SYNC === '1';
let crdtPromise: Promise<CrdtModule> | null = null;
let saveTimer: ReturnType<typeof setTimeout> | null = null;
let activeSyncClient: SyncClient | null = null;
let _crdt: CrdtModule | null = null;
let _handle: number | null = null;
let editorEventsController: AbortController | null = null;
let beforeUnloadRegistered = false;
let ephemeralCleanupTimer: ReturnType<typeof setInterval> | null = null;

const lambdaHighlightStyle = HighlightStyle.define([
  { tag: t.keyword, color: '#c792ea' },
  { tag: t.definition(t.variableName), color: '#e4e4f0', fontWeight: '600' },
  { tag: t.variableName, color: '#82aaff' },
  { tag: t.number, color: '#f78c6c' },
  { tag: t.arithmeticOperator, color: '#ff5370' },
  { tag: t.punctuation, color: '#ff5370' },
  { tag: t.paren, color: '#b8b8d0' },
  { tag: t.definitionOperator, color: '#ff5370' },
]);

function loadCrdtModule(): Promise<CrdtModule> {
  if (!crdtPromise) {
    // Install the host bridge BEFORE importing the MoonBit module.
    // MoonBit's init_model reads bridge.agentId to create the CRDT editor.
    canopyGlobal.__canopy_bridge = {
      agentId: getSessionAgentId(),
      sessionStartMs: Date.now(),
      createLambdaExtensions: () => [
        lambda(),
        syntaxHighlighting(lambdaHighlightStyle),
      ],
      createPeerCursorExtension: peerCursors,
    };
    canopyGlobal.__canopy_codemirror = { ...cmState, ...cmView, ...cmCommands };
    // Loading the MoonBit module also runs Rabbita's main(), which renders <canopy-editor>.
    crdtPromise = import('@moonbit/ideal-editor') as Promise<CrdtModule>;
  }
  return crdtPromise;
}

function createAgentId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return `ideal-${crypto.randomUUID()}`;
  }
  return `ideal-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

function getSessionAgentId(): string {
  try {
    const existing = window.sessionStorage.getItem(AGENT_ID_STORAGE_KEY);
    if (existing) return existing;
    const agentId = createAgentId();
    window.sessionStorage.setItem(AGENT_ID_STORAGE_KEY, agentId);
    return agentId;
  } catch {
    return createAgentId();
  }
}

function getRoomId(): string {
  const hash = location.hash.slice(1);
  if (hash) return hash;
  const id = (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function')
    ? crypto.randomUUID().slice(0, 8)
    : Math.random().toString(36).slice(2, 10);
  history.replaceState(null, '', '#' + id);
  return id;
}

function saveToLocalStorage(handle: number, roomId: string, crdt: CrdtModule) {
  if (saveTimer !== null) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    try {
      const state = crdt.export_all_json(handle);
      localStorage.setItem(STORAGE_KEY_PREFIX + roomId, state);
    } catch (e) {
      console.warn('Failed to save to localStorage:', e);
    }
  }, 1000);
}

function saveNow(handle: number, roomId: string, crdt: CrdtModule) {
  if (saveTimer !== null) {
    clearTimeout(saveTimer);
    saveTimer = null;
  }
  try {
    const state = crdt.export_all_json(handle);
    localStorage.setItem(STORAGE_KEY_PREFIX + roomId, state);
  } catch (e) {
    console.warn('Failed to save to localStorage:', e);
  }
}

function triggerAutosave() {
  if (!_crdt || _handle == null) return;
  const roomId = location.hash.slice(1);
  if (roomId) {
    saveToLocalStorage(_handle, roomId, _crdt);
  }
}

// ── File I/O host (injected into MoonBit via register_file_host) ──────────
// MoonBit calls these in response to the Open/Save toolbar buttons. `save`
// writes text out; `open` reads a file and feeds it back into the TEA loop by
// dispatching a "file-loaded" CustomEvent (rabbita_dom_sub.mbt listens for it).

async function saveTextFile(content: string, suggestedName: string): Promise<void> {
  const w = window as unknown as {
    showSaveFilePicker?: (opts: unknown) => Promise<{
      createWritable: () => Promise<{ write: (d: string) => Promise<void>; close: () => Promise<void> }>;
    }>;
  };
  if (typeof w.showSaveFilePicker === 'function') {
    try {
      // Call as a method so the receiver stays `window`; invoking an extracted
      // reference bare throws "Illegal invocation" in Chrome/Edge.
      const fileHandle = await w.showSaveFilePicker({
        suggestedName,
        types: [{ description: 'Text', accept: { 'text/plain': ['.lambda', '.txt'] } }],
      });
      const writable = await fileHandle.createWritable();
      await writable.write(content);
      await writable.close();
      return;
    } catch (e) {
      if ((e as DOMException)?.name === 'AbortError') return; // user cancelled
      // Other failures (permission, etc.) fall through to the download path.
    }
  }
  const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = suggestedName;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function pickFileViaInput(): Promise<string | null> {
  return new Promise((resolve) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.lambda,.txt,text/plain';
    input.style.display = 'none';
    input.addEventListener('change', async () => {
      const file = input.files?.[0];
      input.remove();
      if (!file) {
        resolve(null);
        return;
      }
      // Resolve null ("nothing chosen") if the read rejects, so the outer
      // Promise never hangs on a failed file.text().
      try {
        resolve(await file.text());
      } catch {
        resolve(null);
      }
    });
    // Dismissing the dialog fires 'cancel' (modern browsers) — without this the
    // Promise and the detached <input> would leak for the page lifetime.
    input.addEventListener('cancel', () => {
      input.remove();
      resolve(null);
    });
    document.body.appendChild(input);
    input.click();
  });
}

async function openTextFile(): Promise<void> {
  const w = window as unknown as {
    showOpenFilePicker?: (opts: unknown) => Promise<Array<{ getFile: () => Promise<File> }>>;
  };
  let content: string | null = null;
  if (typeof w.showOpenFilePicker === 'function') {
    try {
      // Method call keeps the receiver as `window` (see saveTextFile).
      const [fileHandle] = await w.showOpenFilePicker({ multiple: false });
      content = await (await fileHandle.getFile()).text();
    } catch (e) {
      if ((e as DOMException)?.name === 'AbortError') return; // user cancelled
      // Other failures fall through to the <input> fallback.
    }
  }
  if (content === null) content = await pickFileViaInput();
  if (content === null) return; // nothing chosen
  const target = document.getElementById('canopy-text-editor');
  target?.dispatchEvent(new CustomEvent(CanopyEvents.FILE_LOADED, {
    detail: content,
    bubbles: true,
    composed: true,
  }));
}

function updateCmPeerCursors() {
  if (!_crdt || _handle == null) return;
  const json = _crdt.ephemeral_get_peer_cursors_json(_handle);
  updatePeerCursorsFromJson(json);
}

/** Generate a deterministic color from agent ID (hash -> HSL with fixed S/L). */
function agentColor(agentId: string): string {
  let hash = 0;
  for (let i = 0; i < agentId.length; i++) {
    hash = ((hash << 5) - hash + agentId.charCodeAt(i)) | 0;
  }
  const hue = ((hash % 360) + 360) % 360;
  return `hsl(${hue}, 70%, 55%)`;
}

/** Derive a short display name from the agent ID. */
function agentDisplayName(agentId: string): string {
  // Use last 4 chars of the ID as the display name
  const suffix = agentId.slice(-4);
  return `Peer-${suffix}`;
}

function dispatchExternalCrdtChanged(el: CanopyEditor, detail?: ExternalCrdtChangedDetail) {
  el.dispatchEvent(new CustomEvent(CanopyEvents.EXTERNAL_CRDT_CHANGE, {
    detail,
    bubbles: true,
    composed: true,
  }));
}

function dispatchStructuralEditApplied(el: CanopyEditor, detail: StructuralEditDetail) {
  const op = detail.op ?? detail.type ?? "";
  const nodeId = detail.nodeId ?? String(detail.target ?? "");
  el.dispatchEvent(new CustomEvent(CanopyEvents.STRUCTURAL_EDIT_APPLIED, {
    detail: { op, nodeId },
    bubbles: true,
    composed: true,
  }));
}

function wireEditorEvents(el: CanopyEditor) {
  // Abort previous listeners if called again (prevents accumulation)
  if (editorEventsController) editorEventsController.abort();
  editorEventsController = new AbortController();
  const { signal } = editorEventsController;

  el.addEventListener(CanopyEvents.EXTERNAL_CRDT_CHANGE, ((event: Event) => {
    const detail = (event as CustomEvent<ExternalCrdtChangedDetail>).detail;
    if (detail?.autosave !== false) {
      triggerAutosave();
    }
  }) as EventListener, { signal });
  el.addEventListener(CanopyEvents.STRUCTURAL_EDIT_REQUEST, ((event: Event) => {
    const detail = (event as CustomEvent<StructuralEditDetail>).detail ?? {};
    if (!_crdt || _handle == null) return;
    const crdt = _crdt;
    const handle = _handle;

    let result: string;
    if (detail.type === "Drop") {
      // Drag-and-drop: source/target/position payload → apply_tree_edit_json
      const opJson = JSON.stringify({
        type: "Drop",
        source: detail.source,
        target: detail.target,
        position: detail.position,
      });
      result = crdt.apply_tree_edit_json(handle, opJson, canopyEditTimestampMs());
    } else {
      // Standard structural edit: op/nodeId → handle_structural_intent
      const { op, nodeId } = detail as StructuralEditDetail;
      if (!op || !nodeId) return;
      result = crdt.handle_structural_intent(handle, op, nodeId, canopyEditTimestampMs(), "");
    }

    if (result !== "ok") {
      console.error("[protocol] structural edit failed:", result);
      return;
    }
    // Sync CM6 from CRDT after structural edit
    el.syncAfterExternalChange();
    el.notifyLocalChange();
    // Trigger Rabbita refresh
    triggerAutosave();
    dispatchStructuralEditApplied(el, detail);
  }) as EventListener, { signal });
  el.addEventListener(CanopyEvents.REQUEST_UNDO, () => {
    if (!_crdt || _handle == null) return;
    const didUndo = _crdt.handle_undo(_handle);
    if (didUndo) {
      el.syncAfterExternalChange();
      el.notifyLocalChange();
      dispatchExternalCrdtChanged(el);
    }
  }, { signal });
  el.addEventListener(CanopyEvents.REQUEST_REDO, () => {
    if (!_crdt || _handle == null) return;
    const didRedo = _crdt.handle_redo(_handle);
    if (didRedo) {
      el.syncAfterExternalChange();
      el.notifyLocalChange();
      dispatchExternalCrdtChanged(el);
    }
  }, { signal });

  // When remote ephemeral data arrives, update text-mode peer cursor decorations.
  el.addEventListener('sync-cursors-updated', () => {
    updateCmPeerCursors();
  }, { signal });

  // When local cursor changes, broadcast ephemeral data to peers
  el.addEventListener('ephemeral-local-update', () => {
    activeSyncClient?.broadcastEphemeral();
  }, { signal });
}

function startSync(el: CanopyEditor, handle: number, crdt: CrdtModule, roomId: string) {
  activeSyncClient?.disconnect();

  const syncClient = new SyncClient(el, handle, crdt);
  activeSyncClient = syncClient;

  el.setBroadcast(() => {
    syncClient.broadcast();
  });

  syncClient.connect(undefined, roomId);

  if (!beforeUnloadRegistered) {
    beforeUnloadRegistered = true;
    window.addEventListener('beforeunload', () => {
      // Save document state immediately
      if (_crdt && _handle != null) {
        const currentRoomId = location.hash.slice(1);
        if (currentRoomId) {
          saveNow(_handle, currentRoomId, _crdt);
        }
      }
      // Delete local presence before disconnecting
      if (_crdt && _handle != null) {
        _crdt.ephemeral_delete_presence(_handle);
        // Send final ephemeral update so peers know we left
        activeSyncClient?.broadcastEphemeral();
      }
      if (ephemeralCleanupTimer !== null) {
        clearInterval(ephemeralCleanupTimer);
        ephemeralCleanupTimer = null;
      }
      activeSyncClient?.disconnect();
    });
  }
}

function mountWhenReady(crdt: CrdtModule) {
  const el = document.querySelector('canopy-editor') as CanopyEditor | null;
  if (el) {
    doMount(el, crdt);
    return;
  }
  const observer = new MutationObserver((_mutations, obs) => {
    const found = document.querySelector('canopy-editor') as CanopyEditor | null;
    if (found) {
      obs.disconnect();
      doMount(found, crdt);
    }
  });
  observer.observe(document.body, { childList: true, subtree: true });
}

function doMount(el: CanopyEditor, crdt: CrdtModule) {
  // Reuse the editor MoonBit already created in init_model. Under
  // §P0b Phase 1 the coordinator-allocated EditorId starts at 0, so
  // the first (and only) editor opened by init_model has handle 0.
  // Don't call create_editor_with_undo again — that would overwrite
  // the singleton.
  const handle = 0;
  _handle = handle;
  _crdt = crdt;
  const roomId = getRoomId();
  const bridge = canopyGlobal.__canopy_bridge!;
  bridge.crdt = crdt;
  bridge.crdtHandle = handle;
  bridge.triggerAutosave = triggerAutosave;
  // Inject the file I/O host so the Open/Save toolbar buttons work.
  crdt.register_file_host({
    save: (content, name) => { void saveTextFile(content, name); },
    open: () => { void openTextFile(); },
  });
  let restoredState = false;

  // Restore from localStorage if available
  try {
    const savedState = localStorage.getItem(STORAGE_KEY_PREFIX + roomId);
    if (savedState) {
      try {
        const result = crdt.apply_sync_json(handle, savedState);
        if (result === 'ok') {
          restoredState = true;
        } else {
          console.warn('Failed to restore from localStorage, removing corrupted entry:', result);
          try { localStorage.removeItem(STORAGE_KEY_PREFIX + roomId); } catch { /* storage unavailable */ }
        }
      } catch (e) {
        console.warn('Failed to restore from localStorage, removing corrupted entry:', e);
        try { localStorage.removeItem(STORAGE_KEY_PREFIX + roomId); } catch { /* storage unavailable */ }
      }
    }
  } catch (e) {
    console.warn('localStorage unavailable, skipping restore:', e);
  }

  // Set up agent identity for cursor broadcasting
  const agentId = getSessionAgentId();
  const name = agentDisplayName(agentId);
  const color = agentColor(agentId);
  bridge.onSelectionChanged = (from: number, to: number) => {
    crdt.ephemeral_set_presence_with_selection(handle, name, color, from, to);
    activeSyncClient?.broadcastEphemeral();
  };
  bridge.updateCmPeerCursors = updateCmPeerCursors;
  el.setAgentIdentity(name, color);

  // Announce presence to ephemeral hub
  crdt.ephemeral_set_presence(handle, name, color);

  // Text already set by MoonBit's init_model — don't overwrite.
  el.mount(handle, crdt);
  wireEditorEvents(el);
  if (restoredState) {
    dispatchExternalCrdtChanged(el, { autosave: false });
  }
  if (!SKIP_SYNC) {
    startSync(el, handle, crdt, roomId);
  }

  // Periodically remove outdated ephemeral entries (every 10s)
  if (ephemeralCleanupTimer !== null) {
    clearInterval(ephemeralCleanupTimer);
  }
  ephemeralCleanupTimer = setInterval(() => {
    crdt.ephemeral_remove_outdated(handle);
    updateCmPeerCursors();
  }, 10_000);
}

async function bootstrap() {
  const crdt = await loadCrdtModule();
  mountWhenReady(crdt);
}

void bootstrap();
