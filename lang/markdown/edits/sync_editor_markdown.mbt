///| SyncEditor constructor for Markdown.

///|
pub fn new_markdown_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> @editor.SyncEditor[@markdown.Block] {
  @editor.SyncEditor::new_generic(
    agent_id,
    fn(s) { @loom.new_imperative_parser(s, @markdown.markdown_grammar) },
    @md_proj.build_markdown_projection_memos,
    capture_timeout_ms~,
  )
}
