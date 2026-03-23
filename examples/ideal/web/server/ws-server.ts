// WebSocket Relay Server for Canopy Collaborative Editing
//
// A room-based relay that broadcasts CRDT operations between clients.
// Supports history replay, resync, heartbeat, and optional SQLite persistence.
//
// Protocol:
//   Client -> Server: { type: "join"|"operation"|"resync"|"ping"|"ephemeral"|"reset" }
//   Server -> Client: { type: "sync"|"operation"|"pong"|"ephemeral"|"error" }

import { WebSocketServer, WebSocket } from "ws";
import type { OpStore } from "./store";

const PORT = parseInt(process.env.PORT || "8787", 10);
const MAX_OPS = 10_000;
const MAX_PAYLOAD = 5 * 1024 * 1024; // 5MB
const PING_INTERVAL_MS = 30_000;

// Try to load SQLite store; fall back to in-memory if not available.
let store: OpStore | null = null;
try {
  const { createStore } = await import("./store");
  store = createStore();
  console.log("[Server] SQLite persistence enabled");
} catch {
  console.log("[Server] SQLite not available, using in-memory storage");
}

interface Room {
  clients: Set<WebSocket>;
  ops: unknown[]; // only used when store === null
}

const rooms = new Map<string, Room>();

function getOrCreateRoom(roomId: string): Room {
  let room = rooms.get(roomId);
  if (!room) {
    room = { clients: new Set(), ops: [] };
    rooms.set(roomId, room);
    console.log(`[Room] Created: ${roomId}`);
  }
  return room;
}

function getOps(roomId: string, room: Room): unknown[] {
  if (store) return store.getOps(roomId);
  return room.ops;
}

function pushOp(roomId: string, room: Room, op: unknown): void {
  if (store) {
    store.insertOp(roomId, typeof op === "string" ? op : JSON.stringify(op));
    store.evictOldOps(roomId, MAX_OPS);
  } else {
    room.ops.push(op);
    if (room.ops.length > MAX_OPS) room.ops.shift();
  }
}

function clearOps(roomId: string, room: Room): void {
  if (store) store.clearRoom(roomId);
  else room.ops = [];
}

const wss = new WebSocketServer({ port: PORT, maxPayload: MAX_PAYLOAD });
console.log(`[Server] Canopy WebSocket relay running on ws://localhost:${PORT}`);

// Server-side ping: detect dead connections.
const aliveClients = new WeakSet<WebSocket>();
const pingInterval = setInterval(() => {
  for (const ws of wss.clients) {
    if (!aliveClients.has(ws)) { ws.terminate(); continue; }
    aliveClients.delete(ws);
    ws.ping();
  }
}, PING_INTERVAL_MS);

wss.on("close", () => clearInterval(pingInterval));

wss.on("connection", (ws) => {
  let currentRoom: Room | null = null;
  let currentRoomId: string | null = null;

  aliveClients.add(ws);
  ws.on("pong", () => aliveClients.add(ws));

  console.log("[Client] Connected");

  ws.on("message", (raw) => {
    try {
      const message = JSON.parse(raw.toString());

      switch (message.type) {
        case "join": {
          const room = message.room;
          if (typeof room !== "string" || room.length === 0) {
            ws.send(JSON.stringify({ type: "error", message: "Invalid room name" }));
            return;
          }
          currentRoomId = room;
          currentRoom = getOrCreateRoom(room);
          currentRoom.clients.add(ws);
          console.log(`[Client] Joined room: ${room} (${currentRoom.clients.size} clients)`);

          const ops = getOps(room, currentRoom);
          if (ops.length > 0) {
            ws.send(JSON.stringify({ type: "sync", ops }));
            console.log(`[Sync] Sent ${ops.length} ops to new client`);
          }
          break;
        }

        case "operation": {
          if (!currentRoom || !currentRoomId) {
            console.warn("[Warn] Operation received but client not in a room");
            return;
          }
          const op = message.op;
          pushOp(currentRoomId, currentRoom, op);
          for (const client of currentRoom.clients) {
            if (client !== ws && client.readyState === WebSocket.OPEN) {
              client.send(JSON.stringify({ type: "operation", op }));
            }
          }
          console.log(`[Op] Relayed to ${currentRoom.clients.size - 1} clients`);
          break;
        }

        case "resync": {
          if (!currentRoom || !currentRoomId) {
            ws.send(JSON.stringify({ type: "error", message: "Not in a room" }));
            return;
          }
          const ops = getOps(currentRoomId, currentRoom);
          if (ops.length > 0) {
            ws.send(JSON.stringify({ type: "sync", ops }));
            console.log(`[Resync] Sent ${ops.length} ops to client`);
          }
          break;
        }

        case "ping":
          ws.send(JSON.stringify({ type: "pong" }));
          break;

        case "ephemeral": {
          if (!currentRoom) {
            console.warn("[Warn] Ephemeral received but client not in a room");
            return;
          }
          const ephRelay = JSON.stringify({ type: "ephemeral", data: message.data });
          for (const client of currentRoom.clients) {
            if (client !== ws && client.readyState === WebSocket.OPEN) {
              client.send(ephRelay);
            }
          }
          break;
        }

        case "reset": {
          if (currentRoom && currentRoomId) {
            clearOps(currentRoomId, currentRoom);
            console.log(`[Room] Reset: ${currentRoomId}`);
          }
          break;
        }

        default:
          console.warn(`[Warn] Unknown message type: ${message.type}`);
          ws.send(JSON.stringify({ type: "error", message: `Unknown message type: ${message.type}` }));
      }
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : "Unknown error";
      console.error("[Error] Failed to parse message:", errorMsg);
      ws.send(JSON.stringify({ type: "error", message: `Invalid message format: ${errorMsg}` }));
    }
  });

  ws.on("close", () => {
    if (currentRoom) {
      currentRoom.clients.delete(ws);
      console.log(`[Client] Left room: ${currentRoomId} (${currentRoom.clients.size} clients remaining)`);
      if (currentRoom.clients.size === 0 && !store) {
        rooms.delete(currentRoomId!);
        console.log(`[Room] Deleted empty room: ${currentRoomId}`);
      }
    }
  });

  ws.on("error", (err) => console.error("[Error] WebSocket error:", err));
});

// Graceful shutdown
function shutdown() {
  console.log("[Server] Shutting down...");
  clearInterval(pingInterval);
  for (const ws of wss.clients) ws.close(1001, "Server shutting down");
  wss.close(() => {
    store?.close();
    console.log("[Server] Stopped.");
    process.exit(0);
  });
  setTimeout(() => process.exit(0), 5_000);
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
