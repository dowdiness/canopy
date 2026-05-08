///| Companion adapter functions for the Markdown SyncEditor:
///   - constructor (`new_markdown_editor`)
///   - structural-edit bridge (`apply_markdown_edit`)

///|
/// Construct a SyncEditor[@markdown.Block] using the standard 3-memo pipeline.
pub fn new_markdown_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> @editor.SyncEditor[@markdown.Block] {
  @editor.SyncEditor::new_generic(
    agent_id,
    fn(s) { @loom.new_parser(s, @markdown.markdown_grammar) },
    @md_proj.build_markdown_projection_memos,
    capture_timeout_ms~,
  )
}

///|
/// Bridge a structural MarkdownEditOp into the text CRDT by computing
/// span-level text edits and applying them via SyncEditor.
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
