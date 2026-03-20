// WebSocket sync client for collaborative editing.
//
// Connects to a relay server and exchanges CRDT deltas with peers.
// On open:    send full state via export_all_json so peers can catch up.
// On message: dispatch a CustomEvent on the host element so the Web Component
//             can call bridge.applyRemote().
//
// Protocol (matches server/ws-server.ts):
//   Client -> Server: { type: "join", room: string }
//   Client -> Server: { type: "operation", op: string }  (CRDT sync JSON)
//   Server -> Client: { type: "sync", ops: string[] }    (history for late joiners)
//   Server -> Client: { type: "operation", op: string }   (relayed from another peer)

import type { CrdtModule } from "./types";

const DEFAULT_WS_URL = "ws://localhost:8787";
const DEFAULT_ROOM = "canopy-room";

/** Reconnection parameters. */
const RECONNECT_DELAY_MS = 2_000;
const MAX_RECONNECT_DELAY_MS = 30_000;

export class SyncClient {
  private ws: WebSocket | null = null;
  private host: HTMLElement;
  private handle: number;
  private crdt: CrdtModule;
  private disposed = false;
  private reconnectDelay = RECONNECT_DELAY_MS;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private lastSentVersion: string;

  constructor(host: HTMLElement, handle: number, crdt: CrdtModule) {
    this.host = host;
    this.handle = handle;
    this.crdt = crdt;
    this.lastSentVersion = crdt.get_version_json(handle);
  }

  /**
   * Connect to the relay server and join a room.
   *
   * @param url  - WebSocket server URL (default: ws://localhost:8787)
   * @param room - Room name to join (default: "canopy-room")
   */
  connect(
    url: string = DEFAULT_WS_URL,
    room: string = DEFAULT_ROOM,
  ): void {
    if (this.disposed) return;
    // Guard against duplicate connections
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }
    // Clear any pending reconnect timer
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    this.ws = new WebSocket(url);

    this.ws.addEventListener("open", () => {
      this.reconnectDelay = RECONNECT_DELAY_MS;

      // Join the room.
      this.ws!.send(JSON.stringify({ type: "join", room }));

      // Send full state so any peers already in the room can merge.
      const fullState = this.crdt.export_all_json(this.handle);
      this.ws!.send(JSON.stringify({ type: "operation", op: fullState }));

      // Update the sent-version watermark.
      this.lastSentVersion = this.crdt.get_version_json(this.handle);

      this.host.dispatchEvent(
        new CustomEvent("sync-status", {
          detail: { status: "connected" },
          bubbles: true,
          composed: true,
        }),
      );
    });

    this.ws.addEventListener("message", (event) => {
      try {
        const data = JSON.parse(event.data as string);

        switch (data.type) {
          case "operation": {
            // Single relayed operation from another peer.
            const syncJson =
              typeof data.op === "string"
                ? data.op
                : JSON.stringify(data.op);
            this.host.dispatchEvent(
              new CustomEvent("sync-received", {
                detail: { data: syncJson },
                bubbles: true,
                composed: true,
              }),
            );
            // After applying remote ops our version has advanced.
            this.lastSentVersion = this.crdt.get_version_json(this.handle);
            break;
          }

          case "sync": {
            // History replay -- array of ops for late joiners.
            const ops: unknown[] = Array.isArray(data.ops)
              ? data.ops
              : [];
            for (const op of ops) {
              const syncJson =
                typeof op === "string" ? op : JSON.stringify(op);
              this.host.dispatchEvent(
                new CustomEvent("sync-received", {
                  detail: { data: syncJson },
                  bubbles: true,
                  composed: true,
                }),
              );
            }
            this.lastSentVersion = this.crdt.get_version_json(this.handle);
            break;
          }

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

    this.ws.addEventListener("close", () => {
      this.ws = null;
      if (!this.disposed) {
        this.host.dispatchEvent(
          new CustomEvent("sync-status", {
            detail: { status: "disconnected" },
            bubbles: true,
            composed: true,
          }),
        );
        this.scheduleReconnect(url, room);
      }
    });

    this.ws.addEventListener("error", (err) => {
      console.error("[sync] WebSocket error:", err);
      this.host.dispatchEvent(
        new CustomEvent("sync-status", {
          detail: { status: "error" },
          bubbles: true,
          composed: true,
        }),
      );
      // The close event will fire after this, triggering reconnect.
    });
  }

  /**
   * Broadcast local CRDT changes to all connected peers.
   * Called by the bridge after every local edit.
   */
  broadcast(): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;

    try {
      const delta = this.crdt.export_since_json(
        this.handle,
        this.lastSentVersion,
      );
      if (!delta) return;
      // Parse to check for actual operations
      const parsed = JSON.parse(delta);
      const hasOps = Array.isArray(parsed.ops) && parsed.ops.length > 0;
      if (hasOps) {
        this.ws.send(JSON.stringify({ type: "operation", op: delta }));
        this.lastSentVersion = this.crdt.get_version_json(this.handle);
      }
    } catch (err) {
      console.error("[sync] broadcast failed:", err);
    }
  }

  /** Disconnect and stop reconnecting. */
  disconnect(): void {
    this.disposed = true;
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  private scheduleReconnect(url: string, room: string): void {
    if (this.disposed || this.reconnectTimer !== null) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.reconnectDelay = Math.min(
        this.reconnectDelay * 1.5,
        MAX_RECONNECT_DELAY_MS,
      );
      this.connect(url, room);
    }, this.reconnectDelay);
  }
}
