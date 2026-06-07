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

## Position and Offset Units

Protocol positions are plain JSON numbers. Read each number in its declared
unit:

- **UTF-16 document code-unit offset** — an offset in source text. This matches
  CodeMirror, JS `String.length`, and `SyncEditor` cursor APIs.
- **ProseMirror tree position** — an offset in the ProseMirror document tree.
  It is not a source-text offset.

PR #555 replaced the old generic cursor intent with separate cursor intents
so these units stay separate.

| Field | Direction | Unit | Meaning |
|---|---|---|---|
| `ViewPatch.TextChange.from` / `.to` | MoonBit → JS | UTF-16 document code-unit offset | Half-open edit range. |
| `TextEdit.from` / `.to` | JS → MoonBit | UTF-16 document code-unit offset | Half-open edit range. |
| `ViewPatch.SetSelection.anchor` / `.head` | MoonBit → JS | UTF-16 document code-unit offset | Text selection endpoints. |
| `Decoration.from` / `.to` | MoonBit → JS | UTF-16 document code-unit offset | Half-open source range for marks or widgets. |
| `Diagnostic.from` / `.to` | MoonBit → JS | UTF-16 document code-unit offset | Half-open source range for annotations. |
| `SetPmCursor.pm_tree_position` | JS → MoonBit | ProseMirror tree position | Cursor in the PM tree. Convert before using text APIs. |
| `SetDocCursor.doc_code_unit_offset` | JS → MoonBit | UTF-16 document code-unit offset | Cursor in source text. |

Editor code may snap UTF-16 offsets to grapheme boundaries before it converts
them to eg-walker item-space. See [Position Units](../docs/development/API_REFERENCE.md#position-units).

## Stability

Stable wire format / public surface — changes here break the TypeScript frontend and require coordinated updates to the JS consumer side.

### Stable Wire-Format Change Checklist

Before changing stable `ViewPatch`, `UserIntent`, `Decoration`, or
`Diagnostic` JSON shapes:

- Add a changelog entry for the changed field or variant.
- Add a migration note if consumers must change code. Include the reason for
  the break; for unit changes, cite PR #555-style context.
- For any MoonBit protocol change, run `moon info` and review
  `protocol/pkg.generated.mbti` for unintended API diffs.
- Update `adapters/editor-adapter/types.ts`, adapter emit/apply paths, and
  serialization or round-trip tests in the same change.
- Build Canopy demos and known external consumers before release.

## Notes

`UserIntent` implements both `ToJson` and `FromJson` — it is the one type that flows both directions across the FFI boundary. All other protocol types are output-only (MoonBit → JS).
