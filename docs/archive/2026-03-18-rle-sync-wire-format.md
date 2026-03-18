# RLE-Aware Sync Wire Format

**Status:** Completed.
**Date:** 2026-03-18
**PRs:** [event-graph-walker#8](https://github.com/dowdiness/event-graph-walker/pull/8), [crdt#35](https://github.com/dowdiness/canopy/pull/35)

---

## Problem

`export_all` decompressed N OpRuns into N individual Ops (20-31x slower than pre-RLE baseline). The JSON payload was also bloated — each op repeated agent ID, origin_right, etc.

## Solution

Changed `SyncMessage` from `Array[Op]` to `Array[OpRun]` with custom JSON serialization.

**Two message formats coexist:**
- **Real-time:** Individual `Operation` objects per keystroke (unchanged)
- **Batch:** `SyncMessage` with `Array[OpRun]` for `export_all`, `export_since`, late-join sync, and undo/redo export

## What Was Implemented

### MoonBit (completed)

1. **Custom `ToJson`/`FromJson` for `OpRun` and `OpRunContent`** (`core/op_run_json.mbt`)
   - `Inserts(Array[Char])` serializes as `{"Inserts": "hello"}`
   - `Deletes`/`Undeletes` serialize as strings
   - Validation: rejects `count <= 0` and Inserts length mismatch

2. **`SyncMessage` uses `Array[OpRun]`** (`text/sync.mbt`)
   - `export_all`: zero-copy, copies runs directly from Rle
   - `export_since`: re-compresses individual ops via `Rle::append`
   - `apply`: expands runs to individual Ops for `merge_remote`

3. **Legacy backwards compatibility** (`text/sync.mbt`)
   - `from_json_string` reads `"runs"` first, falls back to `"ops"` (wraps as singleton OpRuns)

4. **`OpLog::get_all_runs`** (`oplog/oplog.mbt`) — zero-copy run export

5. **Docs** — `JS_INTEGRATION.md` updated with new schema

### Valtio/WebSocket — No changes needed

The WebSocket relay (`ws-server.ts`) and clients (`egwalker_api_sync.ts`) use a separate protocol that sends individual `Operation` objects via `apply_remote_op`. They never call `export_all_json`/`apply_sync_json` or reference `SyncMessage`. The `SyncMessage` wire format change is transparent to them.

## Wire Format

```json
{
  "runs": [
    {"start_lv":0,"agent":"alice","start_seq":0,"content":{"Inserts":"hello"},"parents":[],"origin_left":null,"origin_right":null,"count":5}
  ],
  "heads": [{"agent":"alice","seq":4}]
}
```

For 5-char typing: 5 objects → 1 object. Legacy `"ops"` format accepted on receive.

## Performance Results

| Benchmark | Before | After |
|---|---|---|
| export_all (100 ops) | 4.24 µs | **0.09 µs** (47x faster) |
| export_all (1000 ops) | 49.88 µs | **0.10 µs** (499x faster) |

Both are faster than the original pre-RLE baseline (0.21µs / 1.60µs).
