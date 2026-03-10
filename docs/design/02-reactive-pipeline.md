# Design 02: Reactive Pipeline Integration

**Parent:** [Grand Design](./GRAND_DESIGN.md)
**Status:** Phase 1 Complete (Strategy A), Phase 2 deferred (Strategy C)
**Updated:** 2026-03-10

---

## Problem

The old `ParsedEditor` (now deleted) used loom's `ImperativeParser` with manual dirty-flag tracking:

```moonbit
// OLD (deleted):
pub struct ParsedEditor {
  mut parse_dirty : Bool       // manual flag
  mut cached_text : String     // manual cache
  mut ast : AstNode?           // manual cache
}
```

Every mutation set `parse_dirty = true`. On access, `reparse()` diffed `cached_text` against `editor.get_text()` to compute an `Edit`. This was:

1. **Redundant** — the Edit Bridge (§1) can produce the edit directly (Phase 2)
2. **Imperative** — manual flag management is error-prone
3. **Ignoring loom's reactive layer** — `Signal`/`Memo` already solve this

---

## Design

### Replace Manual Caching with Reactive Pipeline

Loom's `ReactiveParser` provides exactly the right abstraction:

```
Signal[String]  ->  Memo[CstStage]  ->  Memo[SyntaxNode]
(source text)      (incremental       (typed syntax
                    CST parse)         node views)
```

The reactive pipeline:
- Automatically tracks dependencies via `Signal`/`Memo`
- Only recomputes when inputs change (equality check)
- Lazy evaluation — nothing recomputes until `.get()` is called
- No manual dirty flags

### Architecture

```
+----------------------------------------------------------+
|                   Reactive Wiring                        |
|                                                          |
|  TextDoc --op--> SyncEditor --> parser.set_source()      |
|                                       |                  |
|                                 +-----v------+           |
|                                 | Memo[Cst]  |           |
|                                 | (auto)     |           |
|                                 +-----+------+           |
|                                       |                  |
|                            +----------+----------+       |
|                            v          v          v       |
|                       Memo[Ast]  diagnostics  SourceMap  |
|                            |                             |
|                       (accessed                          |
|                        on demand)                        |
|                                                          |
+----------------------------------------------------------+
```

---

## Integration Strategies

### Strategy A: `ReactiveParser` with `set_source` (implemented)

Use loom's `ReactiveParser` as-is. After each CRDT op, set the new source text:

```moonbit
// SyncEditor (current implementation):
priv parser : @loom.ReactiveParser[@parser.SyntaxNode]

// On each CRDT op (insert, delete, backspace, set_text, apply_sync, undo, redo):
self.parser.set_source(self.doc.text())

// On access (lazy):
let ast = self.parser.term()        // Recomputes only if source changed
let errors = self.parser.diagnostics()
```

`SyncEditor` also exposes a `mark_dirty()` method that simply calls `parser.set_source(self.doc.text())` — used by undo/redo where the text change is indirect.

**Pros:** Uses loom's public API. No changes to loom needed.
**Cons:** Still materializes full text string per edit. `Signal.set` does equality check so it won't re-parse identical text, but string construction is O(n).

### Strategy B: `ImperativeParser` with Edit Bridge (not planned)

Use loom's `ImperativeParser` directly with `Edit`s from the bridge. This would bypass the reactive layer and lose lazy evaluation benefits. Not recommended.

### Strategy C: Hybrid (Phase 2 — deferred)

Use `ReactiveParser` for lazy caching, but feed it `Edit`s via a custom method:

```moonbit
// Future loom API extension:
pub fn ReactiveParser::apply_edit[Ast](
  self : ReactiveParser[Ast],
  edit : Edit,
  new_source : String,
) -> Unit {
  // Set source signal AND pass edit to incremental engine
  self.source_text.set(new_source)
  self.record_pending_edit(edit)
}
```

**Blocked on:** §1 direct Op->Edit path + loom API extension.

---

## What Was Removed

| Old code | Replacement | Status |
|---|---|---|
| `ParsedEditor` struct | `SyncEditor` | Done |
| `ParsedEditor.parse_dirty : Bool` | `Memo` auto-invalidation | Done |
| `ParsedEditor.cached_text : String` | `Signal[String]` inside `ReactiveParser` | Done |
| `ParsedEditor.ast : AstNode?` | `Memo[SyntaxNode]` inside `ReactiveParser` | Done |
| `ParsedEditor.cached_errors` | `parser.diagnostics()` | Done |
| `ParsedEditor.reparse()` | `parser.set_source()` + lazy `.term()` | Done |
| `compute_edit()` in `text_diff.mbt` | Kept as test baseline; not on hot path | Done |
| `CanonicalModel.dirty_projections` | Still exists (used by projection layer) | Deferred |

---

## Memo-derived Views (Phase 2)

With the reactive pipeline, downstream computations should become `Memo`s:

```moonbit
let source_map : Memo[SourceMap] = ...  // Derived from ProjNode tree
let node_registry : Memo[Map[NodeId, ProjNode]] = ...  // Derived from ProjNode tree
```

These are not yet implemented. Currently `SourceMap` and node registry live in `CanonicalModel` with manual `rebuild_indices()`. Migrating to Memo-derived views is part of §3's CanonicalModel retirement (deferred until tree editing is fully integrated).

---

## Verification

1. **Correctness:** `parser.term()` produces correct AST for all inputs. **Working in production.**
2. **Laziness:** Calling `.term()` twice without text change does zero work (memo cache hit). **Verified by loom's own tests.**
3. **No manual flags:** `parse_dirty` does not exist in the codebase. **Confirmed.**
4. **Performance:** Strategy A matches previous `ParsedEditor.reparse()` performance for typical edits.

---

## Dependencies

- **Depends on:** [§1 Edit Bridge](./01-edit-bridge.md) (for Strategy C, deferred)
- **Depends on:** `loom/ReactiveParser` (exists, in use)
- **Depended on by:** [§3 Unified Editor](./03-unified-editor.md)
