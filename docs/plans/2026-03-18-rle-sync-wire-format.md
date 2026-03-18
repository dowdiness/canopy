# RLE-Aware Sync Wire Format

**Status:** Approved
**Date:** 2026-03-18

---

## Problem

`export_all` decompresses N OpRuns into N individual Ops (20-31x slower than pre-RLE baseline). The JSON payload is also bloated — each op repeats agent ID, origin_right, etc.

## Architecture

**Two message formats coexist:**
- **Real-time:** Individual `Operation` objects per keystroke (unchanged)
- **Batch:** New `SyncMessage` with `Array[OpRun]` for `export_all`, `export_since`, late-join sync, and undo/redo export

## MoonBit Changes

### 1. Add serialization to OpRun and OpRunContent

Add `derive(ToJson, FromJson)` to `OpRun` and `OpRunContent`.

`OpRunContent::Inserts(Array[Char])` serializes as `{"Inserts": "hello"}` (join chars to string for JSON compactness, parse back to `Array[Char]` on deserialize).

`Deletes` / `Undeletes` serialize as `"Deletes"` / `"Undeletes"`.

### 2. Change SyncMessage storage

Change `SyncMessage.ops` from `Array[Op]` to `Array[OpRun]`.

- `export_all`: returns `self.operations.iter().collect()` — no decompression
- `export_since`: `diff_and_collect` returns `Array[Op]`, wrap each as `OpRun::from_op`
- `apply`: receives `Array[OpRun]`, expands to individual Ops for `merge_remote`

### 3. Update FFI (`crdt.mbt`)

`export_all_json` / `apply_sync_json` use the new format automatically via `SyncMessage::to_json_string` / `from_json_string`.

## Wire Format Change

**Before:**
```json
{
  "ops": [
    {"lv":0,"agent":"alice","seq":0,"content":{"Insert":"h"},"parents":[],"origin_left":null,"origin_right":null},
    {"lv":1,"agent":"alice","seq":1,"content":{"Insert":"e"},"parents":[{"agent":"alice","seq":0}],...}
  ],
  "heads": [{"agent":"alice","seq":4}]
}
```

**After:**
```json
{
  "runs": [
    {"start_lv":0,"agent":"alice","start_seq":0,"content":{"Inserts":"hello"},"parents":[],"origin_left":null,"origin_right":null,"count":5}
  ],
  "heads": [{"agent":"alice","seq":4}]
}
```

For 5-char typing: 5 objects → 1 object.

## Valtio/WebSocket Changes

### 4. ws-server.ts

Update `'sync'` message handler to use `runs` field instead of `ops` for late-join sync. The server stores runs instead of individual ops.

### 5. egwalker_api.ts / egwalker_api_stub.ts

Update batch sync code to send/receive `runs` format. Real-time `'operation'` messages remain unchanged — still individual ops.

### 6. Real-time operation messages

Unchanged. Individual keystroke operations continue using the existing `Operation` format.

## What Stays the Same

- Real-time keystroke sync (individual `Operation` messages via WebSocket)
- `merge_remote` internal API (still receives `Array[Op]` — expand from OpRun at apply boundary)
- All CRDT semantics
- Undo/redo behavior

## Expected Performance

- `export_all (100 ops)`: ~4µs → ~0.2µs (array copy of runs, no decompression)
- `export_all (1000 ops)`: ~50µs → ~0.5µs
- Network payload: ~50-80% smaller for batch messages

## Testing

- Roundtrip: serialize OpRun → JSON → deserialize → verify fields match
- Sync: export_all from A, apply on B, verify convergence
- Mixed: real-time ops + batch sync interleave correctly
- Late-join: new peer receives compressed runs, applies correctly

## Implementation Order

1. Add `ToJson`/`FromJson` to `OpRunContent` and `OpRun` (custom, not derived — need string representation for `Inserts`)
2. Change `SyncMessage` from `Array[Op]` to `Array[OpRun]`
3. Update `export_all`, `export_since`, `apply` in `sync.mbt`
4. Update `to_json_string` / `from_json_string`
5. Update `crdt.mbt` FFI (should be transparent if SyncMessage API unchanged)
6. Update tests
7. Update `ws-server.ts` — batch/sync message format
8. Update `egwalker_api.ts` / `egwalker_api_stub.ts` — batch sync
9. Update `JS_INTEGRATION.md`
