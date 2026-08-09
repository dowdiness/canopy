# editor

Language-agnostic CRDT editor engine that combines text storage, undo/redo, reactive parsing, ephemeral presence, WebSocket sync, and view-update diffing into a single `SyncEditor[T]` host.

`SyncEditor[T]` is parameterized on the language's AST type `T`. Each language's `companion` subpackage (`lang/lambda/companion`, `lang/json/companion`, `lang/markdown/companion`) defines a `lang/runtime.Language[T, Op, E]` and constructs the editor through `Language::build`. The runtime delegates to `SyncEditor::new_with_builder`, which owns parser, projection, capability, and identity-hint-channel construction order. The FFI packages then wrap the result and export concrete functions to JavaScript.

## Public API

- `SyncEditor[T]` — core struct holding `TextState`, `UndoManager`, reactive `Parser[T]`, ephemeral hub, and WebSocket state
- `SyncEditor::new_with_builder` — coherent low-level constructor used by `lang/runtime.Language::build`; projection builders receive only an opaque consume-only identity-hint handle
- `compute_view_patches` / `compute_pretty_patches` — incremental diff of `ProjNode` tree into `ViewPatch` operations for the frontend
- `EphemeralHub` — multi-peer cursor and presence state (encode/apply/broadcast)
- `SyncMessage` / `encode_message` / `decode_message` — binary protocol framing for CRDT ops, sync requests, and room control
- `ViewUpdateState` — snapshot used to compute minimal `ViewPatch` sequences
- `LanguageCapabilities[T]` — per-language hooks wired at construction time (text-edit handler, tree-edit handler, pretty-print, ViewNode conversion, etc.)

## Language-specific ViewNode conversion

`LanguageCapabilities::with_to_view_node` is the intended hook when a language needs to convert `ProjNode[T]` to `protocol.ViewNode` differently from the generic `Renderable` path. Use it for language-specific view semantics that are derived from the projection tree, `SourceMap`, annotations, and optional source text.

The converter should keep the generic `ViewNode` wire contract. Prefer calling `@protocol.proj_to_view_node` first, then refining the returned tree narrowly. Markdown uses this path to preserve list-specific view tags while keeping generic editor and FFI view-patch code language-agnostic.

Do not add parallel frontend-only view models or special-case language behavior in `SyncEditor::get_view_tree`; install the converter in the language companion constructor instead.

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

## Markdown façade coordinate migration

Starting with the portable snapshot and receipt contract:

- `MarkdownDocumentSnapshot::source`, block source/text/marker/fence ranges, block and document selections, and `MarkdownCommitReceipt::transforms` share one sentinel-free UTF-16 coordinate space.
- Only runtime-confirmed structural empty-paragraph sentinels collapse from that source and its ranges. Caller-authored inline ZWSP remains visible, while an empty block's public text is empty and its text range is zero-width.
- A source-equal accepted commit may report `MarkdownCommitResult::Unchanged` while its version and history advance. Its receipt still retains the accepted transform evidence.
- `MarkdownEditorError::Committed` means mutation landed and must not be retried. It carries portable before/optional-after `MarkdownCommittedEvidence` and a typed `MarkdownPostCommitIssue`.

Two compatibility paths are intentionally outside this coordinate migration. `MarkdownEditRequest::ReplaceText` still accepts legacy canonical coordinates; do not derive those offsets from a portable snapshot when hidden sentinels exist. `MarkdownEditRequest::ReplaceSource` remains a lossy source import and does not continue causal identity; use `MarkdownEditor::open` or `MarkdownEditor::admit` with history to continue an owned document.

## Notes

WebSocket wiring is split into two per-target files (`websocket_js.mbt` / `websocket_native.mbt`). Ephemeral state (peer cursors) is encoded in a compact binary varint format, not JSON. The binary sync protocol uses a versioned framing defined in `sync_protocol.mbt`; `encode_message` / `decode_message` are the only crossing points.
