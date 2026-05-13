# API Reference

This document provides a high-level reference for the core MoonBit APIs in the `crdt` project.

## SyncEditor (`@editor.SyncEditor`)

The `SyncEditor` is the primary facade for the editor application, integrating the CRDT document, incremental parser, and undo manager.

### Construction
- `SyncEditor::new_lambda(agent_id : String, capture_timeout_ms? : Int = 500) -> SyncEditor[@ast.Term]`
  Creates the lambda-calculus editor facade used by the current apps and tests.

### Text Operations

> All `Int` positions in this section are **UTF-16 code-unit offsets** at the
> editor layer. Cursor-bearing editor APIs maintain a UAX #29 grapheme-cluster
> boundary invariant with `@moji`. Before mutating the eg-walker text facade,
> the editor converts UTF-16 offsets to eg-walker *item-space*
> (visible-character count). The two units coincide for ASCII and diverge for
> non-ASCII input; see [Position Units](#position-units).

- `insert(text : String) -> Unit raise`
  Snaps the current cursor to the previous grapheme boundary, inserts text at
  that position, then snaps the cursor to the next grapheme boundary after the
  inserted text.
- `delete() -> Bool`
  Deletes the character at the current cursor position (forward delete).
  Deletes the next UAX #29 grapheme cluster and leaves the cursor on a
  grapheme boundary.
- `backspace() -> Bool`
  Deletes the previous UAX #29 grapheme cluster and leaves the cursor on a
  grapheme boundary.
- `move_cursor(position : Int) -> Unit`
  Moves the cursor to the specified absolute position. `position` is a
  UTF-16 code-unit offset clamped to `[0, doc.text().length()]`, then snapped
  backward to the nearest grapheme boundary.
- `move_cursor_left_grapheme() -> Unit`
  Moves left by one grapheme cluster.
- `move_cursor_right_grapheme() -> Unit`
  Moves right by one grapheme cluster.
- `move_cursor_left_word() -> Unit`
  Moves left to the previous raw UAX #29 word boundary.
- `move_cursor_right_word() -> Unit`
  Moves right to the next raw UAX #29 word boundary.
- `get_text() -> String`
  Returns the full document text.
- `get_cursor() -> Int`
  Returns the current cursor position as a UTF-16 code-unit offset. The value
  is maintained as a grapheme boundary by the editor layer.
- `set_text(new_text : String) -> Unit`
  Replaces the entire document text (useful for initialization).
  Routes through `dowdiness/text_change::compute_text_change`, whose prefix
  and suffix walks compare full grapheme clusters.

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

## Text Diff (`@editor.text_diff`)

- `compute_edit(old_text : String, new_text : String) -> @loom_core.Edit`
  Computes a parser `Edit` describing the splice that turns `old_text` into
  `new_text`. The returned `start`, `delete_len`, and inserted-length fields
  are all in **UTF-16 code units**. The prefix/suffix trimming is
  grapheme-aware via `@moji.grapheme_boundaries`, so non-ASCII diffs do not
  slice surrogate pairs or combining clusters.

## Position Units

> **Status (2026-05-13):** `moji` shipped in canopy [#251][canopy251] and
> the editor layer now keeps cursor and local splice endpoints on UAX #29
> grapheme boundaries. The public unit remains a UTF-16 code-unit offset,
> not a grapheme ordinal.

[canopy251]: https://github.com/dowdiness/canopy/pull/251

Three position units appear in the text-editing surface:

| Layer | Unit (today) | What it counts |
|---|---|---|
| Editor cursor and splice APIs (`SyncEditor::*`) | UTF-16 code-unit offset, snapped to a UAX #29 grapheme boundary | Non-BMP code points still occupy 2 code units; combining marks occupy 1 code unit but are not exposed as cursor stops inside a cluster. |
| Text diff (`@editor.text_diff`, `dowdiness/text_change`) | UTF-16 code-unit offsets aligned to grapheme boundaries | The minimal splice fields still use code-unit lengths, but prefix/suffix comparison walks full grapheme clusters. |
| eg-walker text facade (`@text.Pos`, `TextState::len` via `visible_count()`) | Item-space offset | One slot per atomic content `Op`. The editor converts UTF-16 offsets to item-space before calling `@text.Pos` / `@text.Range`. |

No `GraphemeOffset` opaque type exists today. Keep treating public editor
positions as UTF-16 code-unit offsets that are expected to lie on grapheme
boundaries.

### Non-ASCII Status

The local editor text paths are grapheme-aware after [#251][canopy251] and
the follow-up parser/undo fixes for #216:

| Inputs | Status |
|---|---|
| BMP combining marks (NFD `"e\u{0301}"`) | **Fixed at the editor layer.** Cursor movement, `backspace`, local splice snapping, and text diff operate on the full grapheme cluster. |
| Surrogate-pair inputs (emoji, ZWJ family, regional indicator) through `SyncEditor` | **Fixed for local mutation and parser-recovery paths.** `editor/sync_editor_text_wbtest.mbt` covers non-BMP insert, `set_text`, RI re-pairing, and ZWJ cluster fusion. |

Callers should still treat public editor positions as UTF-16 code-unit offsets
and prefer editor APIs that snap or validate grapheme boundaries instead of
constructing offsets arithmetically across non-ASCII text.

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
