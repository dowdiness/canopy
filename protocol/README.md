# protocol

Data types that cross the MoonBit-to-JavaScript boundary: the view tree, diff patches, user intents, and diagnostics. Everything defined here is serializable to JSON and has no dependency on the CRDT internals.

This package is the stable contract between the MoonBit engine and the TypeScript/React frontend. It also contains the two conversion functions that build a `ViewNode` tree from a `ProjNode` tree or a pretty-printer `Layout`.

## Public API

- `ViewNode` — tree node sent to the frontend; carries `id`, `kind_tag`, `label`, `text`, `text_range`, `token_spans`, and `children`
- `ViewPatch` — incremental update: `TextChange`, `ReplaceNode`, `InsertChild`, `RemoveChild`, `UpdateNode`, `SetDecorations`, `SetDiagnostics`, `SetSelection`, `SelectNode`, `FullTree`
- `UserIntent` — frontend-originated action: `TextEdit`, `StructuralEdit`, `SelectNode`, `SetPmCursor`, `SetDocCursor`, `Undo`, `Redo`, `CommitEdit`
- `Decoration` / `Diagnostic` / `Severity` — CodeMirror decoration and lint annotations
- `proj_to_view_node` — converts a `ProjNode[T]` + `SourceMap` into a `ViewNode`
- `layout_to_view_tree` — converts a pretty-printer `Layout` into a `ViewNode` tree

## Consumers

- `editor` — produces `ViewPatch` sequences via `compute_view_patches` and `compute_pretty_patches`
- `lang/lambda/companion` — passes `ViewAnnotation` arrays into `proj_to_view_node`
- `ffi/lambda`, `ffi/json`, `ffi/markdown` — serialize `ViewPatch` / `ViewNode` to JSON for JavaScript
- Root `moon.pkg` (canopy module facade)

## Dependencies

- `dowdiness/canopy/core` — `NodeId`, `ProjNode`, `SourceMap`
- `dowdiness/pretty` — `Layout`, `SyntaxCategory`
- `moonbitlang/core/json` — `ToJson` / `FromJson` derivations

## Stability

Stable wire format / public surface — changes here break the TypeScript frontend and require coordinated updates to the JS consumer side.

## Notes

`UserIntent` implements both `ToJson` and `FromJson` — it is the one type that flows both directions across the FFI boundary. All other protocol types are output-only (MoonBit → JS).
