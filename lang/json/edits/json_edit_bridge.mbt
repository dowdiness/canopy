// JSON edit bridge: applies structural JsonEditOps through the text CRDT.

///|
/// Apply a structural JSON edit by computing span-level text edits
/// and routing them through the text CRDT (incremental-parser-aware).
pub fn apply_json_edit(
  editor : @editor.SyncEditor[@json.JsonValue],
  op : JsonEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let source = editor.get_text()
  let proj = match editor.get_proj_node() {
    Some(p) => p
    None => return Err("no projection available")
  }
  let source_map = editor.get_source_map()
  match compute_json_edit(op, source, proj, source_map) {
    Ok(Some((edits, focus_hint))) => {
      if edits.is_empty() {
        return Ok(())
      }
      // Apply span edits in reverse document order to avoid position shifts.
      let sorted = edits.copy()
      sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
      let old_cursor = editor.get_cursor()
      for edit in sorted {
        editor.apply_text_edit_internal(
          edit.start,
          edit.delete_len,
          edit.inserted,
          timestamp_ms,
          true, // record_undo
          false, // move_cursor_to_edit_end
        )
      }
      match focus_hint {
        @core.FocusHint::RestoreCursor => editor.move_cursor(old_cursor)
        @core.FocusHint::MoveCursor(position~) => editor.move_cursor(position)
      }
      Ok(())
    }
    Ok(None) => Err("unhandled edit op: " + op.to_string())
    Err(msg) => Err(msg)
  }
}
