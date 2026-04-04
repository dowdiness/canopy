///| Bridge from MarkdownEditOp to SyncEditor text edits.

///|
pub fn apply_markdown_edit(
  editor : @editor.SyncEditor[@markdown.Block],
  op : MarkdownEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let source = editor.get_text()
  let proj = match editor.get_proj_node() {
    Some(p) => p
    None => return Err("no projection available")
  }
  let source_map = editor.get_source_map()
  match compute_markdown_edit(op, source, proj, source_map) {
    Ok(Some((edits, focus_hint))) => {
      if edits.is_empty() {
        return Ok(())
      }
      let sorted = edits.copy()
      sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
      let old_cursor = editor.get_cursor()
      for edit in sorted {
        editor.apply_text_edit_internal(
          edit.start,
          edit.delete_len,
          edit.inserted,
          timestamp_ms,
          true,
          false,
        )
      }
      match focus_hint {
        @core.FocusHint::RestoreCursor => editor.move_cursor(old_cursor)
        @core.FocusHint::MoveCursor(position~) => editor.move_cursor(position)
      }
      Ok(())
    }
    Ok(None) => Ok(()) // no-op (e.g., merge on first block)
    Err(msg) => Err(msg)
  }
}
