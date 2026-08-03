/**
 * Cloudflare Worker — CRDT Operation Relay Server
 *
 * Room-based WebSocket relay that broadcasts CRDT operations between peers.
 * Each room is a Durable Object instance with SQLite-backed persistent
 * operation storage for late-joiner replay.
 *
 * Protocol (matches sync.ts SyncClient):
 *   Client -> Server: { type: "join"|"operation"|"resync"|"ping"|"ephemeral"|"reset" }
 *   Server -> Client: { type: "sync"|"operation"|"pong"|"ephemeral"|"error" }
 */

export class RelayRoom {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.clients = new Set();
    this.state.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS operations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        data TEXT NOT NULL
      )
    `);
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

  /** Replay stored ops from SQLite. */
  _getOps() {
    const cursor = this.state.storage.sql.exec(
      "SELECT data FROM operations ORDER BY id"
    );
    const ops = [];
    for (const row of cursor) ops.push(row.data);
    return ops;
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
            const ops = this._getOps();
            if (ops.length > 0) ws.send(JSON.stringify({ type: "sync", ops }));
            break;
          }

          case "operation": {
            if (!joined) { ws.send(JSON.stringify({ type: "error", message: "Not joined" })); break; }
            const op = msg.op;
            this.state.storage.sql.exec("INSERT INTO operations (data) VALUES (?)", op);
            const MAX_OPS = 10_000;
            const countCursor = this.state.storage.sql.exec("SELECT COUNT(*) as cnt FROM operations");
            for (const row of countCursor) {
              if (row.cnt > MAX_OPS) {
                this.state.storage.sql.exec(
                  "DELETE FROM operations WHERE id <= (SELECT id FROM operations ORDER BY id LIMIT 1)"
                );
              }
            }
            const relay = JSON.stringify({ type: "operation", op });
            for (const peer of this.clients) {
              if (peer !== ws) { try { peer.send(relay); } catch { this.clients.delete(peer); } }
            }
            break;
          }

          case "resync": {
            if (!joined) { ws.send(JSON.stringify({ type: "error", message: "Not joined" })); break; }
            const ops = this._getOps();
            if (ops.length > 0) ws.send(JSON.stringify({ type: "sync", ops }));
            break;
          }

          case "ping":
            ws.send(JSON.stringify({ type: "pong" }));
            break;

          case "ephemeral": {
            if (!joined) { ws.send(JSON.stringify({ type: "error", message: "Not joined" })); break; }
            const relay = JSON.stringify({ type: "ephemeral", data: msg.data });
            for (const peer of this.clients) {
              if (peer !== ws) { try { peer.send(relay); } catch { this.clients.delete(peer); } }
            }
            break;
          }

          case "reset": {
            if (!joined) { ws.send(JSON.stringify({ type: "error", message: "Not joined" })); break; }
            this.state.storage.sql.exec("DELETE FROM operations");
            break;
          }

          default:
            ws.send(JSON.stringify({ type: "error", message: `Unknown message type: ${msg.type}` }));
        }
      } catch (err) {
        ws.send(JSON.stringify({ type: "error", message: `Invalid message: ${err.message}` }));
      }
    });

    ws.addEventListener("close", () => this.clients.delete(ws));
    ws.addEventListener("error", () => this.clients.delete(ws));
  }
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Upgrade, Connection",
        },
      });
    }
    const url = new URL(request.url);
    const pathParts = url.pathname.split("/").filter(Boolean);
    const roomName =
      pathParts.length >= 2 && pathParts[0] === "room" ? pathParts[1] : "default";
    const id = env.RELAY_ROOM.idFromName(roomName);
    const stub = env.RELAY_ROOM.get(id);
    return stub.fetch(request);
  },
};
