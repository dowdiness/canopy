///|
const MAX_INTENT_LOG = 50

///|
const MAX_PATCH_LOG = 50

///|
/// Per-SpanEdit cap on the retained `inserted` text. The full text is still
/// applied to the CRDT; only the patch_log copy is truncated to keep
/// patch_log memory proportional to MAX_PATCH_LOG, not to user paste size.
const MAX_PATCH_INSERTED_CHARS = 200

///|
fn push_intent(model : Model, op : @lambda_edits.TreeEditOp) -> Unit {
  push_intent_label(model, op.to_generic().to_string())
}

///|
/// Fallback for structural intents arriving via the FFI path when the op
/// cannot be rebuilt as a typed `TreeEditOp` from `(op, node_id)` alone —
/// e.g. `"Drop"`, whose `source`/`position` payload is not recoverable.
/// Ops in `structural_edit_op_to_tree_edit`'s domain go through
/// `push_intent` instead so the Op Log row shape matches direct-apply paths.
fn push_intent_label(model : Model, label : String) -> Unit {
  model.intent_log.push(label)
  while model.intent_log.length() > MAX_INTENT_LOG {
    model.intent_log.remove(0) |> ignore
  }
}

///|
/// Record an applied (op, SpanEdits) pair for the Patch panel. The op label
/// mirrors the Op Log entry shape (`TreeEditOp.to_generic().to_string()`),
/// so a Patch row reads as a back-reference to the producing Op Log entry.
/// Skipped if `edits` is empty — those rows would be visually noisy and
/// duplicate the corresponding Op Log entry without adding patch detail.
///
/// Each retained `SpanEdit` is decoupled from the editor-owned array:
/// (a) the outer array is rebuilt, so post-apply mutation upstream can't
/// corrupt logged rows; (b) `inserted` is capped at
/// `MAX_PATCH_INSERTED_CHARS` so a 1MB paste doesn't anchor 1MB in the log.
fn push_patch(
  model : Model,
  op : @lambda_edits.TreeEditOp,
  edits : Array[@canopy_core.SpanEdit],
) -> Unit {
  if edits.is_empty() {
    return
  }
  let snapshot = @lambda.snapshot_span_edits(edits, MAX_PATCH_INSERTED_CHARS)
  // Force reconcile to populate the trace with this edit's events,
  // then capture the structural changes as a per-entry snapshot.
  let _ = model.editor.get_proj_node()
  let changes = model.companion.get_structured_changes()
  model.patch_log.push({
    op_label: op.to_generic().to_string(),
    edits: snapshot,
    changes,
  })
  while model.patch_log.length() > MAX_PATCH_LOG {
    model.patch_log.remove(0) |> ignore
  }
}
