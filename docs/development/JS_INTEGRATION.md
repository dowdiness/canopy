# JavaScript Integration Guide

This document describes how to integrate the MoonBit CRDT editor into a JavaScript/Web environment.

## Overview

The editor is compiled to WebAssembly (WASM). The `crdt.mbt` file defines the JavaScript FFI, which uses a "handle-based" system for managing `SyncEditor` instances.

### Loading the WASM Module

Refer to the `examples/web/` directory for a complete integration example using Vite.

```javascript
// Basic loading pattern
import init, { create_editor, get_text, insert_and_record } from './crdt.js';

async function setup() {
  await init(); // Initialize the WASM module
  const handle = create_editor("agent-1"); // Create a new editor for "agent-1"
  const text = get_text(handle);
  console.log("Initial text:", text);
}
```

## Editor API (FFI)

All FFI functions take a `handle` (currently always `1` in the MVP) as their first argument.

### Initialization
- `create_editor(agent_id: string): number`
- `create_editor_with_undo(agent_id: string, capture_timeout_ms: number): number`

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
4.  **Error Handling:** FFI calls that might fail are wrapped in `try/catch` in MoonBit; however, ensure your JS integration also handles potential WASM runtime errors.
