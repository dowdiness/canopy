// Tree Edit Bridge: Apply structural projection edits through the text CRDT.
// TreeEditOp -> compute_text_edit -> apply_text_edit_internal -> memo reconcile
// Debt rule: tree edits must route back through authoritative text state.
// Do not introduce a second persistent AST/editor model alongside SyncEditor.

///|
/// Apply a tree edit by computing span-level text edits and applying them
/// through the text CRDT (incremental-parser-aware).
pub fn SyncEditor::apply_tree_edit(
  self : SyncEditor,
  op : @proj.TreeEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let old_text = self.get_text()
  let old_cursor = self.get_cursor()
  let source_map = self.get_source_map()
  let registry = self.registry_memo.get()
  let flat_proj = match self.get_flat_proj() {
    Some(fp) => fp
    None => return Err("No FlatProj available")
  }
  match @proj.compute_text_edit(op, old_text, source_map, registry, flat_proj) {
    Ok(Some(edits)) => {
      if edits.is_empty() {
        return Ok(()) // no-op
      }
      // Apply span edits in reverse document order to avoid position shifts.
      // IMPORTANT: use apply_text_edit_internal (not apply_replace_span)
      // because it calls apply_local_text_change to notify the incremental parser.
      // All edits use record_undo=true — the undo manager's capture_timeout_ms
      // groups same-timestamp edits into one undo entry automatically.
      edits.sort_by((a, b) => b.start.compare(a.start))
      for edit in edits {
        self.apply_text_edit_internal(
          edit.start,
          edit.delete_len,
          edit.inserted,
          timestamp_ms,
          true, // record_undo — grouped by capture timeout
          false, // move_cursor_to_edit_end
        )
      }
      self.move_cursor(old_cursor)
      Ok(())
    }
    Ok(None) => Err("Unhandled tree edit op: " + op.to_string())
    Err(msg) => Err(msg)
  }
}
