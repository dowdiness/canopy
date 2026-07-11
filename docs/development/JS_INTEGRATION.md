# JavaScript Integration Guide

This document describes how to integrate the MoonBit CRDT editor into a JavaScript/Web environment.

## Overview

The browser integration uses the generated JavaScript build, not WebAssembly. The `crdt.mbt` file defines the JavaScript FFI exposed through the JS build output.

The canonical browser example lives under `examples/web/`, where the Vite plugin exposes three per-page virtual modules: `@moonbit/crdt-lambda` (at `_build/js/release/build/dowdiness/canopy/ffi/lambda/lambda.js`), `@moonbit/crdt-json` (at `_build/js/release/build/dowdiness/canopy/ffi/json/json.js`), and `@moonbit/crdt-markdown` (at `_build/js/release/build/dowdiness/canopy/ffi/markdown/markdown.js`). The lambda module is the closest replacement for the old monolithic `@moonbit/crdt`.

### Loading the JavaScript Module

Refer to the `examples/web/` directory for a complete integration example using Vite.

```ts
import * as crdt from '@moonbit/crdt-lambda';

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
make build-js
```

## Editor API (FFI)

All FFI functions take a `handle` as their first argument. The implementation now keeps a real handle-to-editor registry, so multiple JS-created editors can coexist in the same module instance.

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
- `apply_sync_json(handle: number, sync_json: string): void`
- `get_version_json(handle: number): string`

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
5.  **Error Handling:** the root FFI is the string/JSON flattening edge. Typed
    internal errors such as `TreeEditError` are converted to strings there.
    Example: `apply_tree_edit_json(...)` returns `"ok"` or `"error: <message>"`.
    Integration code should still handle generated-module/runtime exceptions,
    but ordinary editor failures are expected to arrive through these string
    return values rather than raw MoonBit error objects.
