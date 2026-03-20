# Design 01: Edit Bridge

**Parent:** [Grand Design](./GRAND_DESIGN.md)
**Status:** Phase 1 Complete (fallback path), Phase 2 deferred (direct Op->Edit)
**Updated:** 2026-03-10

---

## Problem

Every time the CRDT text changes, the editor materializes the full text string, then diffs it to produce a loom `Edit`. This is wasteful because the CRDT operation already knows _exactly_ what changed and where.

```
CURRENT (O(n) per edit) — Phase 1, implemented:
  Op::Insert(pos=5, "x") -> doc.text() -> text_to_delta(old, new) -> Edit{5, 0, 1}

IDEAL (O(1) per edit) — Phase 2, deferred:
  Op::Insert(pos=5, "x") -> Edit{5, 0, 1}   // direct conversion
```

---

## Design

### 1. Use existing `TextDelta` API (in loom)

`TextDelta` already exists in loom and is reused directly:

- `TextDelta::{Retain, Insert, Delete}`
- `to_edits(deltas : Array[TextDelta]) -> Array[Edit]`
- `text_to_delta(old : String, new : String) -> Array[TextDelta]`

**Location:** `loom/loom/src/core/delta.mbt` (existing)

### 2. Fallback Path: `merge_to_edits` (Phase 1 — implemented)

The fallback path diffs two text strings via loom's `TextDelta` API:

```moonbit
/// Convert a batch change by diffing whole strings.
/// Used for both local ops and remote merges in Phase 1.
pub fn merge_to_edits(old_text : String, new_text : String) -> Array[@loom_core.Edit] {
  if old_text == new_text {
    return []
  }
  @loom_core.to_edits(@loom_core.text_to_delta(old_text, new_text))
}
```

This is O(n) per edit (prefix/suffix scan of full text), but correct and simple. It is the only active path today.

### 3. Direct Path: `Op -> TextDelta` Converter (Phase 2 — deferred)

Each eg-walker `Op` maps trivially to a `TextDelta`:

```moonbit
/// Convert a CRDT Op (applied at a known visible position) to a TextDelta
fn op_to_delta(op : @core.Op, visible_position : Int) -> Array[TextDelta] {
  match op.content() {
    @core.OpContent::Insert(text) =>
      [TextDelta::Retain(visible_position), TextDelta::Insert(text)]
    @core.OpContent::Delete =>
      [TextDelta::Retain(visible_position), TextDelta::Delete(1)]
    @core.OpContent::Undelete =>
      [] // handled by fallback path
  }
}
```

**Partially unblocked:** `lv_to_position()` is now implemented in `event-graph-walker/internal/document/document.mbt`. `insert_with_op()` is still needed before the direct path can be fully implemented.

### 4. Integration Point

The bridge sits between `TextDoc` and loom's parser. Currently, `SyncEditor` uses the fallback path:

```moonbit
// In SyncEditor (current implementation):
pub fn insert(self : SyncEditor, text : String) -> Unit raise {
  let old_source = self.doc.text()
  self.doc.insert(@text.Pos::at(self.cursor), text)
  self.cursor = self.cursor + text.length()
  self.sync_parser_after_text_change(
    old_source,
    self.doc.text(),
    Some(@parser.Edit::insert(self.cursor - text.length(), text.length())),
  )
}
```

The `merge_to_edits` function is available but `SyncEditor` currently uses the
fallback path only for cases where it does not already know the edit shape (for
example after remote sync). Once the direct path is available, the flow becomes:

```
TextDoc.insert_with_op()
  -> Op created, applied to FugueTree, returned to caller
  -> doc.lv_to_position(op.lv()) -> visible_position
  -> op_to_delta(op, visible_position)
  -> @loom.to_edits(...)
  -> parser.apply_edit(edit, new_source)
```

---

## Resolved Questions

1. **Multi-character inserts:** `TextDoc.insert(pos, "hello")` accepts a full `String`. The CRDT handles character-level op splitting internally. The bridge treats this as a single `Edit{pos, 0, 5}` which is correct for the parser.

2. **Undelete mapping:** Deferred. `Undelete` is a sync-only operation that currently goes through the fallback path (full text diff after merge). It does not need special bridge handling.

---

## Location

| File | Package | Content |
|------|---------|---------|
| `loom/loom/src/core/delta.mbt` | `dowdiness/loom/core` | Existing `TextDelta`, `to_edits`, `text_to_delta` |
| `editor/edit_bridge.mbt` | `dowdiness/canopy/editor` | `merge_to_edits()` (implemented) |
| `editor/edit_bridge_test.mbt` | `dowdiness/canopy/editor` | 13 tests: parity between `merge_to_edits` and `compute_edit` |
| `editor/text_diff.mbt` | `dowdiness/canopy/editor` | `compute_edit()` — kept as reference baseline |

---

## Verification

1. **Fallback parity:** `merge_to_edits(old, new)` produces parser-equivalent edits vs `compute_edit(old, new)`. **13 tests passing.**
2. **Direct-path parity (Phase 2):** For local insert/delete ops, `op_to_delta -> to_edits` should match string-diff baseline.
3. **Benchmark (Phase 2):** Direct conversion vs string diff on 10K-character document.
4. **Integration:** insert via SyncEditor -> `parser.set_source()` -> incremental reparse -> correct AST. **Working in production.**

---

## Dependencies

- **Depends on:** Existing loom `TextDelta` API (`to_edits`, `text_to_delta`)
- **Depends on (Phase 2):** Exported `TextDoc` op/position APIs (`lv_to_position`, `insert_with_op`)
- **Depended on by:** [§2 Reactive Pipeline](./02-reactive-pipeline.md), [§3 Unified Editor](./03-unified-editor.md)
