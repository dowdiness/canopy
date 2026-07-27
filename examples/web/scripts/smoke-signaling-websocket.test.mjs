import assert from 'node:assert/strict';
import test from 'node:test';
import { parsePeerList } from './smoke-signaling-websocket.mjs';

test('accepts a peer list containing only other string identities', () => {
  assert.deepEqual(
    parsePeerList('{"type":"peer_list","peers":["peer-a","peer-b"]}', 'self'),
    ['peer-a', 'peer-b'],
  );
});

test('rejects malformed, mistyped, and self-containing peer lists', () => {
  for (const payload of [
    'not-json',
    'null',
    '{"type":"peer_joined","peers":[]}',
    '{"type":"peer_list","peers":"peer-a"}',
    '{"type":"peer_list","peers":[7]}',
    '{"type":"peer_list","peers":["self"]}',
  ]) {
    assert.throws(() => parsePeerList(payload, 'self'));
  }
});
