# WebSocket Transport — MoonBit-First Collaborative Sync

**Date:** March 19, 2026
**Status:** Draft
**Scope:** `editor/`, `relay/`, `examples/prosemirror/`, `examples/relay-server/`
**Builds on:** [Ephemeral Store v2](../archive/2026-03-19-ephemeral-store-v2-design.md)
**Inspired by:** [mizchi/converge](https://github.com/mizchi/converge) two-tier architecture, [mizchi/npm_typed.mbt](https://github.com/mizchi/npm_typed.mbt) FFI patterns

## Goal

Enable real-time multi-peer collaboration over WebSocket with minimal TypeScript — all sync logic (session management, broadcast, message routing, ephemeral merge) lives in MoonBit. TypeScript is only the ~30 lines of irreducible event-loop glue that MoonBit's FFI cannot express (callback registration, CF Durable Object class declaration, ArrayBuffer→Bytes conversion).

## Architecture Overview

```
Browser                           Cloudflare Worker
┌─────────────────────┐           ┌──────────────────────────────┐
│ TypeScript (~6 lines)│           │ TypeScript (~25 lines)       │
│  new WebSocket(url)  │           │  export class CrdtDoc        │
│  ws.onmessage = ... │◄─────────►│    new WebSocketPair()       │
│  ws.onopen = ...    │  binary   │    server.accept()           │
│  ws.onclose = ...   │  frames   │    server.addEventListener() │
├─────────────────────┤           ├──────────────────────────────┤
│ MoonBit (all logic)  │           │ MoonBit (all logic)          │
│  SyncEditor          │           │  RelayRoom                   │
│  EphemeralHub        │           │  session management          │
│  encode/decode msgs  │           │  broadcast via opaque WS     │
│  ws_on_message()     │           │  encode PeerJoined/Left      │
│  js_ws_send()        │           │  ephemeral merge             │
└─────────────────────┘           └──────────────────────────────┘
```

### Why Minimal TypeScript

MoonBit's JS FFI cannot:
- Register event listeners (`ws.onmessage = callback` requires passing a closure FROM JS)
- Declare CF Durable Object classes (`export class ... implements DurableObject`)
- Call `new WebSocketPair()` (CF-specific constructor)

MoonBit CAN:
- Hold opaque WebSocket references via `#external pub type JsWebSocket`
- Call `ws.send(data)` via `self.as_any()._call("send", [...])`
- Manage session maps (`Map[String, JsWebSocket]`)
- Do all protocol encoding/decoding, merge, routing

## Client Side

### WebSocket FFI (`editor/websocket_js.mbt`, JS target only)

```moonbit
#external
pub type JsWebSocket

pub fn JsWebSocket::as_any(self : JsWebSocket) -> @core.Any = "%identity"

pub fn JsWebSocket::send_bytes(self : JsWebSocket, data : Bytes) -> Unit {
  self.as_any()._call("send", [@core.any(data)]) |> ignore
}

pub fn JsWebSocket::close(self : JsWebSocket) -> Unit {
  self.as_any()._call("close", []) |> ignore
}
```

### WebSocket State on SyncEditor

The `JsWebSocket` reference is stored inside MoonBit (no global):

```moonbit
// Added to SyncEditor struct
priv mut ws : JsWebSocket?    // None when disconnected

// Send helper — checks connection before sending
fn SyncEditor::ws_send(self : SyncEditor, data : Bytes) -> Unit {
  match self.ws {
    Some(ws) => ws.send_bytes(data)
    None => ()  // silently drop if disconnected
  }
}
```

### Exported Functions (added to `crdt.mbt`)

```moonbit
// Called by JS when WebSocket connects — stores ws ref, sends PeerJoined
pub fn ws_on_open(handle : Int, ws : JsWebSocket) -> Unit

// Called by JS when binary message received
pub fn ws_on_message(handle : Int, data : Bytes) -> Unit

// Called by JS when WebSocket closes
pub fn ws_on_close(handle : Int) -> Unit
```

### TypeScript Glue (`examples/prosemirror/src/ws-glue.ts`)

```typescript
import * as crdt from "@moonbit/canopy";

export function connectWebSocket(handle: number, url: string) {
  const ws = new WebSocket(url);
  ws.binaryType = 'arraybuffer';
  ws.onopen = () => crdt.ws_on_open(handle, ws);  // pass ws ref to MoonBit
  ws.onmessage = (e) => crdt.ws_on_message(handle, new Uint8Array(e.data));
  ws.onclose = () => crdt.ws_on_close(handle);
}
```

### CRDT Serialization: JSON-as-Bytes

Two types are both named `SyncMessage`:
- **Wire `SyncMessage`** (`editor/sync_protocol.mbt`) — the transport envelope: `CrdtOps(Bytes)`, `EphemeralUpdate(...)`, `PeerJoined(...)`, etc.
- **`@text.SyncMessage`** (`event-graph-walker/text/sync.mbt`) — the CRDT operation bundle with `runs` and `heads`.

To wrap `@text.SyncMessage` inside `CrdtOps(Bytes)`, we use `@text.SyncMessage::to_json_string()` encoded as UTF-8 Bytes. This reuses the existing JSON serialization path (same as `export_all_json`/`apply_sync_json`).

```moonbit
// Encode: @text.SyncMessage → Bytes (JSON as UTF-8)
fn crdt_msg_to_bytes(msg : @text.SyncMessage) -> Bytes {
  let json_str = msg.to_json_string()
  let buf = @buffer.new()
  buf.write_string(json_str)
  buf.to_bytes()
}

// Decode: Bytes → @text.SyncMessage
fn crdt_msg_from_bytes(data : Bytes) -> @text.SyncMessage? {
  let json_str = data.to_unchecked_string()
  @text.SyncMessage::from_json_string(json_str)  // returns Option or raises
}
```

A binary codec would be more efficient but JSON works for MVP and matches the existing `export_all_json`/`apply_sync_json` path.

### Client Message Flow

**Local edit → remote peers:**
```
User types → SyncEditor.insert()
  → export_since() → @text.SyncMessage
  → crdt_msg_to_bytes(msg) → Bytes
  → encode_message(CrdtOps(bytes)) → wire Bytes   ← MoonBit
  → self.ws_send(wire_bytes)                       ← MoonBit calls JsWebSocket
  → WebSocket → relay → other peers
```

**Remote message → local state:**
```
WebSocket message event                            ← JS
  → crdt.ws_on_message(handle, bytes)              ← JS calls MoonBit
  → decode_message(bytes) match {
      CrdtOps(payload) →
        crdt_msg_from_bytes(payload) → @text.SyncMessage
        doc.apply_sync(msg)
      EphemeralUpdate(ns, payload) → hub.apply(ns, payload)
      PeerJoined(peer_id) →
        // Send ephemeral state: one EphemeralUpdate per namespace
        for ns in [Cursor, EditMode, Drag, Presence]:
          ws_send(encode_message(EphemeralUpdate(ns, hub.encode(ns))))
        // Send CRDT state
        ws_send(encode_message(CrdtOps(crdt_msg_to_bytes(export_all()))))
      PeerLeft(peer_id) → hub.on_peer_leave(peer_id)
    }                                              ← all MoonBit
```

## Relay Server

### Design: Stateless Room Relay

The relay is a message router. It does NOT store CRDT operations or parse message payloads. It:

1. Manages rooms (peer → WebSocket mapping)
2. Broadcasts messages to room peers (excluding sender)
3. Generates `PeerJoined`/`PeerLeft` control messages
4. Late-joiner catch-up is peer-to-peer: on `PeerJoined`, existing peers send their state

### Relay Room (`relay/relay_room.mbt`)

The relay package does NOT import `editor/` — it has zero heavy dependencies. It only needs to encode `PeerJoined`/`PeerLeft` messages, which requires ~20 lines of the wire format (version byte + type byte + flags byte + string encoding). The relay duplicates this minimal encoding rather than pulling in the full editor dependency tree.

```moonbit
// relay/js_websocket.mbt — opaque WS type (same pattern as editor/, separate declaration)
#external
pub type JsWebSocket

pub fn JsWebSocket::as_any(self : JsWebSocket) -> @core.Any = "%identity"

pub fn JsWebSocket::send_bytes(self : JsWebSocket, data : Bytes) -> Unit {
  self.as_any()._call("send", [@core.any(data)]) |> ignore
}
```

```moonbit
// relay/relay_room.mbt
pub struct RelayRoom {
  sessions : Map[String, JsWebSocket]   // peer_id → WebSocket
}

pub fn RelayRoom::new() -> RelayRoom {
  { sessions: Map::new() }
}

pub fn RelayRoom::on_connect(
  self : RelayRoom,
  peer_id : String,
  ws : JsWebSocket,
) -> Unit {
  // Broadcast PeerJoined to existing peers
  let join_msg = encode_peer_control(b'\x01', peer_id) // 0x01 = Join sub-type
  self.broadcast(peer_id, join_msg)
  // Add to room
  self.sessions[peer_id] = ws
}

pub fn RelayRoom::on_message(
  self : RelayRoom,
  sender : String,
  data : Bytes,
) -> Unit {
  // Broadcast raw binary to all other peers — relay doesn't parse
  self.broadcast(sender, data)
}

pub fn RelayRoom::on_disconnect(
  self : RelayRoom,
  peer_id : String,
) -> Unit {
  self.sessions.remove(peer_id)
  // Broadcast PeerLeft to remaining peers
  let leave_msg = encode_peer_control(b'\x02', peer_id) // 0x02 = Leave sub-type
  self.broadcast(peer_id, leave_msg)
}

fn RelayRoom::broadcast(
  self : RelayRoom,
  exclude : String,
  data : Bytes,
) -> Unit {
  for peer_id, ws in self.sessions {
    if peer_id != exclude {
      ws.send_bytes(data)
    }
  }
}
```

```moonbit
// relay/wire.mbt — minimal wire format for PeerJoined/PeerLeft only
// Duplicates ~20 lines of the SyncMessage wire format. This is intentional:
// the relay must NOT depend on editor/ to stay lightweight.
fn encode_peer_control(sub_type : Byte, peer_id : String) -> Bytes {
  let buf = @buffer.new()
  buf.write_byte(b'\x01')     // version
  buf.write_byte(b'\x05')     // message_type: Room control
  buf.write_byte(b'\x00')     // flags: no BFT
  buf.write_byte(sub_type)    // 0x01=Join, 0x02=Leave
  // uvarint-prefixed UTF-8 string
  let str_buf = @buffer.new()
  str_buf.write_string(peer_id)
  let str_bytes = str_buf.to_bytes()
  write_relay_uvarint(buf, str_bytes.length())
  buf.write_bytes(str_bytes)
  buf.to_bytes()
}

fn write_relay_uvarint(buf : @buffer.Buffer, value : Int) -> Unit {
  let mut v = value
  while v >= 0x80 {
    buf.write_byte(((v & 0x7F) | 0x80).to_byte())
    v = v >> 7
  }
  buf.write_byte(v.to_byte())
}
```

### Exported Relay Functions (added to `crdt.mbt`)

```moonbit
let relay_rooms : Map[String, @relay.RelayRoom] = Map::new()

fn get_or_create_room(room_id : String) -> @relay.RelayRoom {
  match relay_rooms.get(room_id) {
    Some(room) => room
    None => {
      let room = @relay.RelayRoom::new()
      relay_rooms[room_id] = room
      room
    }
  }
}

// These are called from the CF Worker TypeScript glue:
pub fn relay_on_connect(room_id : String, peer_id : String, ws : @relay.JsWebSocket) -> Unit {
  get_or_create_room(room_id).on_connect(peer_id, ws)
}

pub fn relay_on_message(room_id : String, peer_id : String, data : Bytes) -> Unit {
  get_or_create_room(room_id).on_message(peer_id, data)
}

pub fn relay_on_disconnect(room_id : String, peer_id : String) -> Unit {
  get_or_create_room(room_id).on_disconnect(peer_id)
}
```

### Cloudflare Durable Object (`examples/relay-server/src/index.ts`)

```typescript
import * as relay from "@moonbit/canopy";

export interface Env { RELAY: DurableObjectNamespace; }

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const room = url.searchParams.get("room") ?? "main";
    const id = env.RELAY.idFromName(room);
    return env.RELAY.get(id).fetch(request);
  },
};

export class RelayRoom implements DurableObject {
  private roomId: string;
  constructor(state: DurableObjectState) {
    this.roomId = state.id.toString();
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Expected WebSocket", { status: 426 });
    }
    const url = new URL(request.url);
    const peerId = url.searchParams.get("peer_id") ?? crypto.randomUUID();
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];
    server.accept();

    relay.relay_on_connect(this.roomId, peerId, server);

    server.addEventListener("message", (e) => {
      const data = e.data instanceof ArrayBuffer
        ? new Uint8Array(e.data)
        : new TextEncoder().encode(e.data as string);
      relay.relay_on_message(this.roomId, peerId, data);
    });

    server.addEventListener("close", () => {
      relay.relay_on_disconnect(this.roomId, peerId);
    });

    return new Response(null, { status: 101, webSocket: client });
  }
}
```

### Local Development

Use `wrangler dev` to run the relay locally. It emulates CF Workers + Durable Objects faithfully — same code, same behavior as production, zero divergence.

```bash
cd examples/relay-server
npm install
wrangler dev   # relay on localhost:8787
```

No separate dev server needed. The `wrangler.toml` + `src/index.ts` above IS the dev server.

## Package Structure

```
editor/
  websocket_js.mbt          ← NEW: JsWebSocket opaque type (JS target only, add to moon.pkg targets)
  websocket_native.mbt       ← NEW: stub for native target (add to moon.pkg targets)
  sync_editor.mbt            ← MODIFY: add ws field + ws_on_open/ws_on_message/ws_on_close methods
  moon.pkg                   ← MODIFY: add target entries for websocket_js.mbt/websocket_native.mbt

relay/
  js_websocket.mbt           ← NEW: JsWebSocket opaque type (relay's own, no editor dep)
  relay_room.mbt             ← NEW: RelayRoom struct + broadcast logic
  wire.mbt                   ← NEW: minimal PeerJoined/PeerLeft encoding (~20 lines)
  relay_room_test.mbt        ← NEW: tests using InMemoryTransport-like pattern
  moon.pkg                   ← NEW: minimal deps (buffer only, NO editor import)

crdt.mbt                     ← MODIFY: add relay exports
moon.pkg                     ← MODIFY: add relay exports to JS exports list

examples/relay-server/
  src/index.ts               ← NEW: CF Durable Object (~30 lines)
  wrangler.toml              ← NEW: CF config (local dev via `wrangler dev`)
  package.json               ← NEW: wrangler + @cloudflare/workers-types

examples/prosemirror/
  src/ws-glue.ts             ← NEW: WebSocket event wiring (~6 lines)
  src/main.ts                ← MODIFY: call connectWebSocket on init
```

## Protocol Flow

### Peer A joins room (first peer)

```
A → relay: WebSocket connect
relay: broadcast PeerJoined("A") → no recipients (room empty)
relay: add A to sessions
A: hub.set_presence("Alice", "#ff0000", Active)
```

No messages are sent — A is the first peer.

### Peer B joins room (late joiner)

```
B → relay: WebSocket connect
relay → A: PeerJoined("B")        [MoonBit generates + broadcasts to existing peers]
relay: add B to sessions

A receives PeerJoined("B"):
  // Send ephemeral state: one EphemeralUpdate per namespace
  A → relay → B: encode_message(EphemeralUpdate(Cursor, hub.encode(Cursor)))
  A → relay → B: encode_message(EphemeralUpdate(Presence, hub.encode(Presence)))
  // (EditMode, Drag only if non-empty)
  // Send full CRDT document state
  A → relay → B: encode_message(CrdtOps(crdt_msg_to_bytes(export_all())))

B receives CrdtOps: crdt_msg_from_bytes → doc.apply_sync()
B receives EphemeralUpdate(Cursor, ...): hub.apply(Cursor, data)
B receives EphemeralUpdate(Presence, ...): hub.apply(Presence, data)
B is now caught up.
```

**Note:** If N peers exist when B joins, all N peers send their state. B receives N copies — the CRDT merge and LWW ephemeral resolve correctly. This is bandwidth-wasteful for large rooms but correct and simple. A future optimization could designate one peer as the responder.

### Peer A types a character

```
A: SyncEditor.insert("x")
A → relay → B: encode_message(CrdtOps(crdt_msg_to_bytes(export_since())))
A → relay → B: encode_message(EphemeralUpdate(Cursor, hub.encode(Cursor)))

B receives CrdtOps: crdt_msg_from_bytes → doc.apply_sync() → reconcile PM
B receives EphemeralUpdate: hub.apply(Cursor, data) → cursor_view updates
```

### Peer A disconnects

```
A: WebSocket close
relay: RelayRoom.on_disconnect("A")
relay → B: PeerLeft("A")          [MoonBit generates + broadcasts]

B receives PeerLeft("A"): hub.on_peer_leave("A")
B: cursor/presence/drag state for A removed
```

## What Changes

**New files:**
- `editor/websocket_js.mbt` — `JsWebSocket` opaque type, `js_ws_send` extern
- `editor/websocket_native.mbt` — native target stubs
- `relay/relay_room.mbt` — `RelayRoom` struct, session management, broadcast
- `relay/relay_room_test.mbt` — relay tests
- `relay/moon.pkg` — package config
- `examples/relay-server/` — CF Worker + local dev server
- `examples/prosemirror/src/ws-glue.ts` — WebSocket event wiring

**Modified files:**
- `crdt.mbt` — add `ws_on_open`, `ws_on_message`, `ws_on_close`, relay exports
- `moon.pkg` — add relay exports to JS exports list
- `editor/sync_editor.mbt` — add WebSocket lifecycle methods
- `examples/prosemirror/src/main.ts` — call `connectWebSocket`

**Unchanged:**
- `editor/ephemeral_hub.mbt` — reused as-is
- `editor/sync_protocol.mbt` — `SyncMessage` encode/decode reused by relay
- `editor/ephemeral.mbt` — core store unchanged
- All existing tests

## Testing Strategy

**Relay unit tests** (no WebSocket, no CF):
- Use `InMemoryTransport`-like pattern: call `on_connect`/`on_message`/`on_disconnect` directly
- Verify: broadcast reaches correct peers, PeerJoined/PeerLeft generated, disconnect cleanup

**Integration tests** (in MoonBit):
- Two `SyncEditor` instances + one `RelayRoom`, wired via direct function calls
- Verify: document convergence after edits, ephemeral state sync, late joiner catch-up

**E2E tests** (future, with Playwright):
- Two browser tabs editing the same document
- Verify: text converges, remote cursors visible

## What This Does NOT Change

- The CRDT (eg-walker) internals
- The incremental parser / loom framework
- The ProseMirror reconciler
- The existing EphemeralStore/EphemeralHub implementation
- The SyncMessage wire format

## Development Workflow

```bash
# Terminal 1: build MoonBit → JS (watch mode)
moon build --target js --release --watch

# Terminal 2: relay server (local CF emulation)
cd examples/relay-server && wrangler dev

# Terminal 3: editor frontend
cd examples/prosemirror && npm run dev
```

## Open Questions

1. **Reconnection** — should the client auto-reconnect with exponential backoff? The existing `sync.ts` already has this logic. Defer to follow-up.
2. **DO persistence** — relay is stateless in MVP. Adding event persistence to DO storage is a natural follow-up for offline support.
3. **Binary CRDT codec** — MVP uses JSON-as-Bytes for `@text.SyncMessage` serialization. A binary codec would be more efficient but is not needed for MVP.
4. **Multiple rooms** — the CF Worker routes by room ID in the URL query param. Each room gets its own DO instance.
5. **N-peer state dump** — when a late joiner connects, all N existing peers send full state. A future optimization could designate one peer as the responder.
