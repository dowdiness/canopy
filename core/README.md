# core

Shared runtime types for the projectional editor — the vocabulary that `editor`, `protocol`, and all `lang/*` packages agree on.

This package owns nothing computational: no parsing, no CRDT, no rendering. It only defines the identifiers and data shapes that cross package boundaries, plus the incremental-memo wiring that connects a parsed `SyntaxNode` to a live `ProjNode` tree.

## Public API

- `NodeId` — stable identifier for an AST node, persists across edits
- `ProjNode[T]` — generic tree node carrying a language-specific `kind : T`, a `NodeId`, and source-range bounds
- `SourceMap` — bidirectional index from `NodeId` to text range and back; supports incremental `patch_subtree` / `remove_subtree`
- `GenericTreeOp` — UI-level tree operations (select, drag-drop, structural edit, collapse) that language packages translate to via `to_generic()`
- `DropPosition` (`Before` / `After` / `Inside`) — drag-and-drop placement enum used by `GenericTreeOp` and by language-specific edit ops
- `Direction` (`Up` / `Down` / `Left` / `Right`) — navigation direction used by `navigate_proj`
- `SpanEdit` / `FocusHint` — low-level text-edit and cursor-placement hints returned by edit handlers
- `build_projection_memos` — wires `SyntaxNode → ProjNode → SourceMap` as three reactive `Memo` cells

## Consumers

Imported by almost every package in the module: `editor`, `protocol`, `projection`, all `lang/*/proj`, `lang/*/edits`, `lang/*/companion`, `lang/*/flat`, `ffi/json`, `ffi/markdown`, and the root `moon.pkg`.

## Dependencies

- `dowdiness/incr` (reactive cells / `Memo`)
- `dowdiness/loom/core` (`TreeNode`, `Range`)
- `dowdiness/seam` (`SyntaxNode` concrete type)

## Stability

Stable wire format / public surface — all language packages depend on these types. Field changes require coordinated updates across the whole module.

## Notes

`ProjNode` IDs are assigned by `assign_fresh_ids` during projection and preserved across incremental refreshes by `reconcile`. The `SourceMap` stores token-level sub-ranges (e.g. the exact span of a keyword within a node) keyed by role string via `set_token_span`.
