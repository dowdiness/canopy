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
/// Return markdown text with ZWSP placeholder lines stripped structurally.
///
/// Identifies sentinel paragraphs (those whose AST is exactly
/// `Paragraph([Text("\u200B")])`) and removes only the ZWSP character itself,
/// collapsing `prev\n\u200B\nnext` to `prev\n\nnext` (preserving the block
/// separator). Leaves ZWSP inside other content (code blocks, paragraphs with
/// other text) untouched.
pub fn export_markdown_text(
  editor : @editor.SyncEditor[@markdown.Block],
) -> String {
  let src = editor.get_text()
  guard editor.get_proj_node() is Some(root) else { return src }
  let source_map = editor.get_source_map()
  let ranges : Array[(Int, Int)] = []
  collect_zwsp_ranges(root, source_map, ranges)
  if ranges.is_empty() {
    return src
  }
  ranges.sort_by(fn(a, b) { a.0.compare(b.0) })
  let buf = StringBuilder::new()
  let mut pos = 0
  for r in ranges {
    let (s, e) = r
    if s > pos {
      buf.write_string(src[pos:s].to_owned())
    }
    pos = e
  }
  if pos < src.length() {
    buf.write_string(src[pos:].to_owned())
  }
  buf.to_string()
}

///|
/// Walk the projection tree and append the source range of every ZWSP-sentinel
/// Paragraph to `out`. The range covers exactly the ZWSP character (the "text"
/// token span), so removing it from source converts `\n\u200B\n` into `\n\n`.
fn collect_zwsp_ranges(
  node : @core.ProjNode[@markdown.Block],
  source_map : @core.SourceMap,
  out : Array[(Int, Int)],
) -> Unit {
  if is_zwsp_sentinel(node.kind) {
    match source_map.get_token_span(node.id(), "text") {
      Some(r) => out.push((r.start, r.end))
      None => ()
    }
    return
  }
  for child in node.children {
    collect_zwsp_ranges(child, source_map, out)
  }
}

///|
fn is_zwsp_sentinel(block : @markdown.Block) -> Bool {
  match block {
    Paragraph(inlines) =>
      inlines.length() == 1 &&
      (match inlines[0] {
        Text(s) => @md_sentinel.is_empty_paragraph_text(s)
        _ => false
      })
    _ => false
  }
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
