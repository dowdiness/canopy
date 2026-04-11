///| Bridge from MarkdownEditOp to SyncEditor text edits.

///|
pub fn apply_markdown_edit(
  editor : @editor.SyncEditor[@markdown.Block],
  op : @md_edits.MarkdownEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let source = editor.get_text()
  guard editor.get_proj_node() is Some(proj) else {
    return Err("no projection available")
  }
  let source_map = editor.get_source_map()
  match @md_edits.compute_markdown_edit(op, source, proj, source_map) {
    Ok(Some((edits, focus_hint))) => {
      editor.apply_span_edits(edits, focus_hint, timestamp_ms)
      Ok(())
    }
    Ok(None) => Ok(()) // no-op (e.g., merge on first block)
    Err(msg) => Err(msg)
  }
}
