# relay

In-process WebSocket relay for multi-peer CRDT collaboration. A `RelayRoom` holds a set of connected peers and broadcasts messages between them, enforcing membership validity without touching message content.

This package is the server-side half of the real-time sync protocol. It runs inside a Cloudflare Worker (or any native host) as a pure message forwarder — it never parses or interprets CRDT operations.

## Public API

- `RelayRoom` — peer registry with broadcast routing
- `RelayRoom::on_connect(peer_id, send_fn)` — register a peer; returns `false` if duplicate or empty ID
- `RelayRoom::on_message(peer_id, bytes)` — forward `bytes` to all other peers; drops messages from unknown senders
- `RelayRoom::on_disconnect(peer_id)` — deregister a peer and broadcast a `PeerLeft` notification
- `encode_peer_joined(peer_id)` / `encode_peer_left(peer_id)` — build the binary join/leave notifications sent to all existing peers

## Consumers

- `ffi/lambda` — exports `relay_on_connect`, `relay_on_message`, `relay_on_disconnect` to JavaScript via the link block
- Root `moon.pkg` (canopy module facade)

## Dependencies

`moonbitlang/core/buffer` only — this package is intentionally dependency-light so it can compile to any target.

## Stability

Internal but stable — the `RelayRoom` API is the server-side counterpart to the sync protocol in `editor/sync_protocol.mbt`. Changes here require matching changes in the client-side WebSocket wiring.

## Notes

Peer IDs are opaque strings, expected to be UUIDs assigned by the hosting environment (e.g. `crypto.randomUUID()` in a CF Worker). `RelayRoom` enforces uniqueness but does not generate IDs. The `ffi/lambda` package exposes a single global relay room shared across all editor instances on one server process.
