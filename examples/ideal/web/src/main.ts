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

type CanopyGlobal = typeof globalThis & {
  __canopy_crdt?: CrdtModule;
  __canopy_crdt_handle?: number;
  __canopy_agent_id?: string;
  __canopy_overlay_open?: boolean;
  __canopy_trigger_autosave?: () => void;
  __canopy_agent_name?: string;
  __canopy_agent_color?: string;
  __canopy_broadcast_ephemeral?: () => void;
  __canopy_codemirror?: Record<string, any>;
  __canopy_create_cm_peer_cursor_extension?: CmExtensionFactory;
  __canopy_create_lambda_cm_extensions?: CmExtensionFactory;
  __canopy_update_cm_peer_cursors?: () => void;
};

const canopyGlobal = globalThis as CanopyGlobal;
const AGENT_ID_STORAGE_KEY = 'canopy-ideal-agent-id';
const STORAGE_KEY_PREFIX = 'canopy-doc-';
const SKIP_SYNC = import.meta.env.VITE_CANOPY_SKIP_SYNC === '1';
let crdtPromise: Promise<CrdtModule> | null = null;
let saveTimer: ReturnType<typeof setTimeout> | null = null;
let activeSyncClient: SyncClient | null = null;
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
    // Set agent ID globally BEFORE importing the MoonBit module.
    // MoonBit's init_model reads this to create the CRDT editor with a unique agent.
    canopyGlobal.__canopy_agent_id = getSessionAgentId();
    canopyGlobal.__canopy_codemirror = { ...cmState, ...cmView, ...cmCommands };
    canopyGlobal.__canopy_create_lambda_cm_extensions = () => [
      lambda(),
      syntaxHighlighting(lambdaHighlightStyle),
    ];
    canopyGlobal.__canopy_create_cm_peer_cursor_extension = peerCursors;
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
  if (canopyGlobal.__canopy_crdt && canopyGlobal.__canopy_crdt_handle != null) {
    const roomId = location.hash.slice(1);
    if (roomId) {
      saveToLocalStorage(
        canopyGlobal.__canopy_crdt_handle,
        roomId,
        canopyGlobal.__canopy_crdt,
      );
    }
  }
}

function updateCmPeerCursors() {
  if (!canopyGlobal.__canopy_crdt || canopyGlobal.__canopy_crdt_handle == null) return;
  const json = canopyGlobal.__canopy_crdt.ephemeral_get_peer_cursors_json(
    canopyGlobal.__canopy_crdt_handle,
  );
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
    if (!canopyGlobal.__canopy_crdt || canopyGlobal.__canopy_crdt_handle == null) return;
    const crdt = canopyGlobal.__canopy_crdt;
    const handle = canopyGlobal.__canopy_crdt_handle;

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
    if (!canopyGlobal.__canopy_crdt || canopyGlobal.__canopy_crdt_handle == null) return;
    const crdt = canopyGlobal.__canopy_crdt;
    const handle = canopyGlobal.__canopy_crdt_handle;
    const didUndo = crdt.handle_undo(handle);
    if (didUndo) {
      el.syncAfterExternalChange();
      el.notifyLocalChange();
      dispatchExternalCrdtChanged(el);
    }
  }, { signal });
  el.addEventListener(CanopyEvents.REQUEST_REDO, () => {
    if (!canopyGlobal.__canopy_crdt || canopyGlobal.__canopy_crdt_handle == null) return;
    const crdt = canopyGlobal.__canopy_crdt;
    const handle = canopyGlobal.__canopy_crdt_handle;
    const didRedo = crdt.handle_redo(handle);
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
      if (canopyGlobal.__canopy_crdt && canopyGlobal.__canopy_crdt_handle != null) {
        const currentRoomId = location.hash.slice(1);
        if (currentRoomId) {
          saveNow(canopyGlobal.__canopy_crdt_handle, currentRoomId, canopyGlobal.__canopy_crdt);
        }
      }
      // Delete local presence before disconnecting
      if (canopyGlobal.__canopy_crdt && canopyGlobal.__canopy_crdt_handle != null) {
        canopyGlobal.__canopy_crdt.ephemeral_delete_presence(canopyGlobal.__canopy_crdt_handle);
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
  // Reuse the editor MoonBit already created in init_model (handle = 1).
  // Don't call create_editor_with_undo again — that would overwrite the singleton.
  const handle = 1;
  const roomId = getRoomId();
  canopyGlobal.__canopy_crdt_handle = handle;
  canopyGlobal.__canopy_trigger_autosave = triggerAutosave;
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
  canopyGlobal.__canopy_agent_name = name;
  canopyGlobal.__canopy_agent_color = color;
  canopyGlobal.__canopy_broadcast_ephemeral = () => activeSyncClient?.broadcastEphemeral();
  canopyGlobal.__canopy_update_cm_peer_cursors = updateCmPeerCursors;
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
  canopyGlobal.__canopy_crdt = crdt;
  mountWhenReady(crdt);
}

void bootstrap();
