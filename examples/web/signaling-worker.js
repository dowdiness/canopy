/**
 * Cloudflare Worker with Durable Objects for CRDT Signaling Server
 *
 * This implements a WebSocket signaling server for peer discovery and WebRTC
 * coordination, deployed on Cloudflare's edge network.
 */

/**
 * Durable Object that manages WebSocket connections and signaling
 */
export class SignalingRoom {
  constructor(state, env) {
    this.state = state;
    this.clients = new Map(); // Map<clientId, WebSocket>
    this.env = env;
  }

  /**
   * Handle incoming HTTP requests (WebSocket upgrades)
   */
  async fetch(request) {
    const upgradeHeader = request.headers.get('Upgrade');
    if (!upgradeHeader || upgradeHeader !== 'websocket') {
      return new Response('Expected WebSocket upgrade', { status: 426 });
    }

    // Create WebSocket pair
    const webSocketPair = new WebSocketPair();
    const [client, server] = Object.values(webSocketPair);

    // Handle the WebSocket session
    this.handleSession(server);

    // Return the client WebSocket in the response
    return new Response(null, {
      status: 101,
      webSocket: client,
    });
  }

  /**
   * Handle a WebSocket session
   */
  handleSession(ws) {
    // Accept the WebSocket connection
    ws.accept();

    let clientId = null;

    // Handle incoming messages
    ws.addEventListener('message', async (event) => {
      try {
        const data = JSON.parse(event.data);

        switch (data.type) {
          case 'join':
            // Register new peer
            clientId = data.agentId;
            this.clients.set(clientId, ws);

            console.log(`[SignalingRoom] Peer joined: ${clientId}`);
            console.log(`[SignalingRoom] Total peers: ${this.clients.size}`);

            // Notify all other peers about the new peer
            this.broadcast({
              type: 'peer_joined',
              peerId: clientId
            }, clientId);

            // Send current peer list to new peer
            const peerList = Array.from(this.clients.keys())
              .filter(id => id !== clientId);

            ws.send(JSON.stringify({
              type: 'peer_list',
              peers: peerList
            }));
            break;

          case 'offer':
          case 'answer':
          case 'ice_candidate':
            // Forward signaling messages to target peer
            const targetClient = this.clients.get(data.to);
            if (targetClient) {
              try {
                targetClient.send(JSON.stringify(data));
              } catch (error) {
                console.error(`[SignalingRoom] Error sending to ${data.to}:`, error);
              }
            } else {
              console.warn(`[SignalingRoom] Target peer not found: ${data.to}`);
            }
            break;

          default:
            console.warn(`[SignalingRoom] Unknown message type: ${data.type}`);
        }
      } catch (error) {
        console.error('[SignalingRoom] Error handling message:', error);
      }
    });

    // Handle connection close
    ws.addEventListener('close', () => {
      if (clientId) {
        this.clients.delete(clientId);
        console.log(`[SignalingRoom] Peer left: ${clientId}`);
        console.log(`[SignalingRoom] Total peers: ${this.clients.size}`);

        // Notify other peers
        this.broadcast({
          type: 'peer_left',
          peerId: clientId
        }, clientId);
      }
    });

    // Handle errors
    ws.addEventListener('error', (error) => {
      console.error('[SignalingRoom] WebSocket error:', error);
    });
  }

  /**
   * Broadcast message to all clients except sender
   */
  broadcast(message, excludeId = null) {
    const messageStr = JSON.stringify(message);

    for (const [id, client] of this.clients) {
      if (id !== excludeId) {
        try {
          client.send(messageStr);
        } catch (error) {
          console.error(`[SignalingRoom] Error broadcasting to ${id}:`, error);
          // Remove dead connections
          this.clients.delete(id);
        }
      }
    }
  }
}

/**
 * Worker entry point
 */
export default {
  async fetch(request, env) {
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Upgrade, Connection',
        },
      });
    }

    // Get or create the Durable Object instance
    // Using a single global room for all peers
    const id = env.SIGNALING_ROOM.idFromName('global-room');
    const stub = env.SIGNALING_ROOM.get(id);

    // Forward the request to the Durable Object
    return stub.fetch(request);
  },
};
