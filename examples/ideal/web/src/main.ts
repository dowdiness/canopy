import './canopy-editor';
import type { CanopyEditor } from './canopy-editor';
import { CanopyEvents } from './events';
import { SyncClient } from './sync';
import type { CrdtModule } from './types';

type NodeSelectedDetail = {
  nodeId?: string;
};

type StructuralEditDetail = {
  op?: string;
  nodeId?: string;
};

type CanopyGlobal = typeof globalThis & {
  __canopy_crdt?: CrdtModule;
  __canopy_crdt_handle?: number;
  __canopy_agent_id?: string;
  __canopy_pending_node_selection?: string | null;
  __canopy_pending_structural_edit?: StructuralEditDetail | null;
  __canopy_pending_sync_status?: string | null;
};

const canopyGlobal = globalThis as CanopyGlobal;
const AGENT_ID_STORAGE_KEY = 'canopy-ideal-agent-id';
let crdtPromise: Promise<CrdtModule> | null = null;
let activeSyncClient: SyncClient | null = null;
let editorEventsController: AbortController | null = null;
let beforeUnloadRegistered = false;

function loadCrdtModule(): Promise<CrdtModule> {
  if (!crdtPromise) {
    // Set agent ID globally BEFORE importing the MoonBit module.
    // MoonBit's init_model reads this to create the CRDT editor with a unique agent.
    canopyGlobal.__canopy_agent_id = getSessionAgentId();
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

function clickTrigger(id: string) {
  const btn = document.getElementById(id) as HTMLButtonElement | null;
  if (btn) btn.click();
}

function wireEditorEvents(el: CanopyEditor) {
  // Abort previous listeners if called again (prevents accumulation)
  if (editorEventsController) editorEventsController.abort();
  editorEventsController = new AbortController();
  const { signal } = editorEventsController;

  el.addEventListener(CanopyEvents.TEXT_CHANGE, () => {
    clickTrigger('canopy-text-sync-trigger');
  }, { signal });
  el.addEventListener(CanopyEvents.NODE_SELECTED, ((event: Event) => {
    const { nodeId } = (event as CustomEvent<NodeSelectedDetail>).detail ?? {};
    canopyGlobal.__canopy_pending_node_selection = nodeId ?? null;
    clickTrigger('canopy-node-selected-trigger');
  }) as EventListener, { signal });
  el.addEventListener(CanopyEvents.STRUCTURAL_EDIT_REQUEST, ((event: Event) => {
    const { op, nodeId } = (event as CustomEvent<StructuralEditDetail>).detail ?? {};
    canopyGlobal.__canopy_pending_structural_edit =
      op && nodeId ? { op, nodeId } : null;
    clickTrigger('canopy-structural-edit-trigger');
  }) as EventListener, { signal });
  el.addEventListener(CanopyEvents.REQUEST_UNDO, () => {
    clickTrigger('canopy-undo-trigger');
  }, { signal });
  el.addEventListener(CanopyEvents.REQUEST_REDO, () => {
    clickTrigger('canopy-redo-trigger');
  }, { signal });
  el.addEventListener('sync-status', ((event: Event) => {
    const { status } = (event as CustomEvent<{ status: string }>).detail ?? {};
    if (status) {
      canopyGlobal.__canopy_pending_sync_status = status;
      clickTrigger('canopy-sync-status-trigger');
    }
  }) as EventListener, { signal });
}

function startSync(el: CanopyEditor, handle: number, crdt: CrdtModule) {
  activeSyncClient?.disconnect();

  const syncClient = new SyncClient(el, handle, crdt);
  activeSyncClient = syncClient;

  el.setBroadcast(() => {
    syncClient.broadcast();
  });

  syncClient.connect();

  if (!beforeUnloadRegistered) {
    beforeUnloadRegistered = true;
    window.addEventListener('beforeunload', () => {
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
  canopyGlobal.__canopy_crdt_handle = handle;
  canopyGlobal.__canopy_pending_node_selection = null;
  canopyGlobal.__canopy_pending_structural_edit = null;
  // Text already set by MoonBit's init_model — don't overwrite.
  el.mount(handle, crdt);
  wireEditorEvents(el);
  startSync(el, handle, crdt);
}

async function bootstrap() {
  const crdt = await loadCrdtModule();
  canopyGlobal.__canopy_crdt = crdt;
  mountWhenReady(crdt);
}

void bootstrap();
