import { randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import WebSocket from 'ws';

export function parsePeerList(payload, agentId) {
  let message;
  try {
    message = JSON.parse(payload);
  } catch {
    throw new Error('Signaling Worker returned invalid JSON.');
  }
  if (
    typeof message !== 'object' ||
    message === null ||
    message.type !== 'peer_list' ||
    !Array.isArray(message.peers) ||
    !message.peers.every((peer) => typeof peer === 'string') ||
    message.peers.includes(agentId)
  ) {
    throw new Error('Signaling Worker returned an invalid peer list.');
  }
  return Object.freeze([...message.peers]);
}

export async function runSignalingHandshake(url, { cloudflareLocal = false } = {}) {
  const agentId = `canopy-smoke-${randomUUID()}`;
  const socket = new WebSocket(url, {
    handshakeTimeout: 5_000,
    maxPayload: 64 * 1024,
    ...(cloudflareLocal
      ? { headers: { 'cf-visitor': '{"scheme":"http"}' } }
      : {}),
  });

  await new Promise((resolve, reject) => {
    let settled = false;
    let handshakeComplete = false;
    let closeTimer;
    const handshakeTimer = setTimeout(
      () => fail(new Error('Timed out waiting for the signaling peer list.')),
      8_000,
    );

    function clearTimers() {
      clearTimeout(handshakeTimer);
      if (closeTimer !== undefined) clearTimeout(closeTimer);
    }

    function fail(error) {
      if (settled) return;
      settled = true;
      clearTimers();
      socket.terminate();
      reject(error);
    }

    socket.once('unexpected-response', (_request, response) => {
      response.resume();
      fail(new Error(`Signaling upgrade returned HTTP ${response.statusCode}.`));
    });
    socket.once('error', (error) => {
      if (!handshakeComplete) fail(error);
    });
    socket.once('open', () => {
      socket.send(JSON.stringify({ type: 'join', agentId }), (error) => {
        if (error) fail(error);
      });
    });
    socket.on('message', (data, isBinary) => {
      if (handshakeComplete) return;
      if (isBinary) {
        fail(new Error('Signaling Worker returned an unexpected binary message.'));
        return;
      }
      try {
        parsePeerList(data.toString(), agentId);
      } catch (error) {
        fail(error);
        return;
      }
      handshakeComplete = true;
      clearTimeout(handshakeTimer);
      socket.close(1000, 'smoke complete');
      closeTimer = setTimeout(() => socket.terminate(), 500);
    });
    socket.once('close', () => {
      if (settled) return;
      if (!handshakeComplete) {
        fail(new Error('Signaling connection closed before the peer list arrived.'));
        return;
      }
      settled = true;
      clearTimers();
      resolve();
    });
  });
}

async function main() {
  const cloudflareLocal = process.argv[3] === '--cloudflare-local';
  if (process.argv.length < 3 || process.argv.length > 4 ||
    (process.argv.length === 4 && !cloudflareLocal)) {
    throw new Error(
      'Usage: node scripts/smoke-signaling-websocket.mjs <ws-url> [--cloudflare-local]',
    );
  }
  const url = new URL(process.argv[2]);
  if (url.protocol !== 'ws:' && url.protocol !== 'wss:') {
    throw new Error('The signaling smoke URL must use ws: or wss:.');
  }
  await runSignalingHandshake(url.href, { cloudflareLocal });
  console.log('Signaling WebSocket handshake: OK');
}

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
