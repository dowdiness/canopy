## IdentityTransform hints in undo/redo for identity-preserving undo

Tracking issue: [#831](https://github.com/dowdiness/canopy/issues/831)

**Why:** Currently `IdentityTransform` hints are consumed and discarded in a single reconciliation pass. When the user performs `WrapInLambda(node_42)` → Undo, the undo restores the text but the next reconciliation pass has no hint — it falls back to Level 0 LCS and assigns fresh IDs. The cursor position jumps, tree collapse state is lost, and the undo feels broken for structural edits.

Level: `docs/architecture/grove-and-structural-identity.md` Level 1 (edit-aware reconciliation) extended to undo/redo.

### Constraint

`IdentityTransform` is valid only against the **previous projection tree** (the tree before the edit or undo). After a reparse, stale NodeIds in a saved hint are meaningless. Therefore:

- We CANNOT save a hint at forward-edit time and replay it on undo — the undo-time tree may have different NodeIds.
- We MUST derive the inverse hint **against the pre-undo tree** at the moment undo is called.
- This means the undo handler needs access to the current projection tree to construct the inverse in terms of current-valid NodeIds.

### Design

Instead of storing the forward edit's hint, store the **structural edit op description** in the undo record. On undo, the undo handler:

1. Reads the `UndoOp` from the undo record
2. At undo time (before `mark_dirty()`), inspects the **current** projection tree to identify the nodes affected by the reverse operation
3. Constructs the inverse `IdentityTransform` referencing current-valid NodeIds
4. Feeds that hint to the next reconciliation pass

**First slice scope:** **Wrap undo** only. Record the wrapper NodeId at forward-edit time (after reconciliation assigns it). On undo, that wrapper NodeId is valid (no intervening edit changed the tree in this case). If valid, emit `Unwrap(wrapper=wrapper_id, keep=inner_id)`. If stale (intervening edit), degrade to LCS.

This simpler approach works for: Wrap → Immediate Undo (no intervening edits). The common case.

### Scope

- **Undo record** (`editor/`): Add `Array[UndoRecordMeta]` for undo-side and redo-side that mirrors the text undo stack
- **Undo handler** (`SyncEditor::undo`/`redo`): Hook to inspect current projection tree and emit inverse hint
- **Hint pipeline** (`lang/lambda/proj/projection_memo.mbt`): Allow hints to be injected from the undo path (currently hints only come from the structural-edit FFI path)

### Design: undo record extension (desync-safe)

The undo stack lives in `event-graph-walker`'s `UndoManager`. The critical invariant: **every text undo transaction must have a corresponding metadata record**, even if the metadata record carries `None` (no op). Otherwise the two stacks desync.

**Approach A (recommended first slice): One-metadata-record-per-text-undo.**

Add a Canopy-side pair of arrays `(undo_meta_stack, redo_meta_stack)` that mirrors the text UndoManager's two stacks 1:1. Every text undo push also pushes an `UndoRecordMeta`. On undo/redo, metadata entries move between the two stacks (undo → redo on undo, redo → undo on redo). A count mismatch is an abort.

```moonbit
struct UndoRecordMeta {
  record_index : Int      // monotonic counter, incremented per push
  op_desc : Option[UndoOp]          // for deriving inverse at undo time; None for raw text edits
}

pub(all) enum UndoOp {
  Wrap(inner_id_at_edit_time : NodeId, wrapper_node_id : NodeId)
  Unwrap(keep_id_at_edit_time : NodeId)
  Rename(old_name : String)
}
```

Note: `IdentityTransform` is NOT stored. Only `UndoOp` is stored (a description of what the forward edit did). The inverse `IdentityTransform` is derived at undo time from `op_desc` + current tree.

A metadata record is pushed in every function that calls `UndoManager::record_insert` or `UndoManager::record_delete` — currently `insert_and_record`, `delete_and_record`, `backspace_and_record`, and `apply_text_edit_internal` in `editor/sync_editor_undo.mbt` and `editor/sync_editor_text.mbt`. Functions that call `UndoManager::undo`/`redo` pop from the metadata stack and do not push. Remote sync paths (`apply_splice_changes_from_remote`) do not touch the undo stack and produce no metadata.

```
Metadata stack management:

On any forward edit:
  1. Push text undo record to UndoManager (existing)
  2. Push UndoRecordMeta to undo_meta_stack with matching record_index
     - structural edit → op_desc = Some(op)   e.g. Wrap(inner_id=42, wrapper_node_id=91)
     - raw text edit   → op_desc = None

On undo:
  1. Pop from undo_meta_stack. If the array is empty → abort (desync).
  2. If op_desc is None → call UndoManager.undo(), Level 0 fallback
  3. If op_desc is Some(Wrap(inner_id, wrapper_node_id)) →
     a. Read current projection tree (before mark_dirty)
     b. Verify wrapper_node_id still exists in tree
     c. If yes: emit Unwrap(wrapper=wrapper_node_id, keep=inner_id) as hint
     d. If no (node was deleted by intervening edit): no hint, Level 0 fallback
  4. Call UndoManager.undo()
  5. Feed inverse hint (if any) to next reconciliation via identity_hints Ref
  6. Push the popped UndoRecordMeta onto redo_meta_stack

On redo:
  1. Pop from redo_meta_stack. If empty → abort (desync).
  2. If op_desc is None → call UndoManager.redo(), Level 0 fallback
  3. If op_desc is Some(Wrap(inner_id, wrapper_node_id)) →
     Re-emit the original Wrap hint (the forward edit's intent is still correct:
     wrapping inner_id in a new lambda at the current tree position)
  4. Call UndoManager.redo()
  5. Feed hint to next reconciliation
  6. Push the popped UndoRecordMeta back onto undo_meta_stack
```

**Approach B (if event-graph-walker can be extended):** Add `Option[Bytes] user_metadata` to EGW's `UndoRecord`. Serialize `UndoRecordMeta` inside the text undo entry. Eliminates the parallel stacks. Requires an EGW submodule bump.

Approach A is preferred for the first slice: no submodule change, and the 1:1 push discipline is enforced by construction (same function call, same branch).

### Exit criteria

1. **Wrap → Undo preserves cursor position.** After `WrapInLambda(node_42)` → Ctrl+Z, the cursor is at the same logical position as before the wrap.
2. **Wrap → Undo does not freshen the inner expression's NodeId.** Verified via whitebox test: `editor.get_tree()` after undo has the same NodeId for the inner expression as before the wrap.
3. **Wrap → text edit (typing) → Undo(×2) → Redo(×2)**: intermediate raw text edits have `op_desc = None` in their metadata records. Undoing past them correctly reaches the Wrap's metadata and applies the inverse hint. Redoing replays both edits with correct hints.
4. **Redo of non-structural edit produces no hint.** Raw text insert/delete has `op_desc = None`.
5. **Undo of raw text edit before any structural edit**: undo_meta_stack has `None` entry, no hint produced. Same as current behavior.
6. `moon check` + `moon test` pass. `git diff *.mbti` reviewed.

### Non-goals

- Not transmitting hints through the CRDT (Level 2 in grove doc).
- Not fixing structural edit → text edit roundtrip identity for remote peers.
- Not implementing general inverse-hint resolution — first slice handles **Wrap undo** only.
- Not supporting undo of Unwrap or Rename edits — those are follow-up work once the Wrap undo infrastructure is validated.

### Existing code to reuse

- `editor/sync_editor_undo.mbt` — `undo()`, `redo()` entry points
- `core/reconcile.mbt` — `reconcile_hinted` (already consumes hints)
- `core/identity_transform.mbt` — `IdentityTransform::Unwrap`
- `lang/lambda/proj/projection_memo.mbt` — `build_lambda_projection_memos`, `build_hints_map`, `reconcile_lambda_projection_hinted`

### New code

- Add undo/redo metadata stacks to `SyncEditor` struct (two `Array[UndoRecordMeta]`)
- `editor/undo_hooks.mbt` (new file) — `UndoRecordMeta`, `UndoOp` enums; `resolve_inverse_hint` function that inspects current projection tree
- Modifications to `editor/sync_editor_undo.mbt` — push metadata in `insert_and_record`, `delete_and_record`, `backspace_and_record`, `apply_text_edit_internal`; pop metadata in `undo()` / `redo()` and call `resolve_inverse_hint`
- Modifications to `lang/lambda/proj/projection_memo.mbt` or `lambda_editor.mbt` — capture `wrapper_node_id` after reconciliation and store in `UndoOp::Wrap`
