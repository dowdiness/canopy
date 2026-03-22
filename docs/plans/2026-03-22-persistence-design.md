# Document Persistence — Design Spec

**Date:** 2026-03-22
**Status:** Draft
**Scope:** `examples/ideal/web/` (frontend) + `examples/ideal/web/relay-worker.js` (Cloudflare Durable Object)

---

## Goal

Add document persistence so users can save work, reload the page, and share documents via URL. Two storage layers: localStorage for instant client-side restore, Durable Object SQLite for collaborative persistence across peers.

---

## Storage Architecture

### localStorage (client-side)

- **Key:** `canopy-doc-{roomId}` → **Value:** `export_all_json(1)` output (SyncMessage JSON string)
- Saved on every edit (debounced ~1s) and on `beforeunload`
- On page load: if localStorage has data for this room, `apply_sync_json(1, savedState)` before connecting to server
- Gives instant restore on reload, works offline

### Durable Object SQLite (server-side)

Target file: `examples/ideal/web/relay-worker.js` (the JSON protocol relay that the ideal editor actually uses — NOT `examples/relay-server/`).

- **Table:** `operations(id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT NOT NULL)`
- On `"operation"` message: write op to SQLite before broadcasting to peers
- On `"join"`: replay from SQLite instead of in-memory `this.ops` array
- Documents survive all peers disconnecting and Durable Object eviction

The `RelayRoom` class in `relay-worker.js` already has `this.state` (Durable Object state) from the constructor. SQLite is accessed via `this.state.storage.sql`.

### Sync order on page load

1. MoonBit creates editor during module init (`init_model` in `main.mbt`, handle = 1)
2. In `doMount()`: read room ID from URL hash
3. Load from localStorage → `crdt.apply_sync_json(1, savedState)` (instant, before UI mount)
4. `el.mount(handle, crdt)` — render the editor
5. `startSync(roomId)` → connect to server → receive any operations we missed
6. CRDT merge handles deduplication — applying the same ops twice is safe

**Key: localStorage restore happens in `doMount()`, BEFORE `el.mount()` and `startSync()`**, so the user sees their saved content immediately.

---

## URL Scheme

**Format:** `https://editor.example.com/#abc123`

- Hash fragment contains the room ID
- On page load: read `location.hash`
  - If empty → generate new 8-char ID (`crypto.randomUUID().slice(0, 8)` or `Math.random().toString(36).slice(2, 10)`), `history.replaceState` to set hash
  - If present → join existing room
- SyncClient connects with the hash as room name (replacing hardcoded `DEFAULT_ROOM`)

### localStorage keying

- `canopy-doc-{roomId}` — CRDT state (SyncMessage JSON)
- `canopy-agent-{roomId}` — agent ID (per-room, persistent across reloads via localStorage instead of sessionStorage)

### Document lifecycle

- Visit with no hash → new document, new room ID, editor with sample text from `init_model`
- Visit with hash → join existing room, load from localStorage + server (overrides sample text)
- Share the URL → collaborator joins the same room
- No document listing UI — browser history serves as the document list

**Note:** MoonBit's `init_model` seeds the editor with sample text. When loading a saved document, `apply_sync_json` merges the saved CRDT state, which will contain the actual document content. The sample text only shows for brand-new documents with no saved state.

---

## Implementation

### Frontend changes (`examples/ideal/web/src/`)

**main.ts — room ID + localStorage:**
- At top of `doMount(el, crdt)` (before `el.mount()`):
  - Read `location.hash.slice(1)` for room ID
  - If empty: generate ID, `history.replaceState(null, '', '#' + roomId)`
  - Check `localStorage.getItem('canopy-doc-' + roomId)`:
    - If found: `crdt.apply_sync_json(1, savedState)`
  - Use `roomId` for agent ID key: `localStorage` instead of `sessionStorage` for agent ID persistence across sessions
- After `el.mount()`:
  - Set up save on `CanopyEvents.TEXT_CHANGE`: debounced (1s) `localStorage.setItem('canopy-doc-' + roomId, crdt.export_all_json(1))`
  - `window.addEventListener('beforeunload', () => saveNow())`
  - Pass `roomId` to `startSync(roomId)` instead of hardcoded room

**sync.ts — dynamic room:**
- `connect()` method already accepts optional room name
- Change `DEFAULT_ROOM` usage: accept room as required parameter to `SyncClient` constructor or `connect()`
- `scheduleReconnect()` must use the stored room name, not DEFAULT_ROOM

### Server changes (`examples/ideal/web/relay-worker.js`)

This is the actual relay the ideal editor connects to (JSON protocol: join/operation/sync/ephemeral).

**Schema initialization** (in constructor or lazy on first request):
```javascript
constructor(state, env) {
  this.state = state;
  this.env = env;
  this.clients = new Set();
  // Initialize SQLite schema
  this.state.storage.sql.exec(`
    CREATE TABLE IF NOT EXISTS operations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      data TEXT NOT NULL
    )
  `);
}
```

**On join (replace in-memory `this.ops` replay):**
```javascript
case "join": {
  joined = true;
  this.clients.add(ws);
  // Replay from SQLite instead of in-memory array
  const cursor = this.state.storage.sql.exec(
    "SELECT data FROM operations ORDER BY id"
  );
  const ops = [];
  for (const row of cursor) {
    ops.push(row.data);
  }
  if (ops.length > 0) {
    ws.send(JSON.stringify({ type: "sync", ops }));
  }
  break;
}
```

**On operation (persist before broadcast):**
```javascript
case "operation": {
  const op = msg.op;
  // Persist to SQLite
  this.state.storage.sql.exec(
    "INSERT INTO operations (data) VALUES (?)", op
  );
  // Broadcast to peers (existing logic)
  // ...
}
```

**Remove `this.ops` in-memory array** — SQLite is the source of truth now.

### No MoonBit changes

All required APIs already exist and are re-exported via `crdt_reexport.mbt`:
- `export_all_json(handle)` — full CRDT state
- `apply_sync_json(handle, json)` — merge operations
- `get_version_json(handle)` — version tracking

Editor creation uses MoonBit's `init_model` (singleton handle = 1) — no `create_editor` call from TypeScript.

---

## Edge Cases

### localStorage quota exceeded
- Catch `QuotaExceededError` on `setItem`, log warning, continue without local persistence
- JSON CRDT state for typical documents is small (< 1MB)

### Corrupted localStorage
- Wrap `apply_sync_json` in try/catch
- On failure: log warning, remove the corrupted entry, continue with empty state
- Server will provide the authoritative state on connect

### Stale localStorage + fresh server state
- Not a problem — CRDT merge is idempotent and commutative
- Client applies localStorage state, then server sends additional operations
- Result is the union of both — no data loss, no conflicts

### Multiple tabs same document
- Each tab has its own editor instance with the same agent ID
- Both connect to the same room via WebSocket
- CRDT handles concurrent edits from same agent correctly
- localStorage writes may race — last write wins, but server has the authoritative state

### New document with sample text
- MoonBit's `init_model` seeds with sample text (`let id = λx.x ...`)
- For new rooms (no hash): sample text is the initial state, saved to localStorage on first edit
- For existing rooms (hash in URL): `apply_sync_json` from localStorage/server replaces sample text

### SQLite growth
- Operations accumulate indefinitely per room
- For v1: no compaction. Typical document has hundreds of operations, not millions.
- Future: periodic compaction by replacing all ops with a single `export_all` snapshot

---

## Testing

- Create doc → type → reload → text preserved (localStorage)
- Create doc → copy URL → open in incognito → document appears (server persistence)
- Both peers disconnect → reconnect via URL → document restored (SQLite)
- Offline editing → reconnect → changes synced
- Corrupted localStorage → graceful fallback to server state

---

## Out of Scope

- Document listing / management UI
- Authentication / access control
- Document deletion / expiry / TTL
- Binary serialization / compression of CRDT state
- Conflict resolution UI (CRDT handles it automatically)
- Playwright E2E tests for ideal editor
- SQLite compaction / snapshot optimization
