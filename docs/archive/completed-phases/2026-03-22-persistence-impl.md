# Document Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add localStorage + Durable Object SQLite persistence with shareable URLs to the ideal editor.

**Architecture:** Three changes: (1) URL hash for room IDs, (2) localStorage save/load in main.ts, (3) SQLite persistence in relay-worker.js. No MoonBit changes — all TypeScript/JavaScript.

**Tech Stack:** TypeScript, Cloudflare Workers, Durable Objects SQLite

**Design spec:** `docs/plans/2026-03-22-persistence-design.md`

---

## File Map

All paths relative to `examples/ideal/web/`.

| File | Action | Responsibility |
|------|--------|---------------|
| `src/main.ts` | Modify | URL hash routing, localStorage save/load, dynamic room |
| `src/sync.ts` | Modify | Accept room as required parameter |
| `relay-worker.js` | Modify | SQLite schema, persist ops, replay from DB |

---

## Task 1: URL Hash Room Routing

**Files:**
- Modify: `examples/ideal/web/src/main.ts`

- [ ] **Step 1: Add room ID helper functions**

Add at the top of `main.ts` (after the existing constants/imports):

```typescript
const STORAGE_KEY_PREFIX = 'canopy-doc-';
const AGENT_STORAGE_PREFIX = 'canopy-agent-';

function getRoomId(): string {
  const hash = location.hash.slice(1);
  if (hash) return hash;
  const id = crypto.randomUUID
    ? crypto.randomUUID().slice(0, 8)
    : Math.random().toString(36).slice(2, 10);
  history.replaceState(null, '', '#' + id);
  return id;
}
```

- [ ] **Step 2: Use room ID in doMount**

In `doMount()`, at the very beginning (before `const handle = 1`), add:

```typescript
const roomId = getRoomId();
```

Then change `startSync(el, handle, crdt)` at line 211 to pass the room:

```typescript
startSync(el, handle, crdt, roomId);
```

- [ ] **Step 3: Update startSync to accept roomId**

Change the `startSync` function signature:

```typescript
function startSync(el: CanopyEditor, handle: number, crdt: CrdtModule, roomId: string) {
```

And change `syncClient.connect()` to:

```typescript
syncClient.connect(undefined, roomId);
```

- [ ] **Step 4: Update agent ID to use localStorage (per-room, persistent)**

Change `getSessionAgentId()` to use localStorage with room-scoped keys. Replace the `sessionStorage` calls:

```typescript
function getPersistedAgentId(roomId: string): string {
  const key = AGENT_STORAGE_PREFIX + roomId;
  try {
    const existing = localStorage.getItem(key);
    if (existing) return existing;
    const agentId = createAgentId();
    localStorage.setItem(key, agentId);
    return agentId;
  } catch {
    return createAgentId();
  }
}
```

Update `doMount` to use `getPersistedAgentId(roomId)` instead of `getSessionAgentId()`. Also update `loadCrdtModule` — it currently sets `__canopy_agent_id` from `getSessionAgentId()`. Since the room ID isn't known at module load time, keep the session-scoped agent ID for initial creation, but use the per-room one for presence.

- [ ] **Step 5: Verify locally**

Run: `cd examples/ideal/web && npm run dev`
- Visit `http://localhost:5173` → should auto-redirect to `http://localhost:5173/#<random-id>`
- Refresh → same hash persists
- Open in new tab without hash → different hash generated

- [ ] **Step 6: Commit**

```bash
git add examples/ideal/web/src/main.ts
git commit -m "feat(ideal): URL hash room routing with auto-generated IDs"
```

---

## Task 2: localStorage Save/Load

**Files:**
- Modify: `examples/ideal/web/src/main.ts`

- [ ] **Step 1: Add localStorage save function**

Add a debounced save function:

```typescript
let saveTimer: ReturnType<typeof setTimeout> | null = null;

function saveToLocalStorage(handle: number, roomId: string, crdt: CrdtModule) {
  if (saveTimer !== null) clearTimeout(saveTimer);
  saveTimer = setTimeout(() => {
    try {
      const state = crdt.export_all_json(handle);
      localStorage.setItem(STORAGE_KEY_PREFIX + roomId, state);
    } catch (e) {
      console.warn('Failed to save to localStorage:', e);
    }
  }, 1000);
}

function saveNow(handle: number, roomId: string, crdt: CrdtModule) {
  if (saveTimer !== null) {
    clearTimeout(saveTimer);
    saveTimer = null;
  }
  try {
    const state = crdt.export_all_json(handle);
    localStorage.setItem(STORAGE_KEY_PREFIX + roomId, state);
  } catch (e) {
    console.warn('Failed to save to localStorage:', e);
  }
}
```

- [ ] **Step 2: Load from localStorage in doMount**

In `doMount()`, after `const roomId = getRoomId()` and before `el.mount(handle, crdt)`, add:

```typescript
// Restore from localStorage if available
const savedState = localStorage.getItem(STORAGE_KEY_PREFIX + roomId);
if (savedState) {
  try {
    crdt.apply_sync_json(handle, savedState);
  } catch (e) {
    console.warn('Failed to restore from localStorage, removing corrupted entry:', e);
    localStorage.removeItem(STORAGE_KEY_PREFIX + roomId);
  }
}
```

- [ ] **Step 3: Wire save on text change**

In `wireEditorEvents()`, modify the `TEXT_CHANGE` handler to also trigger save. The existing handler calls `clickTrigger('canopy-text-sync-trigger')`. Add save after it:

```typescript
el.addEventListener(CanopyEvents.TEXT_CHANGE, () => {
  clickTrigger('canopy-text-sync-trigger');
  // Debounced save to localStorage
  if (canopyGlobal.__canopy_crdt && canopyGlobal.__canopy_crdt_handle != null) {
    const roomId = location.hash.slice(1);
    if (roomId) {
      saveToLocalStorage(
        canopyGlobal.__canopy_crdt_handle,
        roomId,
        canopyGlobal.__canopy_crdt,
      );
    }
  }
}, { signal });
```

- [ ] **Step 4: Save on beforeunload**

In `startSync()`, the `beforeunload` listener already exists. Add save before disconnect:

```typescript
window.addEventListener('beforeunload', () => {
  // Save document state
  if (canopyGlobal.__canopy_crdt && canopyGlobal.__canopy_crdt_handle != null) {
    const roomId = location.hash.slice(1);
    if (roomId) {
      saveNow(canopyGlobal.__canopy_crdt_handle, roomId, canopyGlobal.__canopy_crdt);
    }
  }
  // ... existing presence cleanup and disconnect ...
});
```

- [ ] **Step 5: Verify locally**

Run: `cd examples/ideal/web && npm run dev`
- Type some text → wait 1s → check `localStorage` in DevTools → `canopy-doc-<hash>` key exists
- Reload page → text is preserved
- Check DevTools Console → no errors

- [ ] **Step 6: Commit**

```bash
git add examples/ideal/web/src/main.ts
git commit -m "feat(ideal): localStorage save/load with debounced writes"
```

---

## Task 3: Dynamic Room in SyncClient

**Files:**
- Modify: `examples/ideal/web/src/sync.ts`

- [ ] **Step 1: Store room name for reconnection**

In `SyncClient`, add a `room` field and use it in `connect` and reconnection:

```typescript
export class SyncClient {
  private ws: WebSocket | null = null;
  private host: HTMLElement;
  private handle: number;
  private crdt: CrdtModule;
  private disposed = false;
  private reconnectDelay = RECONNECT_DELAY_MS;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private lastSentVersion: string;
  private room: string = DEFAULT_ROOM;  // NEW: store room name
```

In `connect()`, store the room:

```typescript
connect(url: string = DEFAULT_WS_URL, room: string = DEFAULT_ROOM): void {
  this.room = room;  // NEW: remember for reconnection
  // ... rest unchanged
}
```

- [ ] **Step 2: Fix scheduleReconnect to use stored room**

Find `scheduleReconnect` in sync.ts. It likely calls `this.connect()` with no room argument (using DEFAULT_ROOM). Change to:

```typescript
private scheduleReconnect() {
  // ... existing delay logic ...
  this.reconnectTimer = setTimeout(() => {
    this.reconnectTimer = null;
    this.connect(undefined, this.room);  // Use stored room, not DEFAULT_ROOM
  }, delay);
}
```

Read the actual method to verify the structure before editing.

- [ ] **Step 3: Verify locally**

Run: `cd examples/ideal/web && npm run dev`
- Visit `http://localhost:5173/#test-room`
- Check WebSocket frame in DevTools → join message contains `room: "test-room"`
- Simulate disconnect → reconnect should rejoin "test-room", not "canopy-room"

- [ ] **Step 4: Commit**

```bash
git add examples/ideal/web/src/sync.ts
git commit -m "feat(ideal): store room name in SyncClient for reconnection"
```

---

## Task 4: SQLite Persistence in Relay Worker

**Files:**
- Modify: `examples/ideal/web/relay-worker.js`

- [ ] **Step 1: Add SQLite schema initialization**

In the `RelayRoom` constructor, initialize the SQLite table:

```javascript
constructor(state, env) {
  this.state = state;
  this.env = env;
  this.clients = new Set();
  // Initialize SQLite schema for persistent operation storage
  this.state.storage.sql.exec(`
    CREATE TABLE IF NOT EXISTS operations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      data TEXT NOT NULL
    )
  `);
}
```

Remove `this.ops = [];` — SQLite replaces the in-memory array.

- [ ] **Step 2: Replace in-memory replay with SQLite query**

In the `"join"` case, replace `this.ops` replay with SQLite query:

```javascript
case "join": {
  if (joined) break;
  joined = true;
  this.clients.add(ws);

  // Replay stored ops from SQLite
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

- [ ] **Step 3: Persist operations to SQLite**

In the `"operation"` case, replace `this.ops.push(op)` with SQLite insert:

```javascript
case "operation": {
  if (!joined) {
    ws.send(JSON.stringify({ type: "error", message: "Not joined" }));
    break;
  }

  const op = msg.op;

  // Persist to SQLite
  this.state.storage.sql.exec(
    "INSERT INTO operations (data) VALUES (?)", op
  );

  // Broadcast to all other clients
  const relay = JSON.stringify({ type: "operation", op });
  for (const peer of this.clients) {
    if (peer !== ws) {
      try {
        peer.send(relay);
      } catch {
        this.clients.delete(peer);
      }
    }
  }
  break;
}
```

- [ ] **Step 4: Update reset handler**

In the `"reset"` case, clear SQLite instead of in-memory array:

```javascript
case "reset": {
  this.state.storage.sql.exec("DELETE FROM operations");
  break;
}
```

- [ ] **Step 5: Remove MAX_OPS constant**

Delete `const MAX_OPS = 10_000;` — SQLite handles storage without in-memory limits.

- [ ] **Step 6: Test with wrangler dev**

Run: `cd examples/ideal/web && npx wrangler dev --config wrangler-relay.toml`
- This starts a local Cloudflare Workers dev server with SQLite
- If wrangler is not installed: `npm install -D wrangler` first
- Connect from the frontend dev server → verify operations are stored and replayed

- [ ] **Step 7: Commit**

```bash
git add examples/ideal/web/relay-worker.js
git commit -m "feat(ideal): SQLite persistence in relay worker Durable Object"
```

---

## Task 5: Integration Testing

- [ ] **Step 1: End-to-end test flow**

Start both dev servers:
```bash
# Terminal 1: frontend
cd examples/ideal/web && npm run dev

# Terminal 2: relay (if using Cloudflare Workers)
cd examples/ideal/web && npx wrangler dev --config wrangler-relay.toml
```

Test scenarios:
1. **localStorage persistence:** Type text → reload → text preserved
2. **URL sharing:** Copy URL with hash → open in incognito → document loads from server
3. **New document:** Visit without hash → new room created → empty (sample text from init)
4. **Server persistence:** Type text → close all tabs → reopen URL → text restored from SQLite
5. **Collaboration:** Two tabs with same hash → edits sync in real-time
6. **Corrupted localStorage:** Manually set `canopy-doc-<hash>` to invalid JSON → reload → graceful fallback, no crash

- [ ] **Step 2: Commit any fixes from testing**

```bash
git add -A
git commit -m "fix(ideal): adjustments from integration testing"
```

---

## Dependency Graph

```text
Task 1 (URL hash routing)
    ↓
Task 2 (localStorage save/load)
    ↓
Task 3 (Dynamic room in SyncClient)
    ↓
Task 4 (SQLite in relay worker)
    ↓
Task 5 (Integration testing)
```

All tasks are sequential.

---

## Notes for Implementer

1. **Module load timing:** `loadCrdtModule()` sets `__canopy_agent_id` from `getSessionAgentId()` BEFORE the module loads. The MoonBit `init_model` reads this to create the editor. We can't change the agent ID after creation. Keep the existing session-scoped ID for editor creation, use the per-room ID for presence display only.

2. **`doMount` is the integration point.** Everything happens here: room ID resolution, localStorage restore, mount, sync start. The order matters: restore → mount → sync.

3. **`crdt.apply_sync_json(1, state)` is safe to call before mount.** The CRDT editor (handle = 1) is created during MoonBit module init. `apply_sync_json` merges operations into the existing state — it doesn't need the UI mounted.

4. **`export_all_json(1)` returns the full CRDT operation history.** For small documents this is fine (< 100KB). For very large documents (100k+ operations), this could be slow or hit localStorage limits. The design spec defers compaction to future work.

5. **Relay worker SQLite API:** Cloudflare Durable Objects with `new_sqlite_classes` in wrangler config get `this.state.storage.sql.exec(query, ...params)` which returns a cursor. See [Cloudflare docs on Durable Object SQL API](https://developers.cloudflare.com/durable-objects/api/sql-storage/).

6. **Local dev without relay:** If wrangler isn't set up, the localStorage layer works independently. The sync layer gracefully handles connection failures (reconnect with backoff). Test localStorage first, then add relay testing.

7. **`beforeunload` is already registered** in `startSync()`. Don't register it twice — extend the existing handler to also save localStorage state.
