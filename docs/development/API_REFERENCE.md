# API Reference

This document provides a high-level reference for the core MoonBit APIs in the `crdt` project.

## SyncEditor (`@editor.SyncEditor`)

The `SyncEditor` is the primary facade for the editor application, integrating the CRDT document, incremental parser, and undo manager.

### Construction
- `SyncEditor::new_lambda(agent_id : String, capture_timeout_ms? : Int = 500) -> SyncEditor[@ast.Term]`
  Creates the lambda-calculus editor facade used by the current apps and tests.

### Text Operations

> All `Int` positions in this section are **UTF-16 code-unit offsets** at the
> editor layer. Forwarded into the eg-walker text facade they address
> *item-space* (visible-character count). The two coincide for ASCII and
> diverge for non-ASCII inputs in known, bimodal ways. See
> [Position Units](#position-units) for the full contract and sharp edges.

- `insert(text : String) -> Unit raise`
  Inserts text at the current cursor position. The cursor is advanced by
  `text.length()` (code units), which for non-ASCII input may not be a
  grapheme boundary.
- `delete() -> Bool`
  Deletes the character at the current cursor position (forward delete).
  Operates on a single code-unit slot at the editor layer.
- `backspace() -> Bool`
  Deletes the character before the current cursor position. Removes a
  single code-unit slot — see [Position Units](#position-units) for the
  combining-mark and surrogate-pair edges.
- `move_cursor(position : Int) -> Unit`
  Moves the cursor to the specified absolute position. `position` is a
  UTF-16 code-unit offset clamped to `[0, doc.len()]`. The future external
  contract is a grapheme-cluster offset; the unit will be tightened (and
  may be wrapped in a `GraphemeOffset` opaque type — name reserved) once
  the **moji** UAX #29 dependency is available.
- `get_text() -> String`
  Returns the full document text.
- `get_cursor() -> Int`
  Returns the current cursor position as a UTF-16 code-unit offset.
  Same future direction as `move_cursor`.
- `set_text(new_text : String) -> Unit`
  Replaces the entire document text (useful for initialization).
  Routes through `text_diff::compute_edit`; see [Text Diff](#text-diff-editortext_diff).

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
  are all in **UTF-16 code units** — `compute_edit` operates on `String`
  arguments directly and does not pass through eg-walker, so it does not
  inherit the typed-rejection behavior described in
  [Position Units](#position-units). Non-ASCII inputs (notably surrogate
  pairs and BMP combining marks) can produce splices that are not aligned
  to grapheme boundaries; this is pinned by xfail tests in
  `editor/text_diff_test.mbt` and resolved as part of issue #216 once
  **moji** is available.

## Position Units

> **Status (2026-05-09):** this section documents the *current* contract,
> not the target one. Tracked at canopy [#216][issue-216]. The editor's
> intended external contract is grapheme-cluster offsets; landing it is
> blocked on the **moji** UAX #29 library.

[issue-216]: https://github.com/dowdiness/canopy/issues/216

Three position units appear in the text-editing surface:

| Layer | Unit (today) | What it counts |
|---|---|---|
| Editor (`SyncEditor::*`, `text_diff::compute_edit`) | UTF-16 code-unit offset | One slot per `String.length()` increment. Non-BMP code points count as 2; combining marks count as 1. |
| eg-walker text facade (`@text.Pos`, `TextState::len` via `visible_count()`) | Item-space offset | One slot per atomic content `Op`. Post eg-walker [#31][egw31] / canopy [#240][canopy240], inputs are split into per-codepoint atomic Ops, so item-space is closely aligned with code-point count. |
| Future external contract | Grapheme-cluster offset | One slot per UAX #29 grapheme cluster. Not yet implemented. |

[egw31]: https://github.com/dowdiness/event-graph-walker/issues/31
[canopy240]: https://github.com/dowdiness/canopy/pull/240

The editor advances its cursor by `text.length()` (code units) and forwards
the resulting `Int` to the eg-walker facade, whose internal addressing is
item-space. The two coincide for ASCII; for non-ASCII inputs they diverge
along the failure modes below.

A future `GraphemeOffset` opaque type may replace `Int` at the editor's
public boundary once **moji** lands. The name is **reserved** — no such
type exists today.

### Known sharp edges (non-ASCII inputs)

The non-ASCII failure surface is **bimodal** — two distinct paths, two
distinct failure modes. Both are pinned by xfail tests added in
[#239][canopy239]:

| Inputs | Failure mode |
|---|---|
| Surrogate-pair (emoji, ZWJ family, regional indicator) | **Typed rejection** at the CRDT boundary. After eg-walker [#31][egw31] / canopy [#240][canopy240], the eg-walker text facade splits inputs into per-codepoint atomic Ops and rejects mid-surrogate positions with `TextError::SyncFailed(MalformedContent { ... })` rather than aborting via `String::sub`. The editor layer does not yet round-trip these inputs cleanly: `cursor + text.length()` advancement after `insert("😀")` can land between the high and low surrogate from the editor's point of view, and `backspace` removes only one code unit. |
| BMP combining marks (NFD `"e\u{0301}"`) | **Silent corruption.** `backspace` deletes only the trailing combining mark; `text_diff::compute_edit` reports a 1-code-unit delete. No abort, no rejection — the output is wrong. This path is unaffected by eg-walker [#31][egw31] / canopy [#240][canopy240]; only editor-layer grapheme awareness closes it. |

The grapheme-aware fix at the editor layer (Step 2 of [#216][issue-216])
is what closes both edges; it is blocked on **moji**. Until then, callers
should treat editor positions as UTF-16 code-unit offsets and avoid
constructing positions arithmetically across non-ASCII boundaries.

[canopy239]: https://github.com/dowdiness/canopy/pull/239

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
