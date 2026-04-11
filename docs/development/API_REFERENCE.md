# API Reference

This document provides a high-level reference for the core MoonBit APIs in the `crdt` project.

## SyncEditor (`@editor.SyncEditor`)

The `SyncEditor` is the primary facade for the editor application, integrating the CRDT document, incremental parser, and undo manager.

### Construction
- `SyncEditor::new_lambda(agent_id : String, capture_timeout_ms? : Int = 500) -> SyncEditor[@ast.Term]`
  Creates the lambda-calculus editor facade used by the current apps and tests.

### Text Operations
- `insert(text : String) -> Unit raise`
  Inserts text at the current cursor position.
- `delete() -> Bool`
  Deletes the character at the current cursor position (forward delete).
- `backspace() -> Bool`
  Deletes the character before the current cursor position.
- `move_cursor(position : Int) -> Unit`
  Moves the cursor to the specified absolute position.
- `get_text() -> String`
  Returns the full document text.
- `get_cursor() -> Int`
  Returns the current cursor position.
- `set_text(new_text : String) -> Unit`
  Replaces the entire document text (useful for initialization).

### Undo/Redo
- `insert_and_record(text : String, timestamp_ms : Int) -> Unit raise`
- `delete_and_record(timestamp_ms : Int) -> Bool`
- `backspace_and_record(timestamp_ms : Int) -> Bool`
- `undo() -> Bool`
- `redo() -> Bool`
- `can_undo() -> Bool`
- `can_redo() -> Bool`

### Synchronization
- `export_all() -> @text.SyncMessage`
  Exports all operations for initial synchronization.
- `export_since(peer_version : @text.Version) -> @text.SyncMessage`
  Exports operations created since the specified peer version.
- `apply_sync(msg : @text.SyncMessage) -> Unit`
  Applies a synchronization message received from a peer.
- `get_version() -> @text.Version`
  Returns the current document version.

### AST & Parsing
- `get_ast() -> @ast.Term`
  Returns the current parsed AST.
- `get_ast_pretty() -> String`
  Returns a pretty-printed string of the AST.
- `get_errors() -> Array[String]`
  Returns a list of parse errors.
- `is_parse_valid() -> Bool`
  Returns true if the current text parses without errors.

### Projectional Editing
- `delete_node(node_id : @core.NodeId, timestamp_ms : Int) -> Result[Unit, TreeEditError]`
  Deletes a node by round-tripping through the text CRDT.
- `commit_edit(node_id : @core.NodeId, new_text : String, timestamp_ms : Int) -> Result[Unit, TreeEditError]`
  Commits an inline text edit on a node.
- `move_node(source_id : @core.NodeId, target_id : @core.NodeId, position : @core.DropPosition, timestamp_ms : Int) -> Result[Unit, TreeEditError]`
  Moves a node via drag-and-drop.

### WebSocket / Wire Protocol
- `decode_message(data : Bytes) -> SyncMessage?`
  Compatibility decoder that drops malformed frames by returning `None`.
- `decode_message_result(data : Bytes) -> Result[SyncMessage, ProtocolError]`
  Typed decoder for callers that need explicit protocol failure reasons.
- `ws_on_message(data : Bytes) -> Unit`
  Applies incoming wire data. Malformed protocol/input frames are intentionally
  dropped as resilience policy; typed decode helpers exist when diagnostics are
  needed outside the hot path.

## EphemeralStore (`@editor.EphemeralStore`)

Manages transient state like peer cursors and presence information.

- `set(key : String, value : EphemeralValue) -> Unit raise EphemeralError`
  Sets a value for a specific key (usually a peer ID).
- `get(key : String) -> EphemeralValue?`
  Retrieves a value for a key.
- `delete(key : String) -> Unit raise EphemeralError`
  Removes a key from the store.
- `encode_all() -> Bytes`
  Encodes all non-expired state for broadcasting.
- `apply(data : Bytes) -> Unit raise EphemeralError`
  Applies an encoded update from a peer.
- `remove_outdated() -> Unit`
  Prunes expired entries based on `timeout_ms`.

## Editor Error Types

The `editor` package now uses typed boundary errors rather than raw strings for
its main internal error surfaces:

- `EphemeralError`
- `TreeEditError`
- `ProtocolError`

Each exposes `.message()` for conversion at UI/FFI edges.

Low-level sync/document failures still come from `@text.TextError` and should
remain owned by the text layer.

## JavaScript FFI Edge

The root JS FFI remains a string/JSON boundary. Internal typed errors are
flattened there rather than earlier in the call stack.

Examples:

- `apply_tree_edit_json(handle, op_json, timestamp_ms) -> "ok" | "error: ..."`
- `apply_sync_json(handle, sync_json) -> String`
- `export_all_json(handle) -> String`

See [JS Integration](JS_INTEGRATION.md) for the browser-facing surface.
