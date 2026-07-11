// WebSocket glue — irreducible event wiring for binary CRDT sync.
// All sync logic lives in MoonBit (editor/sync_editor_ws.mbt).

/** Subset of the MoonBit FFI module needed for WebSocket sync. */
interface WsCrdtModule {
  ws_on_open(handle: number, ws: WebSocket): void;
  ws_on_message(handle: number, data: Uint8Array): void;
  ws_on_close(handle: number): void;
  ws_broadcast_edit(handle: number): void;
  ws_broadcast_cursor(handle: number): void;
  [key: string]: any;
}

const RECONNECT_DELAY_MS = 2000;
const MAX_RECONNECT_DELAY_MS = 30000;

export function connectWebSocket(
  handle: number,
  crdt: WsCrdtModule,
  url: string,
  onRemoteSync: () => void,
): { disconnect: () => void; broadcastEdit: () => void } {
  let ws: WebSocket | null = null;
  let reconnectDelay = RECONNECT_DELAY_MS;
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  let disposed = false;

  const statusEl = document.getElementById("status");

  function setStatus(text: string, cls: string) {
    if (statusEl) {
      statusEl.textContent = text;
      statusEl.className = `status ${cls}`;
    }
  }

  function connect() {
    if (disposed) return;
    setStatus("Connecting...", "disconnected");
    ws = new WebSocket(url);
    ws.binaryType = "arraybuffer";

    ws.onopen = () => {
      reconnectDelay = RECONNECT_DELAY_MS;
      setStatus("Connected", "connected");
      crdt.ws_on_open(handle, ws!);
    };

    ws.onmessage = (e) => {
      const data = e.data instanceof ArrayBuffer
        ? new Uint8Array(e.data)
        : new TextEncoder().encode(e.data as string);
      crdt.ws_on_message(handle, data);
      // After remote ops, reconcile the editor view
      onRemoteSync();
    };

    ws.onclose = () => {
      ws = null;
      crdt.ws_on_close(handle);
      if (!disposed) {
        setStatus("Disconnected — reconnecting...", "disconnected");
        scheduleReconnect();
      }
    };

    ws.onerror = () => {
      setStatus("Connection error", "error");
    };
  }

  function scheduleReconnect() {
    if (disposed || reconnectTimer !== null) return;
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      reconnectDelay = Math.min(reconnectDelay * 1.5, MAX_RECONNECT_DELAY_MS);
      connect();
    }, reconnectDelay);
  }

  function disconnect() {
    disposed = true;
    if (reconnectTimer !== null) {
      clearTimeout(reconnectTimer);
      reconnectTimer = null;
    }
    if (ws) {
      ws.close();
      ws = null;
    }
    crdt.ws_on_close(handle);
    setStatus("Disconnected", "disconnected");
  }

  function broadcastEdit() {
    crdt.ws_broadcast_edit(handle);
  }

  connect();
  return { disconnect, broadcastEdit };
}
