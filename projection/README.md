# projection

Interactive tree-editor UI state for projectional editing — selection, inline editing, drag-and-drop, and node collapse — maintained as a pure value (`TreeEditorState[T]`) that is updated by applying `GenericTreeOp` events.

This package bridges the gap between the raw `ProjNode` tree (from `core`) and what the frontend tree-editor widget needs to render. It is language-agnostic: any `T` satisfying `TreeNode + Renderable` can be hosted here.

## Public API

- `TreeEditorState[T]` — full UI state snapshot: current tree, selection set, editing node, drag-over target, collapsed nodes
- `TreeEditorState::from_projection` — build initial state from a `ProjNode` tree
- `TreeEditorState::refresh` — incremental update when the underlying `ProjNode` changes
- `TreeEditorState::apply_edit` — apply a `GenericTreeOp` and return the new state (pure)
- `InteractiveTreeNode[T]` — view-model node annotated with `selected`, `editing`, `collapsed`, `drop_target`
- `InteractiveChildren[T]` — either `Loaded(children)` or `Elided(count)` for virtual scrolling

## Consumers

- Root `moon.pkg` (canopy module facade) — the only direct in-module importer found
- `lang/lambda/companion` (`lang/lambda/companion/moon.pkg`) implicitly uses these types through the `editor` package

## Dependencies

- `dowdiness/canopy/core` — `ProjNode`, `SourceMap`, `NodeId`, `GenericTreeOp`, `DropPosition`
- `dowdiness/loom/core` — `TreeNode`, `Renderable`, `Range`

## Stability

Internal but stable — the `TreeEditorState` shape is touched when new structural editing features are added (e.g. multi-select, new collapse modes).

## Notes

`TreeEditorState` is a pure value — every operation returns a new state rather than mutating in place. This makes it safe to snapshot and compare across reactive refresh cycles.
