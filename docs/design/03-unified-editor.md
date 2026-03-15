# Design 03: Unified Editor Facade (`SyncEditor`)

**Parent:** [Grand Design](./GRAND_DESIGN.md)
**Status:** Core facade and memo-derived projection views implemented
**Updated:** 2026-03-15

---

## Problem

The old architecture had three overlapping "editor" types:

| Type | Location | Source of truth for... | Status |
|------|----------|----------------------|--------|
| `Editor` | `editor/editor.mbt` | Thin cursor wrapper around `TextDoc` | Kept (compatibility) |
| `ParsedEditor` | `editor/parsed_editor.mbt` | AST cache, dirty flag, wraps `Editor` | **Deleted** |
| `CanonicalModel` | `projection/canonical_model.mbt` | Historical projection container | Deleted from active code; kept only in historical docs/plans |

The dual source-of-truth problems have been partially resolved:
- `ParsedEditor` is deleted — `SyncEditor` replaces it
- `CanonicalModel.edit_history` is no longer authoritative — `TextDoc.OpLog` is the real history
- Manual `parse_dirty` flag is gone — `SyncEditor` drives invalidation via `ImperativeParser` + `Signal`/`Memo`
- Tree edits now use `SyncEditor`'s memo-derived `ProjNode`, registry, and source map directly

---

## Design

### `SyncEditor`: Single Unified Facade

`SyncEditor` composes (not wraps) the existing systems:

```moonbit
/// Current implementation
pub struct SyncEditor {
  priv doc : @text.TextDoc                              // CRDT text (eg-walker)
  priv undo : @undo.UndoManager                        // Undo/redo (eg-walker)
  priv parser : @loom.ImperativeParser[@parser.SyntaxNode] // Edit-aware parser
  priv parser_rt : @incr.Runtime
  priv source_text : @incr.Signal[String]
  priv syntax_tree : @incr.Signal[@seam.SyntaxNode?]
  priv mut cursor : Int
  priv proj_memo : @incr.Memo[@proj.ProjNode?]
  priv registry_memo : @incr.Memo[Map[@proj.NodeId, @proj.ProjNode]]
  priv source_map_memo : @incr.Memo[@proj.SourceMap]
}
```

**Not yet added** (planned for Phase 2/3):

| Field | Design doc | Needed by |
|-------|-----------|-----------|
| `ephemeral : EphemeralStore` | [§4](./04-ephemeral-store.md) | Peer cursor awareness |
| `cursor_view : PeerCursorView` | [§4](./04-ephemeral-store.md) | Adjusted peer cursor rendering |
| `tree_state : TreeEditorState` | [§5](./05-tree-edit-roundtrip.md) | Tree editor UI state |
| Memo-derived `SourceMap` | §3 (this doc) | Tree editing, node lookup |
| Memo-derived `ProjNode` tree | §3 (this doc) | Stable node IDs, reconciliation |

### `Editor` Decision (Explicit)

`Editor` is **kept** as a thin compatibility shim. It is no longer the architectural center.

- `SyncEditor` owns the production facade used by `crdt.mbt` and sync paths.
- `Editor` remains for compatibility/tests and small local cursor helpers.
- `Editor` must not become a second source of truth.

### Responsibilities

| Concern | Owner | NOT owned by SyncEditor |
|---------|-------|------------------------|
| Text content | `TextDoc` (delegate) | -- |
| Operation history | `TextDoc.OpLog` | No own `edit_history` |
| Undo/redo | `UndoManager` | No own `history_position` |
| Incremental parse | `ImperativeParser` + SyncEditor-managed signals | No dirty flags or cached text |
| Source map | `SyncEditor` memo-derived projection view | No manual `rebuild_indices` |
| Node registry | `SyncEditor` memo-derived projection view | -- |
| Cursor position | `SyncEditor.cursor` | -- |
| Dirty tracking | `Memo` auto-invalidation | No `dirty_projections` map |

---

## Core API (Implemented)

```moonbit
/// Create
pub fn SyncEditor::new(agent_id : String) -> SyncEditor

/// Local editing
pub fn SyncEditor::insert(self, text : String) -> Unit raise
pub fn SyncEditor::delete(self) -> Bool
pub fn SyncEditor::backspace(self) -> Bool
pub fn SyncEditor::move_cursor(self, position : Int) -> Unit

/// Derived state (lazy, via SyncEditor parser/projection memos)
pub fn SyncEditor::get_text(self) -> String        // delegates to TextDoc
pub fn SyncEditor::get_cursor(self) -> Int
pub fn SyncEditor::get_ast(self) -> @ast.Term      // derives from current syntax tree
pub fn SyncEditor::get_ast_pretty(self) -> String  // expression + debug tree
pub fn SyncEditor::get_errors(self) -> Array[String]
pub fn SyncEditor::is_parse_valid(self) -> Bool
pub fn SyncEditor::get_resolution(self) -> String  // binding/free analysis
pub fn SyncEditor::get_dot_resolved(self) -> String // graphviz

/// Bulk text operations
pub fn SyncEditor::set_text(self, new_text : String) -> Unit
pub fn SyncEditor::set_text_and_record(self, new_text : String, timestamp_ms : Int) -> Unit

/// Sync
pub fn SyncEditor::export_all(self) -> @text.SyncMessage raise
pub fn SyncEditor::export_since(self, peer_version : @text.Version) -> @text.SyncMessage raise
pub fn SyncEditor::apply_sync(self, msg : @text.SyncMessage) -> Unit raise

/// Undo (with timestamp-based grouping)
pub fn SyncEditor::insert_and_record(self, text : String, timestamp_ms : Int) -> Unit raise
pub fn SyncEditor::delete_and_record(self, timestamp_ms : Int) -> Bool
pub fn SyncEditor::backspace_and_record(self, timestamp_ms : Int) -> Bool
pub fn SyncEditor::undo(self) -> Bool
pub fn SyncEditor::redo(self) -> Bool
pub fn SyncEditor::can_undo(self) -> Bool
pub fn SyncEditor::can_redo(self) -> Bool
pub fn SyncEditor::set_tracking(self, enabled : Bool) -> Unit
pub fn SyncEditor::clear_undo(self) -> Unit

/// Parser signal (internal)
pub fn SyncEditor::mark_dirty(self) -> Unit  // calls parser.set_source(doc.text())

/// Tree editing (in editor/tree_edit_bridge.mbt)
pub fn SyncEditor::apply_tree_edit(self, op : TreeEditOp, timestamp_ms : Int) -> Result[Unit, String]
```

### Internal Flow: Local Insert

```
user types "x"
  -> self.doc.insert(@text.Pos::at(cursor), "x")
  -> self.parser.edit(edit, self.doc.text())    // Syntax tree updated
  -> cursor += text.length()
  // AST/projection views are still read lazily
```

### Internal Flow: Remote Merge

```
receive SyncMessage from peer
  -> self.doc.sync().apply(msg)                 // CRDT merge
  -> compute_edit(old, new) -> parser.edit(...)  // syntax signal updated
  // AST/projection views lazily recompute on next access
```

---

## FFI Surface

The `crdt.mbt` FFI layer delegates to `SyncEditor`:

```moonbit
// Current (implemented):
let editor : Ref[@editor.SyncEditor?] = { val: None }
// UndoManager is inside SyncEditor -- no separate global
```

All existing FFI functions delegate to `SyncEditor` methods. **No JavaScript changes were required** during the migration from `ParsedEditor`.

---

## What Was Retired

| File / Type | Action | Status |
|---|---|---|
| `editor/parsed_editor.mbt` | Delete | **Done** |
| `ParsedEditor.parse_dirty` | Gone — SyncEditor-managed parser state handles this | **Done** |
| `ParsedEditor.cached_text` | Gone — `source_text : Signal[String]` handles this | **Done** |
| `CanonicalModel.edit_history` | No longer authoritative — `OpLog` is the history | **Done** |
| `editor/text_diff.mbt` | Kept as compatibility wrapper over `text_change/` | **Done** |
| `editor/editor.mbt` (`Editor`) | Kept as compatibility shim | **Done** |
| `projection/canonical_model.mbt` | Deleted from active codebase | **Done** |
| `CanonicalModel.dirty_projections` | No longer part of the active editor flow | **Retired from `SyncEditor` path** |

---

## `CanonicalModel` -> Derived Computation (Implemented in `SyncEditor`)

The useful parts of `CanonicalModel` have been replaced by derived `Memo`s on `SyncEditor`:

| `CanonicalModel` field | Becomes |
|---|---|
| `ast` | `Memo[ProjNode]` — built from `syntax_tree` + reconciliation |
| `node_registry` | `Memo[Map[NodeId, ProjNode]]` — traversal of ProjNode tree |
| `source_map` | `Memo[SourceMap]` derived from ProjNode tree |
| `next_node_id` | Counter in `SyncEditor` |
| `edit_history` | `TextDoc.OpLog` (the real history) |
| `dirty_projections` | Deleted — `Memo` auto-tracks |

`TreeEditorState` now refreshes directly from `ProjNode?` + `SourceMap`:

```moonbit
pub fn TreeEditorState::refresh(
  self : TreeEditorState,
  proj : ProjNode?,
  source_map : SourceMap,
) -> TreeEditorState
```

`SyncEditor::apply_tree_edit(...)` now uses `get_proj_node()`,
`get_source_map()`, and the internal registry memo directly. The remaining gap
is not dual state inside `SyncEditor`; it is the broader cleanup of older
projection-era documentation and APIs that still mention `CanonicalModel`.

---

## Verification

1. **API compatibility:** All `crdt.mbt` FFI functions produce identical JSON output before and after migration. **Verified.**
2. **Test coverage:** All existing tests pass against `SyncEditor`. **Passing.**
3. **Web demo:** Type, delete, undo, sync — all work identically. **Working.**
4. **No dual state in active editor flow:** tree edits, source maps, and node lookup are all driven from `SyncEditor`'s memo-derived projection state.

---

## Dependencies

- **Depends on:** [§1 Edit Bridge](./01-edit-bridge.md), [§2 Reactive Pipeline](./02-reactive-pipeline.md)
- **Depended on by:** [§4 Ephemeral Store](./04-ephemeral-store.md), [§5 Tree Edit Roundtrip](./05-tree-edit-roundtrip.md)
