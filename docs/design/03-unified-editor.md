# Design 03: Unified Editor Facade (`SyncEditor`)

**Parent:** [Grand Design](./GRAND_DESIGN.md)
**Status:** Draft
**Updated:** 2026-03-05

---

## Problem

The current architecture has three overlapping "editor" types:

| Type | Location | Source of truth for... |
|------|----------|----------------------|
| `Editor` | `editor/editor.mbt` | Legacy cursor wrapper around `TextDoc` |
| `ParsedEditor` | `editor/parsed_editor.mbt` | AST cache, dirty flag, wraps `Editor` |
| `CanonicalModel` | `projection/canonical_model.mbt` | Node registry, source map, own edit history |

This creates **dual source-of-truth problems**:
- `CanonicalModel.edit_history` duplicates eg-walker's `OpLog`
- `CanonicalModel.dirty_projections` duplicates what `Memo` tracking should do
- `ParsedEditor.cached_text` duplicates `TextDoc`'s materialized text
- Undo/redo exists in both `CanonicalModel` (history_position) and `UndoManager`

---

## Design

### `SyncEditor`: Single Unified Facade

Replace `ParsedEditor` and `CanonicalModel` with one type that composes (not wraps) the existing systems:

```moonbit
pub struct SyncEditor {
  // === Source of truth ===
  doc : @text.TextDoc                    // CRDT text (eg-walker)
  undo : @undo.UndoManager              // Undo/redo (eg-walker)

  // === Derived (reactive) ===
  parser : @loom.ReactiveParser[Ast]     // Incremental parser (loom)
  // SourceMap, diagnostics, etc. are Memo-derived from parser

  // === UI state (ephemeral) ===
  mut cursor : Int                       // Local cursor position
  tree_state : TreeEditorState           // Tree editor UI state

  // === Sync ===
  awareness : AwarenessState             // Peer cursors (§4)
}
```

### `Editor` Decision (Explicit)

`Editor` is **kept** as a thin compatibility shim in this phase, but it is no longer
the architectural center once `SyncEditor` exists.

- `SyncEditor` owns the production facade used by `crdt.mbt` and sync paths.
- `Editor` may remain for compatibility/tests and small local cursor helpers.
- `Editor` must not become a second source of truth (no parse cache, no history, no awareness state).

### Responsibilities

| Concern | Owner | NOT owned by SyncEditor |
|---------|-------|------------------------|
| Text content | `TextDoc` (delegate) | — |
| Operation history | `TextDoc.OpLog` | No own `edit_history` |
| Undo/redo | `UndoManager` | No own `history_position` |
| Incremental parse | `ReactiveParser` | No dirty flags or cached text |
| Source map | Derived `Memo` from AST | No manual `rebuild_indices` |
| Node registry | Derived from AST traversal | No mutable `Map[NodeId, AstNode]` |
| Cursor position | `SyncEditor.cursor` | — |
| Tree UI state | `TreeEditorState` | — |
| Dirty tracking | `Memo` auto-invalidation | No `dirty_projections` map |

### Core API

```moonbit
/// Create
pub fn SyncEditor::new(agent_id : String) -> SyncEditor

/// Local editing
pub fn insert(self, text : String) -> Unit raise
pub fn delete(self) -> Unit raise
pub fn backspace(self) -> Unit raise
pub fn move_cursor(self, position : Int) -> Unit

/// Derived state (lazy, memo-cached)
pub fn text(self) -> String           // delegates to TextDoc
pub fn ast(self) -> Ast               // delegates to ReactiveParser
pub fn diagnostics(self) -> Array[String]
pub fn source_map(self) -> SourceMap  // derived Memo

/// Sync
pub fn export_all(self) -> SyncMessage raise
pub fn export_since(self, peer : Version) -> SyncMessage raise
pub fn apply_sync(self, msg : SyncMessage) -> Unit raise

/// Undo
pub fn undo(self) -> Array[Op]
pub fn redo(self) -> Array[Op]

/// Tree editing
pub fn apply_tree_edit(self, op : TreeEditOp) -> Unit raise

/// Awareness (§4)
pub fn set_cursor_for_peer(self, peer : String, pos : Int) -> Unit
pub fn get_peer_cursors(self) -> Map[String, Int]
```

### Internal Flow: Local Insert

```
user types "x"
  → self.doc.insert(Pos::at(cursor), "x")
  → self.parser.set_source(self.doc.text())      // Signal updated
  // Phase-2 optimization (after §1 API additions):
  //   insert_with_op() → op_to_edit(op) → apply_edit(edit, new_source)
  → cursor += 1
  // AST is NOT recomputed here — lazy
  // Next call to self.ast() triggers memo recompute
```

### Internal Flow: Remote Merge

```
receive SyncMessage from peer
  → self.doc.sync().apply(msg)                   // CRDT merge
  → self.parser.set_source(self.doc.text())      // Signal updated
  → self.adjust_cursor()                          // Cursor stays valid
  // AST lazily recomputed on next access
```

---

## FFI Surface

The `crdt.mbt` FFI layer calls `SyncEditor` methods instead of `ParsedEditor`:

```moonbit
// Before:
let editor : Ref[ParsedEditor?] = { val: None }
let undo_mgr : Ref[UndoManager?] = { val: None }

// After:
let editor : Ref[SyncEditor?] = { val: None }
// UndoManager is inside SyncEditor — no separate global
```

All existing FFI functions (`create_editor`, `insert`, `get_ast_json`, `merge_operations`, etc.) delegate to `SyncEditor` methods with the same semantics. **No JavaScript changes required.**

---

## What Gets Retired

| File / Type | Action |
|---|---|
| `editor/editor.mbt` (`Editor`) | Keep as thin compatibility wrapper; not the primary facade |
| `editor/parsed_editor.mbt` | Delete — replaced by `SyncEditor` |
| `projection/canonical_model.mbt` | Retire after tree editor is migrated to AST + SourceMap inputs |
| `editor/text_diff.mbt` | Keep as fallback for batch merges, but no longer on hot path |
| `ParsedEditor.parse_dirty` | Gone — `Memo` handles this |
| `ParsedEditor.cached_text` | Gone — `Signal[String]` handles this |
| `CanonicalModel.edit_history` | Gone — `OpLog` is the history |
| `CanonicalModel.dirty_projections` | Gone — `Memo` dependency graph |

---

## Migration Strategy

### Step 1: Create `SyncEditor` alongside `ParsedEditor`

- New file: `editor/sync_editor.mbt`
- Implements same public API as `ParsedEditor`
- Internally uses `TextDoc` + `ReactiveParser`

### Step 2: Switch `crdt.mbt` to `SyncEditor`

- Change the global `editor` ref type
- Update all FFI functions to delegate to `SyncEditor`
- Replace direct internal-field access (`ed.editor.doc`, separate `undo_mgr`)
  with explicit `SyncEditor` methods so FFI only touches public editor API
- Run web demo — should work identically

### Step 3: Remove `ParsedEditor`

- Delete `parsed_editor.mbt`
- Remove `CanonicalModel` if no other consumers
- Keep `Editor` as a compatibility shim (or alias) until all direct consumers are migrated
- Update tests

---

## `CanonicalModel` → Derived Computation

The useful parts of `CanonicalModel` become derived `Memo`s:

| `CanonicalModel` field | Becomes |
|---|---|
| `ast` | `parser.term()` (memo-cached) |
| `node_registry` | On-demand traversal of AST, or a `Memo[Map[NodeId, AstNode]]` |
| `source_map` | `Memo[SourceMap]` derived from AST |
| `next_node_id` | Counter in `SyncEditor`, or derived from max node_id in AST |
| `edit_history` | `TextDoc.OpLog` (the real history) |
| `dirty_projections` | Deleted — `Memo` auto-tracks |

The `TreeEditorState.refresh_from_model()` method would take `Ast` + `SourceMap` directly instead of `CanonicalModel`:

```moonbit
pub fn TreeEditorState::refresh(
  self : TreeEditorState,
  ast : Ast,
  source_map : SourceMap,
) -> TreeEditorState
```

---

## Verification

1. **API compatibility:** All `crdt.mbt` FFI functions produce identical JSON output before and after migration.
2. **Test coverage:** All existing `editor_test.mbt` and `parsed_editor_test.mbt` tests pass against `SyncEditor`.
3. **Web demo:** Manual test — type, delete, undo, sync — all work identically.
4. **No dual state:** Grep for `parse_dirty`, `dirty_projections`, `edit_history` — zero occurrences.

---

## Dependencies

- **Depends on:** [§1 Edit Bridge](./01-edit-bridge.md), [§2 Reactive Pipeline](./02-reactive-pipeline.md)
- **Depended on by:** [§4 Awareness](./04-awareness-protocol.md), [§5 Tree Edit Roundtrip](./05-tree-edit-roundtrip.md)
