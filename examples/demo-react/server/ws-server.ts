// WebSocket Sync Server for CRDT Collaborative Demo
//
// A minimal relay server that broadcasts CRDT operations between clients.
// Supports room-based collaboration with history replay for late joiners.

import { WebSocketServer, WebSocket } from 'ws';

interface Operation {
  lv: number;
  agent_id: string;
  op_type: 'Insert' | 'Delete';
  content?: string;
  origin_left: number;
  origin_right: number;
  deps: number[];
}

interface Room {
  clients: Set<WebSocket>;
  ops: Operation[];
  seen: Set<string>;
}

const PORT = parseInt(process.env.PORT || '8787', 10);
const rooms = new Map<string, Room>();

function getOrCreateRoom(roomId: string): Room {
  let room = rooms.get(roomId);
  if (!room) {
    room = { clients: new Set(), ops: [], seen: new Set() };
    rooms.set(roomId, room);
    console.log(`[Room] Created: ${roomId}`);
  }
  return room;
}

function opKey(op: Operation): string {
  return `${op.agent_id}:${op.lv}`;
}

const wss = new WebSocketServer({ port: PORT });

console.log(`[Server] WebSocket sync server running on ws://localhost:${PORT}`);

wss.on('connection', (ws) => {
  let currentRoom: Room | null = null;
  let currentRoomId: string | null = null;

  console.log('[Client] Connected');

  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data.toString());

      switch (message.type) {
        case 'join': {
          const roomId = message.room as string;
          currentRoomId = roomId;
          currentRoom = getOrCreateRoom(roomId);
          currentRoom.clients.add(ws);

          console.log(`[Client] Joined room: ${roomId} (${currentRoom.clients.size} clients)`);

          if (currentRoom.ops.length > 0) {
            ws.send(JSON.stringify({ type: 'sync', ops: currentRoom.ops }));
            console.log(`[Sync] Sent ${currentRoom.ops.length} ops to new client`);
          }
          break;
        }

        case 'operation': {
          const op = message.op as Operation;
          const key = opKey(op);

          if (!currentRoom) {
            console.warn('[Warn] Operation received but client not in a room');
            return;
          }

          if (currentRoom.seen.has(key)) {
            return;
          }

          currentRoom.seen.add(key);
          currentRoom.ops.push(op);

          if (currentRoom.ops.length > 10000) {
            const removed = currentRoom.ops.shift();
            if (removed) {
              currentRoom.seen.delete(opKey(removed));
            }
          }

          for (const client of currentRoom.clients) {
            if (client !== ws && client.readyState === WebSocket.OPEN) {
              client.send(JSON.stringify({ type: 'operation', op }));
            }
          }

          console.log(`[Op] ${op.agent_id}:${op.lv} ${op.op_type} -> ${currentRoom.clients.size - 1} clients`);
          break;
        }

        case 'reset': {
          if (currentRoom) {
            currentRoom.ops = [];
            currentRoom.seen.clear();
            console.log(`[Room] Reset: ${currentRoomId}`);
          }
          break;
        }

        default: {
          console.warn(`[Warn] Unknown message type: ${message.type}`);
          ws.send(JSON.stringify({ type: 'error', message: `Unknown message type: ${message.type}` }));
        }
      }
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : 'Unknown error';
      console.error('[Error] Failed to parse message:', errorMsg);
      ws.send(JSON.stringify({ type: 'error', message: `Invalid message format: ${errorMsg}` }));
    }
  });

  ws.on('close', () => {
    if (currentRoom) {
      currentRoom.clients.delete(ws);
      console.log(`[Client] Left room: ${currentRoomId} (${currentRoom.clients.size} clients remaining)`);

      if (currentRoom.clients.size === 0) {
        rooms.delete(currentRoomId!);
        console.log(`[Room] Deleted empty room: ${currentRoomId}`);
      }
    }
  });

  ws.on('error', (err) => {
    console.error('[Error] WebSocket error:', err);
  });
});
