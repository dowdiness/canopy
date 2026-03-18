// WebSocket sync for collaborative editing.
//
// Connects to a relay server and exchanges CRDT deltas with peers.
// On open:    send full state via export_all_json so peers can catch up.
// On message: apply_sync_json, then bridge.reconcile() to update the editor.
// Returns a broadcast function that the bridge calls after local edits.
//
// Protocol (matches examples/demo-react/server/ws-server.ts):
//   Client -> Server: { type: "join", room: string }
//   Client -> Server: { type: "operation", op: string }  (op is CRDT sync JSON)
//   Server -> Client: { type: "sync", ops: string[] }    (history replay for late joiners)
//   Server -> Client: { type: "operation", op: string }   (relayed from another client)

import type { CrdtBridge, CrdtModule } from "./bridge";

const WS_URL = "ws://localhost:8787";
const ROOM_ID = "prosemirror-room";

/** Reconnection parameters. */
const RECONNECT_DELAY_MS = 2000;
const MAX_RECONNECT_DELAY_MS = 30000;

export interface SyncHandle {
  /** Broadcast local CRDT changes to all connected peers. */
  broadcast: () => void;
  /** Disconnect from the sync server. */
  disconnect: () => void;
}

/**
 * Set up WebSocket sync for collaborative editing.
 *
 * @param handle  - CRDT editor handle (from crdt.create_editor)
 * @param crdt    - MoonBit CRDT FFI module
 * @param bridge  - CrdtBridge instance for applying remote changes
 * @param agentId - Unique agent identifier for this peer
 * @returns SyncHandle with broadcast() and disconnect() functions
 */
export function setupSync(
  handle: number,
  crdt: CrdtModule,
  bridge: CrdtBridge,
  agentId: string,
): SyncHandle {
  let ws: WebSocket | null = null;
  let reconnectDelay = RECONNECT_DELAY_MS;
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  let disposed = false;

  // Track the version we last sent so we can export deltas.
  let lastSentVersion: string = crdt.get_version_json(handle);

  const statusEl = document.getElementById("status");

  function setStatus(text: string, cls: "connected" | "disconnected" | "error") {
    if (statusEl) {
      statusEl.textContent = text;
      statusEl.className = `status ${cls}`;
    }
  }

  function connect() {
    if (disposed) return;

    setStatus("Connecting...", "disconnected");
    ws = new WebSocket(WS_URL);

    ws.addEventListener("open", () => {
      reconnectDelay = RECONNECT_DELAY_MS;
      setStatus(`Connected as ${agentId}`, "connected");

      // Join the room.
      ws!.send(JSON.stringify({ type: "join", room: ROOM_ID }));

      // Send full state so any peers already in the room can merge.
      const fullState = crdt.export_all_json(handle);
      ws!.send(JSON.stringify({ type: "operation", op: fullState }));

      // Update the sent-version watermark.
      lastSentVersion = crdt.get_version_json(handle);
    });

    ws.addEventListener("message", (event) => {
      try {
        const data = JSON.parse(event.data as string);

        switch (data.type) {
          case "operation": {
            // Single relayed operation from another peer.
            const syncJson = typeof data.op === "string" ? data.op : JSON.stringify(data.op);
            bridge.applyRemote(syncJson);
            // After applying remote ops our version has advanced, so update the watermark.
            lastSentVersion = crdt.get_version_json(handle);
            break;
          }

          case "sync": {
            // History replay — array of ops for late joiners.
            const ops: unknown[] = Array.isArray(data.ops) ? data.ops : [];
            for (const op of ops) {
              const syncJson = typeof op === "string" ? op : JSON.stringify(op);
              bridge.applyRemote(syncJson);
            }
            lastSentVersion = crdt.get_version_json(handle);
            break;
          }

          case "peer_joined":
          case "peer_left":
          case "peer_list":
            // Informational — ignore for now.
            break;

          case "error":
            console.warn("[sync] server error:", data.message);
            break;

          default:
            console.warn("[sync] unknown message type:", data.type);
        }
      } catch (err) {
        console.error("[sync] failed to process message:", err);
      }
    });

    ws.addEventListener("close", () => {
      ws = null;
      if (!disposed) {
        setStatus("Disconnected — reconnecting...", "disconnected");
        scheduleReconnect();
      }
    });

    ws.addEventListener("error", (err) => {
      console.error("[sync] WebSocket error:", err);
      setStatus("Connection error", "error");
      // The close event will fire after this, triggering reconnect.
    });
  }

  function scheduleReconnect() {
    if (disposed || reconnectTimer !== null) return;
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      reconnectDelay = Math.min(reconnectDelay * 1.5, MAX_RECONNECT_DELAY_MS);
      connect();
    }, reconnectDelay);
  }

  /**
   * Broadcast local changes to peers.
   * Called by the bridge after every local edit.
   */
  function broadcast(): void {
    if (!ws || ws.readyState !== WebSocket.OPEN) return;

    try {
      const delta = crdt.export_since_json(handle, lastSentVersion);
      if (!delta) return;
      // Parse to check for actual operations instead of fragile string comparison
      const parsed = JSON.parse(delta);
      const hasOps = Array.isArray(parsed.ops) && parsed.ops.length > 0;
      if (hasOps) {
        ws.send(JSON.stringify({ type: "operation", op: delta }));
        lastSentVersion = crdt.get_version_json(handle);
      }
    } catch (err) {
      console.error("[sync] broadcast failed:", err);
    }
  }

  function disconnect(): void {
    disposed = true;
    if (reconnectTimer !== null) {
      clearTimeout(reconnectTimer);
      reconnectTimer = null;
    }
    if (ws) {
      ws.close();
      ws = null;
    }
    setStatus("Disconnected", "disconnected");
  }

  // Start the connection.
  connect();

  return { broadcast, disconnect };
}
