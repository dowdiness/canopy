// WebSocket Relay Server for Canopy Collaborative Editing
//
// A minimal room-based relay that broadcasts CRDT operations between clients.
// Supports history replay for late joiners.
//
// Protocol:
//   Client -> Server: { type: "join", room: string }
//   Client -> Server: { type: "operation", op: <CRDT sync JSON> }
//   Server -> Client: { type: "sync", ops: <CRDT sync JSON>[] }   (history for late joiners)
//   Server -> Client: { type: "operation", op: <CRDT sync JSON> } (relayed from another peer)

import { WebSocketServer, WebSocket } from "ws";

interface Room {
  clients: Set<WebSocket>;
  /** Stored operations for replaying to late joiners. */
  ops: unknown[];
}

const PORT = parseInt(process.env.PORT || "8787", 10);
const MAX_OPS = 10_000;

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

const wss = new WebSocketServer({ port: PORT });

console.log(
  `[Server] Canopy WebSocket relay running on ws://localhost:${PORT}`,
);

wss.on("connection", (ws) => {
  let currentRoom: Room | null = null;
  let currentRoomId: string | null = null;

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
          const roomId = room;
          currentRoomId = roomId;
          currentRoom = getOrCreateRoom(roomId);
          currentRoom.clients.add(ws);

          console.log(
            `[Client] Joined room: ${roomId} (${currentRoom.clients.size} clients)`,
          );

          // Replay stored ops to the newly joined client
          if (currentRoom.ops.length > 0) {
            ws.send(JSON.stringify({ type: "sync", ops: currentRoom.ops }));
            console.log(
              `[Sync] Sent ${currentRoom.ops.length} ops to new client`,
            );
          }
          break;
        }

        case "operation": {
          if (!currentRoom) {
            console.warn(
              "[Warn] Operation received but client not in a room",
            );
            return;
          }

          const op = message.op;

          // Store for late-joiner replay
          currentRoom.ops.push(op);

          // Evict oldest ops if we exceed the cap
          if (currentRoom.ops.length > MAX_OPS) {
            currentRoom.ops.shift();
          }

          // Broadcast to all other clients in the room
          for (const client of currentRoom.clients) {
            if (client !== ws && client.readyState === WebSocket.OPEN) {
              client.send(JSON.stringify({ type: "operation", op }));
            }
          }

          console.log(
            `[Op] Relayed to ${currentRoom.clients.size - 1} clients`,
          );
          break;
        }

        case "ephemeral": {
          // Broadcast ephemeral data to all other peers (no history storage)
          if (!currentRoom) {
            console.warn(
              "[Warn] Ephemeral received but client not in a room",
            );
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
          if (currentRoom) {
            currentRoom.ops = [];
            console.log(`[Room] Reset: ${currentRoomId}`);
          }
          break;
        }

        default: {
          console.warn(`[Warn] Unknown message type: ${message.type}`);
          ws.send(
            JSON.stringify({
              type: "error",
              message: `Unknown message type: ${message.type}`,
            }),
          );
        }
      }
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : "Unknown error";
      console.error("[Error] Failed to parse message:", errorMsg);
      ws.send(
        JSON.stringify({
          type: "error",
          message: `Invalid message format: ${errorMsg}`,
        }),
      );
    }
  });

  ws.on("close", () => {
    if (currentRoom) {
      currentRoom.clients.delete(ws);
      console.log(
        `[Client] Left room: ${currentRoomId} (${currentRoom.clients.size} clients remaining)`,
      );

      if (currentRoom.clients.size === 0) {
        rooms.delete(currentRoomId!);
        console.log(`[Room] Deleted empty room: ${currentRoomId}`);
      }
    }
  });

  ws.on("error", (err) => {
    console.error("[Error] WebSocket error:", err);
  });
});
