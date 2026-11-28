# JavaScript Integration Guide

This document describes how to integrate the MoonBit CRDT editor into a JavaScript/Web environment.

## Overview

The browser integration uses the generated JavaScript build, not WebAssembly. The `crdt.mbt` file defines the JavaScript FFI exposed through the JS build output.

The canonical browser example lives under `apps/web/`, where the Vite plugin exposes three per-page virtual modules: `@moonbit/crdt-lambda` (at `_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js`), `@moonbit/crdt-json` (at `_build/js/release/build/dowdiness/canopy/ffi/json/json.js`), and `@moonbit/crdt-markdown` (at `_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.js`). The lambda module is the closest replacement for the old monolithic `@moonbit/crdt`.

### Loading the JavaScript Module

Refer to the `apps/web/` directory for a complete integration example using Vite.

```ts
import * as raw from '@moonbit/crdt-lambda';
import { adaptMoonBitModule } from '@canopy/editor-adapter/moonbit-result';

const crdt = adaptMoonBitModule(raw, {
  createFunctions: ['create_editor', 'create_editor_with_undo'],
  destroyFunctions: ['destroy_editor'],
  tryDestroyFunctions: ['try_destroy_editor'],
});

function setup() {
  const handle = crdt.create_editor("agent-1");
  const text = crdt.get_text(handle);
  console.log("Initial text:", text);

  return () => {
    crdt.destroy_editor(handle);
  };
}
```

For local development, build the JS artifacts first:

```bash
just build-js
```

## Editor API (FFI)

All FFI functions take a `handle` as their first argument. The implementation now keeps a real handle-to-editor registry, so multiple JS-created editors can coexist in the same module instance.

The signatures below describe the adapted host API. Fallible raw MoonBit
exports can return structural `Result` objects; the adapter unwraps successes
and throws `CanopyHostError` on failure. In particular, `get_text` is now
fallible when the document projection is unavailable. Do not treat a raw
`Result` as a string or replace a failed read with empty/stale text.

This also applies to `save_file`, `json_get_text`, `json_get_errors`,
`markdown_get_text`, `markdown_export_text`, `markdown_compute_view_patches_json`,
`get_diagnostics_json`, `get_pattern_matches_json`, and
`apply_ast_grep_results_json`. An adapter failure quarantines an owned handle;
do not continue operating on that handle.

### Initialization
- `create_editor(agent_id: string): number`
- `create_editor_with_undo(agent_id: string, capture_timeout_ms: number): number`
- `destroy_editor(handle: number): void`

### Text Operations
- `get_text(handle: number): string`
- `set_text(handle: number, new_text: string): void`
- `insert_and_record(handle: number, text: string, timestamp_ms: number): void`
- `delete_and_record(handle: number, timestamp_ms: number): boolean`
- `backspace_and_record(handle: number, timestamp_ms: number): boolean`

### Synchronization
- `export_all_json(handle: number): string`
- `export_since_json(handle: number, peer_version_json: string): string`
- `apply_sync_json(handle: number, sync_json: string): string`
- `get_version_json(handle: number): string`

`apply_sync_json` returns `"ok"` or a JSON error object with `history_advanced`
and `projection_available` booleans. An error does not imply rollback. Refresh
the host from accepted history when both fields are true, before handling the
error; never read an unavailable projection as a fallback. Preserve persisted
recovery data after partial acceptance or a host exception rather than assuming
the saved history was corrupt.

### Presence & Ephemeral State
- `ephemeral_encode_all(handle: number): Uint8Array`
- `ephemeral_apply(handle: number, data: Uint8Array): void`
- `ephemeral_set_presence(handle: number, name: string, color: string): void`
- `ephemeral_set_presence_with_selection(handle: number, name: string, color: string, start: number, end: number): void`
- `ephemeral_get_peer_cursors_json(handle: number): string`

## JSON Data Schemas

### `SyncMessage`
Used for transporting CRDT operations between peers. Operations are RLE-compressed as `OpRun` arrays.

```json
{
  "runs": [
    {
      "start_lv": 0,
      "agent": "agent-1",
      "start_seq": 0,
      "content": {"Inserts": "hello"},
      "parents": [],
      "origin_left": null,
      "origin_right": null,
      "count": 5
    }
  ],
  "heads": [
    {"agent": "agent-1", "seq": 4}
  ]
}
```

Each run represents multiple consecutive operations from the same agent. For linear typing, 1000 characters compress to a single run. `content` is one of:
- `{"Inserts": "text"}` — concatenated inserted characters
- `"Deletes"` — count consecutive delete ops
- `"Undeletes"` — count consecutive undelete ops

### `PeerCursor` (via `ephemeral_get_peer_cursors_json`)
```json
[
  {
    "peer_id": "agent-2",
    "cursor": 12,
    "name": "Alice",
    "color": "#ff0000",
    "selection": [10, 15] 
  }
]
```

## Best Practices

1.  **Agent IDs:** Each user or tab should have a unique, persistent `agent_id` for the duration of a session to avoid CRDT conflicts.
2.  **Timestamps:** Provide accurate `timestamp_ms` from `Date.now()` for undo/redo tracking.
3.  **Synchronization Loop:**
    - Listen for local changes and broadcast `export_since_json` deltas to peers via WebSockets/WebRTC.
    - Periodically call `ephemeral_remove_outdated` to prune disconnected peers.
4.  **Lifecycle:** Call `destroy_editor(handle)` when an editor is permanently torn down so the JS module can release it from the handle registry.
5.  **Error Handling:** domain-operation envelopes such as
    `apply_tree_edit_json(...)` still return `"ok"` or `"error: <message>"`.
    Generated fallible exports use a separate `Result`/exception boundary.
    Use the adapter and handle `CanopyHostError` at the owning editor/session
    boundary; a quarantined handle must not receive further editor operations.
