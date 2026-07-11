#!/usr/bin/env node
/**
 * Simple WebSocket Signaling Server for CRDT Collaboration
 *
 * Handles peer discovery and WebRTC signaling for browser-to-browser
 * collaboration.
 */
import { WebSocketServer } from 'ws';

const PORT = process.env.PORT || 8080;

const wss = new WebSocketServer({ port: PORT });

// Track connected clients
const clients = new Map();

console.log(`[Signaling Server] Starting on port ${PORT}...`);

wss.on('connection', (ws) => {
  let clientId = null;

  console.log('[Signaling Server] New connection');

  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message.toString());

      switch (data.type) {
        case 'join':
          // Register new peer
          clientId = data.agentId;
          clients.set(clientId, ws);
          console.log(`[Signaling Server] Peer joined: ${clientId}`);
          console.log(`[Signaling Server] Total peers: ${clients.size}`);

          // Notify all other peers about the new peer
          broadcast({
            type: 'peer_joined',
            peerId: clientId
          }, clientId);

          // Send current peer list to new peer
          const peerList = Array.from(clients.keys()).filter(id => id !== clientId);
          ws.send(JSON.stringify({
            type: 'peer_list',
            peers: peerList
          }));
          break;

        case 'offer':
        case 'answer':
        case 'ice_candidate':
          // Forward signaling messages to target peer
          const targetClient = clients.get(data.to);
          if (targetClient && targetClient.readyState === WebSocket.OPEN) {
            targetClient.send(JSON.stringify(data));
          } else {
            console.warn(`[Signaling Server] Target peer not found or not ready: ${data.to}`);
          }
          break;

        default:
          console.warn(`[Signaling Server] Unknown message type: ${data.type}`);
      }
    } catch (error) {
      console.error('[Signaling Server] Error handling message:', error);
    }
  });

  ws.on('close', () => {
    if (clientId) {
      clients.delete(clientId);
      console.log(`[Signaling Server] Peer left: ${clientId}`);
      console.log(`[Signaling Server] Total peers: ${clients.size}`);

      // Notify other peers
      broadcast({
        type: 'peer_left',
        peerId: clientId
      }, clientId);
    }
  });

  ws.on('error', (error) => {
    console.error('[Signaling Server] WebSocket error:', error);
  });
});

/**
 * Broadcast message to all clients except sender
 */
function broadcast(message, excludeId = null) {
  const messageStr = JSON.stringify(message);

  for (const [id, client] of clients) {
    if (id !== excludeId && client.readyState === WebSocket.OPEN) {
      client.send(messageStr);
    }
  }
}

wss.on('listening', () => {
  console.log(`[Signaling Server] Listening on ws://localhost:${PORT}`);
  console.log('[Signaling Server] Ready for peer connections');
});

wss.on('error', (error) => {
  console.error('[Signaling Server] Server error:', error);
});

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\n[Signaling Server] Shutting down...');
  wss.close(() => {
    console.log('[Signaling Server] Server closed');
    process.exit(0);
  });
});
