# editor

Language-agnostic CRDT editor engine that combines text storage, undo/redo, reactive parsing, ephemeral presence, WebSocket sync, and view-update diffing into a single `SyncEditor[T]` host.

`SyncEditor[T]` is parameterized on the language's AST type `T`. Each language's `companion` subpackage (`lang/lambda/companion`, `lang/json/companion`, `lang/markdown/companion`) constructs one via `SyncEditor::new_generic`, passing a parser factory and memo builder. The FFI packages then wrap the result and export concrete functions to JavaScript.

## Public API

- `SyncEditor[T]` — core struct holding `TextState`, `UndoManager`, reactive `Parser[T]`, ephemeral hub, and WebSocket state
- `SyncEditor::new_generic` — generic constructor; language packages call this, not FFI
- `compute_view_patches` / `compute_pretty_patches` — incremental diff of `ProjNode` tree into `ViewPatch` operations for the frontend
- `EphemeralHub` — multi-peer cursor and presence state (encode/apply/broadcast)
- `SyncMessage` / `encode_message` / `decode_message` — binary protocol framing for CRDT ops, sync requests, and room control
- `ViewUpdateState` — snapshot used to compute minimal `ViewPatch` sequences
- `LanguageCapabilities[T]` — per-language hooks wired at construction time (text-edit handler, tree-edit handler, pretty-print, etc.)

## Consumers

- `ffi/lambda`, `ffi/json`, `ffi/markdown` — each wraps a `SyncEditor` behind an integer handle and exports JS-callable functions
- `lang/*/companion` — construct `SyncEditor` instances via `new_*_editor` and implement the `LanguageCapabilities` hooks
- `lang/lambda` — facade that re-exports `new_lambda_editor` and other companion entry points (the `json`/`markdown` facades currently re-export nothing; consumers reach into the subpackages directly)
- `cmd/main` — the native CLI demo uses the lower-level `Editor` type (not `SyncEditor`)

## Dependencies

- `dowdiness/canopy/core` — `ProjNode`, `SourceMap`, `NodeId`, `GenericTreeOp`
- `dowdiness/canopy/protocol` — `ViewPatch`, `ViewNode`, `UserIntent`
- `dowdiness/event-graph-walker/text` + `undo` + `history` — CRDT text state and undo stack
- `dowdiness/incr` — reactive cell runtime for projection memos
- `dowdiness/loom` — parser pipeline
- `dowdiness/text_change` + `dowdiness/moji` — grapheme-aware text diffing
- `dowdiness/pretty` — layout engine for pretty-view rendering

## Stability

Internal but stable — this is the central package of the monorepo. The `SyncEditor` struct shape and `LanguageCapabilities` interface are touched whenever a new editor feature lands.

## Notes

WebSocket wiring is split into two per-target files (`websocket_js.mbt` / `websocket_native.mbt`). Ephemeral state (peer cursors) is encoded in a compact binary varint format, not JSON. The binary sync protocol uses a versioned framing defined in `sync_protocol.mbt`; `encode_message` / `decode_message` are the only crossing points.
