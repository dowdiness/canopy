///| Companion adapter functions for the Markdown SyncEditor:
///   - constructor (`new_markdown_editor`)
///   - structural-edit bridge (`apply_markdown_edit`)

///| Construct a SyncEditor[@markdown.Block] using the standard 3-memo pipeline.

///|
/// Raises `TextError::EmptyReplicaId` when `agent_id` is empty.
pub fn new_markdown_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> @editor.SyncEditor[@markdown.Block] raise {
  @markdown_runtime.new_editor(agent_id, capture_timeout_ms~, parent_runtime?)
}

///|
/// Construct the standard Markdown editor and one semantic attachment over
/// the exact parser created for it. No parser or reactive handle escapes this
/// Markdown-specific companion boundary.
pub fn new_markdown_editor_with_semantic_attachment(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> (@editor.SyncEditor[@markdown.Block], @markdown.MarkdownSemanticAttachment) raise {
  @markdown_runtime.new_editor_with_semantic_attachment(
    agent_id,
    capture_timeout_ms~,
    parent_runtime?,
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
  @markdown_runtime.export_markdown_text(editor)
}

///|
/// Bridge a structural MarkdownEditOp into the text CRDT by computing
/// span-level text edits and applying them via SyncEditor.
pub fn apply_markdown_edit(
  editor : @editor.SyncEditor[@markdown.Block],
  op : @md_edits.MarkdownEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] raise {
  match @markdown_runtime.apply_edit(editor, op, timestamp_ms) {
    Ok(_) => Ok(())
    Err(e) => Err(e.message())
  }
}
