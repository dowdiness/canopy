# Grand Design: Collaborative Projectional Editor

**Status:** Phase 1 Complete
**Updated:** 2026-03-10
**Goal:** A collaborative editor where multiple peers edit lambda calculus programs through multiple projections (text, AST tree) with real-time sync, incremental parsing, and undo — powered by eg-walker CRDT and loom incremental parser.

---

> Status note (2026-03-15): the current `SyncEditor` path uses
> `ImperativeParser` plus SyncEditor-owned `Signal`/`Memo` state rather than a
> stored `ReactiveParser`. Tree editing already round-trips through
> `SyncEditor::apply_tree_edit(...)`; the remaining gaps are documentation
> cleanup, direct Op→Edit plumbing, and CRDT range-edit APIs.

## Vision

Combine three independently developed systems into a unified collaborative editing experience:

| System | Role | Status |
|--------|------|--------|
| **eg-walker** | Source of truth for text, sync, undo | ✅ Stable |
| **loom** | Incremental parsing (CST → AST) | ✅ Stable |
| **projection** | Bidirectional views (text ↔ tree) | ⚠️ Partial |

The result is a **sync editor** where:
1. Any peer's keystroke produces a CRDT op
2. CRDT ops produce `Edit`s that drive incremental reparsing
3. The parser's CST/AST feeds multiple projections (text editor, tree editor)
4. All projections stay synchronized across peers

---

## Architectural Principles

1. **CRDT is the single source of truth.** All state derives from the eg-walker OpLog. No parallel history or undo stacks.

2. **Edits flow in one direction, views are derived.** User action → CRDT op → materialized text → incremental parse → projections. Never the reverse at the data layer.

3. **Bridge, don't diff.** CRDT ops carry enough information to produce loom `Edit`s directly. String diffing is a fallback, not the primary path.

4. **Reactive, not imperative.** Use loom's `Signal`/`Memo` pipeline so parsing happens lazily on access, not eagerly on every keystroke.

5. **Awareness is separate from data.** Peer cursors and selections travel over the network but are not CRDT operations.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Per-Peer Architecture                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  User Input ──→ CRDT Ops ──→ Edit Bridge ──→ Reactive      │
│  (keystroke)    (eg-walker)   (ops→Edit)     Parser (loom)  │
│                                               │             │
│                                    ┌──────────┤             │
│                                    ▼          ▼             │
│                              CST/SyntaxNode  AST/Views     │
│                                    │          │             │
│                              ┌─────┴──────────┴──────┐     │
│                              │   Projection Layer     │     │
│                              │  (text, tree, etc.)    │     │
│                              └────────────────────────┘     │
│                                                             │
│  Network ←──→ SyncMessage (ops + frontier + awareness)      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Design Documents

The grand design is realized through five sub-designs, each addressing a specific integration gap:

| # | Document | What it solves | Status |
|---|----------|---------------|--------|
| 1 | [Edit Bridge](./01-edit-bridge.md) | CRDT ops -> loom `Edit` without string diffing | Phase 1 done |
| 2 | [Reactive Pipeline](./02-reactive-pipeline.md) | Replace manual dirty-flag with `Signal`/`Memo` | Phase 1 done |
| 3 | [Unified Editor Facade](./03-unified-editor.md) | Single `SyncEditor` replacing `ParsedEditor` | Phase 1 done |
| 4 | [Ephemeral Store](./04-ephemeral-store.md) | Peer cursors, selections, presence over network | Design complete |
| 5 | [Tree Edit Roundtrip](./05-tree-edit-roundtrip.md) | Structural AST edits -> text CRDT ops -> reparse | Phase 1 partial (bridge + tests) |

### Dependency Graph

```
[1] Edit Bridge          (Phase 1 done: fallback path)
      |
      v
[2] Reactive Pipeline    (Phase 1 done: Strategy A)
      |
      v
[3] Unified Editor       (Phase 1 done: SyncEditor facade)
      |
      +--------+---------+
      |                   |
      v                   v
[4] Ephemeral Store  [5] Tree Edit Roundtrip
    (not started)        (bridge + tests done, needs §3 Memo integration)
```

Documents 1-3 are foundational and their Phase 1 implementations are complete.
Remaining Phase 2 work: direct Op->Edit path (§1), Strategy C with edit-aware parser (§2), Memo-derived ProjNode/SourceMap and CanonicalModel retirement (§3).

---

## What Exists vs. What's Missing

### Implemented

| Component | Location | Status |
|-----------|----------|--------|
| `TextDoc` / `SyncSession` | `event-graph-walker/text/` | Stable |
| `OpLog` / `CausalGraph` / `FugueTree` | `event-graph-walker/internal/` | Stable |
| `UndoManager` | `event-graph-walker/undo/` | Stable |
| `ImperativeParser` + `Signal`/`Memo` wiring | `loom/loom/src/` + `editor/` | Stable, in use by `SyncEditor` |
| `Signal` / `Memo` | `loom/incr/` | Stable |
| `CstNode` / `SyntaxNode` | `loom/seam/` | Stable |
| `Lens` / `SourceMap` | `projection/` | Stable |
| `InteractiveTreeNode` / `TreeEditorState` | `projection/tree_editor.mbt` | Stable |
| `Editor` | `editor/editor.mbt` | Kept as compatibility shim |
| **`SyncEditor`** | `editor/sync_editor.mbt` | **Phase 1 done** — core facade |
| **Edit Bridge** (fallback) | `editor/edit_bridge.mbt` | **Phase 1 done** — `merge_to_edits` |
| **Tree Edit Bridge** | `editor/tree_edit_bridge.mbt` | **Implemented** — uses `SyncEditor` projection memos, undo-aware text roundtrip |

### Still to build

| Component | Design doc | Description |
|-----------|-----------|-------------|
| **Direct Op->Edit path** | [§1](./01-edit-bridge.md) | O(1) `Op -> Edit` (needs `lv_to_position` API) |
| **Edit-aware ReactiveParser** | [§2](./02-reactive-pipeline.md) | Strategy C: `apply_edit(edit, source)` |
| **Memo-derived ProjNode/SourceMap** | [§3](./03-unified-editor.md) | Replace `CanonicalModel` with Memos on `SyncEditor` |
| **Ephemeral store** | [§4](./04-ephemeral-store.md) | Generic KV store for peer presence |
| **Tree edit via SyncEditor** | [§5](./05-tree-edit-roundtrip.md) | `apply_tree_edit` without external `CanonicalModel` |

### Required API Additions (for Phase 2 direct-path optimization)

The direct `Op -> Edit` hot path needs small additions in
`event-graph-walker/text`:

1. `insert_with_op` / `delete_with_op` (or equivalent) so callers can observe
the concrete applied op.
2. `lv_to_position(lv : Int) -> Int?` on `TextDoc` (or another public mapping
API) for op-to-visible-position conversion.

Phase 1 works without these via `parser.set_source(doc.text())` and string-based diff fallback.

### Retired

| Component | Reason | Replaced by | Status |
|-----------|--------|-------------|--------|
| `ParsedEditor` | Redundant facade | `SyncEditor` | **Deleted** |
| `ParsedEditor.parse_dirty` flag | Manual cache invalidation | `Memo` auto-invalidation | **Done** |
| `ParsedEditor.cached_text` | Redundant string cache | `Signal[String]` in `SyncEditor` | **Done** |
| `CanonicalModel.edit_history` | Duplicates CRDT OpLog | eg-walker `UndoManager` | **Not authoritative** |
| `CanonicalModel.dirty_projections` | Manual dirty tracking | `Memo` dependency tracking | **Retired from the active path** |

---

## Implementation Order

### Phase 1: Foundation (complete)

1. ~~Reuse existing loom `TextDelta` API~~ -> `merge_to_edits` in `edit_bridge.mbt`
2. ~~Wire parser state to the CRDT text~~ -> `SyncEditor` updates `ImperativeParser` + signals after each text change
3. ~~Create `SyncEditor` combining `TextDoc` + parser state + `UndoManager`~~
4. ~~Expose FFI surface, retire `ParsedEditor`~~ -> `crdt.mbt` delegates to `SyncEditor`
5. ~~Verify: all tests pass, web demo works~~ -> confirmed

### Phase 2: Optimization + Integration (next)

6. ~~Add Memo-derived `ProjNode` and `SourceMap` to `SyncEditor`~~
7. ~~Integrate tree edit bridge into `SyncEditor` (no external `CanonicalModel` argument)~~
8. Add `lv_to_position` / `insert_with_op` to `TextDoc` for direct Op->Edit
9. Implement `ReactiveParser::apply_edit(edit, source)` in loom (Strategy C)
10. Verify: tree edits produce correct CRDT ops, no dual state

### Phase 3: Awareness + Collaboration

11. Implement `EphemeralStore` for peer presence ([§4](./04-ephemeral-store.md))
12. Add `PeerCursorView` derived from ephemeral store
13. Integrate ephemeral store into `SyncEditor` and FFI
14. Verify: two-peer editing with cursor awareness, tree edits sync

---

## Success Criteria

1. **Single-character edit latency** < 1ms for a 1000-char document (CRDT op + incremental reparse)
2. **No string diffing** on the hot path once op-level APIs are exposed — `Op → Edit` conversion is O(1)
3. **Convergence** — all peers reach identical text and AST given the same op set
4. **Zero manual cache invalidation** — all derived state recomputed via `Memo`
5. **Backward compatible FFI** — web demo works without JS changes during Phase 1-2

---

## References

- [eg-walker paper](https://arxiv.org/abs/2409.14252)
- [loom ROADMAP](../../loom/ROADMAP.md)
- [Projectional Editing Architecture](../architecture/PROJECTIONAL_EDITING.md)
- [Module Structure](../architecture/modules.md)
- [event-graph-walker README](../../event-graph-walker/README.md)
