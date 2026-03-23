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
//   Client -> Server: { type: "resync" }                 (request full history replay)
//   Client -> Server: { type: "ping" }                   (keepalive)
//   Server -> Client: { type: "sync", ops: string[] }    (history for late joiners)
//   Server -> Client: { type: "operation", op: string }   (relayed from another peer)
//   Server -> Client: { type: "pong" }                   (keepalive reply)

import type { CrdtModule } from "./types";

// Relay server URL: set VITE_RELAY_URL for Cloudflare deployment,
// falls back to local dev server.
const DEFAULT_WS_URL =
  (typeof import.meta !== "undefined" &&
    (import.meta as Record<string, Record<string, string>>).env
      ?.VITE_RELAY_URL) ||
  "ws://localhost:8787";
const DEFAULT_ROOM = "canopy-room";

/** Reconnection parameters. */
const RECONNECT_DELAY_MS = 2_000;
const MAX_RECONNECT_DELAY_MS = 30_000;

/** Heartbeat parameters. */
const HEARTBEAT_INTERVAL_MS = 30_000;
const HEARTBEAT_TIMEOUT_MS = 5_000;

/** Offline queue cap — beyond this, fall back to full state on reconnect. */
const MAX_PENDING_OPS = 1_000;

export class SyncClient {
  private ws: WebSocket | null = null;
  private host: HTMLElement;
  private handle: number;
  private crdt: CrdtModule;
  private disposed = false;
  private reconnectDelay = RECONNECT_DELAY_MS;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private lastSentVersion: string;
  private url: string = DEFAULT_WS_URL;
  private room: string = DEFAULT_ROOM;

  /** Queued deltas accumulated while disconnected. */
  private pendingOps: string[] = [];

  /** Heartbeat state. */
  private heartbeatInterval: ReturnType<typeof setInterval> | null = null;
  private heartbeatTimeout: ReturnType<typeof setTimeout> | null = null;

  /** Abort controller for host event listeners. */
  private hostAbort: AbortController | null = null;

  /** Resync cooldown timestamp. */
  private lastResyncTime = 0;

  constructor(host: HTMLElement, handle: number, crdt: CrdtModule) {
    this.host = host;
    this.handle = handle;
    this.crdt = crdt;
    this.lastSentVersion = crdt.get_version_json(handle);
  }

  connect(
    url: string = DEFAULT_WS_URL,
    room: string = DEFAULT_ROOM,
  ): void {
    this.url = url;
    this.room = room;
    if (this.disposed) return;
    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      return;
    }
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    // Listen for sync-error events to trigger resync
    this.hostAbort?.abort();
    this.hostAbort = new AbortController();
    this.host.addEventListener('sync-error', () => {
      this.requestResync();
    }, { signal: this.hostAbort.signal });

    const wsUrl = url.includes("localhost")
      ? url
      : `${url.replace(/\/$/, "")}/room/${encodeURIComponent(room)}`;
    this.ws = new WebSocket(wsUrl);
    this.host.dispatchEvent(
      new CustomEvent("sync-status", {
        detail: { status: "connecting" },
        bubbles: true,
        composed: true,
      }),
    );

    this.ws.addEventListener("open", () => {
      this.reconnectDelay = RECONNECT_DELAY_MS;

      this.ws!.send(JSON.stringify({ type: "join", room }));

      // Flush any ops queued while offline, or send full state.
      if (this.pendingOps.length > 0 && this.pendingOps.length <= MAX_PENDING_OPS) {
        for (const op of this.pendingOps) {
          this.ws!.send(JSON.stringify({ type: "operation", op }));
        }
        this.pendingOps = [];
        // Pending ops cover the delta — no need for full state.
      } else {
        this.pendingOps = [];
        // No queued ops (or too many) — send full state for peers to merge.
        const fullState = this.crdt.export_all_json(this.handle);
        this.ws!.send(JSON.stringify({ type: "operation", op: fullState }));
      }
      this.lastSentVersion = this.crdt.get_version_json(this.handle);

      this.host.dispatchEvent(
        new CustomEvent("sync-status", {
          detail: { status: "connected" },
          bubbles: true,
          composed: true,
        }),
      );

      this.broadcastEphemeral();
      this.startHeartbeat();
    });

    this.ws.addEventListener("message", (event) => {
      try {
        const data = JSON.parse(event.data as string);

        switch (data.type) {
          case "operation": {
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
            this.lastSentVersion = this.crdt.get_version_json(this.handle);
            break;
          }

          case "sync": {
            const ops: unknown[] = Array.isArray(data.ops) ? data.ops : [];
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

          case "pong":
            if (this.heartbeatTimeout !== null) {
              clearTimeout(this.heartbeatTimeout);
              this.heartbeatTimeout = null;
            }
            break;

          case "error":
            console.warn("[sync] server error:", data.message);
            break;

          case "ephemeral": {
            const bytes = new Uint8Array(data.data as number[]);
            this.crdt.ephemeral_apply(this.handle, bytes);
            this.host.dispatchEvent(
              new CustomEvent("sync-cursors-updated", {
                bubbles: true,
                composed: true,
              }),
            );
            break;
          }

          default:
            console.warn("[sync] unknown message type:", data.type);
        }
      } catch (err) {
        console.error("[sync] failed to process message:", err);
      }
    });

    this.ws.addEventListener("close", () => {
      this.ws = null;
      this.stopHeartbeat();
      if (!this.disposed) {
        this.host.dispatchEvent(
          new CustomEvent("sync-status", {
            detail: { status: "disconnected" },
            bubbles: true,
            composed: true,
          }),
        );
        this.scheduleReconnect();
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
    });
  }

  broadcast(): void {
    try {
      const delta = this.crdt.export_since_json(
        this.handle,
        this.lastSentVersion,
      );
      if (!delta) return;
      const parsed = JSON.parse(delta);
      const hasOps = Array.isArray(parsed.ops) && parsed.ops.length > 0;
      if (!hasOps) return;

      if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
        if (this.pendingOps.length < MAX_PENDING_OPS) {
          this.pendingOps.push(delta);
        }
        this.lastSentVersion = this.crdt.get_version_json(this.handle);
        this.host.dispatchEvent(
          new CustomEvent("sync-status", {
            detail: { status: "buffering", pending: this.pendingOps.length },
            bubbles: true,
            composed: true,
          }),
        );
        return;
      }

      this.ws.send(JSON.stringify({ type: "operation", op: delta }));
      this.lastSentVersion = this.crdt.get_version_json(this.handle);
    } catch (err) {
      console.error("[sync] broadcast failed:", err);
    }
  }

  broadcastEphemeral(): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    try {
      const bytes = this.crdt.ephemeral_encode_all(this.handle);
      if (!bytes || bytes.length === 0) return;
      this.ws.send(
        JSON.stringify({ type: "ephemeral", data: Array.from(bytes) }),
      );
    } catch (err) {
      console.error("[sync] ephemeral broadcast failed:", err);
    }
  }

  requestResync(): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
    const now = Date.now();
    if (now - this.lastResyncTime < 10_000) return; // 10s cooldown
    this.lastResyncTime = now;
    console.info("[sync] requesting resync from server");
    this.ws.send(JSON.stringify({ type: "resync" }));
  }

  disconnect(): void {
    this.disposed = true;
    this.stopHeartbeat();
    this.hostAbort?.abort();
    this.hostAbort = null;
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatInterval = setInterval(() => {
      if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
      this.ws.send(JSON.stringify({ type: "ping" }));
      this.heartbeatTimeout = setTimeout(() => {
        console.warn("[sync] heartbeat timeout, reconnecting");
        this.ws?.close();
      }, HEARTBEAT_TIMEOUT_MS);
    }, HEARTBEAT_INTERVAL_MS);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatInterval !== null) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }
    if (this.heartbeatTimeout !== null) {
      clearTimeout(this.heartbeatTimeout);
      this.heartbeatTimeout = null;
    }
  }

  private scheduleReconnect(): void {
    if (this.disposed || this.reconnectTimer !== null) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.reconnectDelay = Math.min(
        this.reconnectDelay * 1.5,
        MAX_RECONNECT_DELAY_MS,
      );
      this.connect(this.url, this.room);
    }, this.reconnectDelay);
  }
}
