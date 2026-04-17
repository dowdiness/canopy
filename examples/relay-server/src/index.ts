// Cloudflare Worker + Durable Object relay server.
// All sync logic lives in MoonBit (relay/ package).
// This file is only the irreducible WebSocket event glue.
//
// The MoonBit module is lazy-loaded inside the DO constructor because
// CF Workers disallow async I/O (including Math.random) at global scope.

export interface Env {
  RELAY: DurableObjectNamespace;
}

// Lazy-loaded MoonBit module (deferred to handler scope)
let relay: any = null;
async function loadRelay() {
  if (relay) return relay;
  relay = await import("../../../_build/js/release/build/ffi/ffi.js");
  return relay;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const room = url.searchParams.get("room") ?? "main";
    const id = env.RELAY.idFromName(room);
    return env.RELAY.get(id).fetch(request);
  },
};

export class RelayRoom implements DurableObject {
  private roomId: string;

  constructor(state: DurableObjectState) {
    this.roomId = state.id.toString();
    // Lazy-load MoonBit module inside DO constructor (handler scope)
    state.blockConcurrencyWhile(async () => {
      await loadRelay();
    });
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Expected WebSocket", { status: 426 });
    }

    const url = new URL(request.url);
    const peerId = url.searchParams.get("peer_id") ?? crypto.randomUUID();
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];
    server.accept();

    // Pass a send callback to MoonBit — relay manages sessions + broadcast.
    // relay_on_connect returns false if the peer_id is empty or already in
    // the room; close the duplicate transport rather than leaving a zombie.
    const accepted = relay.relay_on_connect(
      this.roomId,
      peerId,
      (data: Uint8Array) => {
        if (server.readyState === WebSocket.OPEN) {
          server.send(data);
        }
      },
    );
    if (!accepted) {
      // 4000–4999 are application-defined WebSocket close codes.
      server.close(4001, "duplicate or invalid peer_id");
      return new Response(null, { status: 101, webSocket: client });
    }

    server.addEventListener("message", (e) => {
      const data = e.data instanceof ArrayBuffer
        ? new Uint8Array(e.data)
        : new TextEncoder().encode(e.data as string);
      relay.relay_on_message(this.roomId, peerId, data);
    });

    server.addEventListener("close", () => {
      relay.relay_on_disconnect(this.roomId, peerId);
    });

    server.addEventListener("error", () => {
      relay.relay_on_disconnect(this.roomId, peerId);
    });

    return new Response(null, { status: 101, webSocket: client });
  }
}
