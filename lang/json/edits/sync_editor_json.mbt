// JSON SyncEditor constructor.

///|
/// Create a new SyncEditor for JSON documents.
/// Uses the generic 3-memo pipeline (no FlatProj).
pub fn new_json_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> @editor.SyncEditor[@json.JsonValue] {
  @editor.SyncEditor::new_generic(
    agent_id,
    fn(s) { @loom.new_imperative_parser(s, @json.json_grammar) },
    @json_proj.build_json_projection_memos,
    capture_timeout_ms~,
  )
}
