/**
 * Cloudflare Worker — CRDT Operation Relay Server
 *
 * Room-based WebSocket relay that broadcasts CRDT operations between peers.
 * Each room is a Durable Object instance with in-memory operation history
 * for late-joiner replay.
 *
 * Protocol (matches sync.ts SyncClient):
 *   Client → Server: { type: "join", room: string }
 *   Client → Server: { type: "operation", op: string }   (CRDT sync JSON)
 *   Server → Client: { type: "sync", ops: string[] }     (history for late joiners)
 *   Server → Client: { type: "operation", op: string }   (relayed from another peer)
 *   Server → Client: { type: "error", message: string }
 */

const MAX_OPS = 10_000;

/**
 * Durable Object that manages a single relay room.
 */
export class RelayRoom {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.clients = new Set();
    this.ops = [];
  }

  async fetch(request) {
    const upgradeHeader = request.headers.get("Upgrade");
    if (!upgradeHeader || upgradeHeader !== "websocket") {
      return new Response("Expected WebSocket upgrade", { status: 426 });
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.handleSession(server);

    return new Response(null, { status: 101, webSocket: client });
  }

  handleSession(ws) {
    ws.accept();
    let joined = false;

    ws.addEventListener("message", (event) => {
      try {
        const msg = JSON.parse(event.data);

        switch (msg.type) {
          case "join": {
            if (joined) break;
            joined = true;
            this.clients.add(ws);

            // Replay stored ops to the newly joined client
            if (this.ops.length > 0) {
              ws.send(JSON.stringify({ type: "sync", ops: this.ops }));
            }
            break;
          }

          case "operation": {
            if (!joined) {
              ws.send(JSON.stringify({ type: "error", message: "Not joined" }));
              break;
            }

            const op = msg.op;

            // Store for late-joiner replay
            this.ops.push(op);
            if (this.ops.length > MAX_OPS) {
              this.ops.shift();
            }

            // Broadcast to all other clients
            const relay = JSON.stringify({ type: "operation", op });
            for (const peer of this.clients) {
              if (peer !== ws) {
                try {
                  peer.send(relay);
                } catch {
                  this.clients.delete(peer);
                }
              }
            }
            break;
          }

          case "ephemeral": {
            // Broadcast ephemeral data to all other peers (no history storage)
            if (!joined) {
              ws.send(JSON.stringify({ type: "error", message: "Not joined" }));
              break;
            }
            const relay = JSON.stringify({ type: "ephemeral", data: msg.data });
            for (const peer of this.clients) {
              if (peer !== ws) {
                try {
                  peer.send(relay);
                } catch {
                  this.clients.delete(peer);
                }
              }
            }
            break;
          }

          case "reset": {
            this.ops = [];
            break;
          }

          default:
            ws.send(
              JSON.stringify({
                type: "error",
                message: `Unknown message type: ${msg.type}`,
              })
            );
        }
      } catch (err) {
        ws.send(
          JSON.stringify({
            type: "error",
            message: `Invalid message: ${err.message}`,
          })
        );
      }
    });

    ws.addEventListener("close", () => {
      this.clients.delete(ws);
    });

    ws.addEventListener("error", () => {
      this.clients.delete(ws);
    });
  }
}

/**
 * Worker entry point — routes requests to room Durable Objects.
 */
export default {
  async fetch(request, env) {
    // CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Upgrade, Connection",
        },
      });
    }

    // Extract room name from URL path: /room/<name> or default
    const url = new URL(request.url);
    const pathParts = url.pathname.split("/").filter(Boolean);
    const roomName =
      pathParts.length >= 2 && pathParts[0] === "room"
        ? pathParts[1]
        : "default";

    const id = env.RELAY_ROOM.idFromName(roomName);
    const stub = env.RELAY_ROOM.get(id);
    return stub.fetch(request);
  },
};
