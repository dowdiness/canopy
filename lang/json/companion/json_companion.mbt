// Companion adapter functions for the JSON SyncEditor:
//   - constructor (`new_json_editor`)
//   - structural-edit bridge (`apply_json_edit`)

///|
/// Create a new SyncEditor for JSON documents.
/// Uses the generic 3-memo pipeline (no FlatProj).
pub fn new_json_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> @editor.SyncEditor[@json.JsonValue] {
  @editor.SyncEditor::new_generic(
    agent_id,
    fn(s, rt) { @loom.new_parser(s, @json.json_grammar, runtime?=rt) },
    @json_proj.build_json_projection_memos,
    capture_timeout_ms~,
    parent_runtime?,
  )
}

///|
/// Apply a structural JSON edit by computing span-level text edits
/// and routing them through the text CRDT (incremental-parser-aware).
pub fn apply_json_edit(
  editor : @editor.SyncEditor[@json.JsonValue],
  op : @json_edits.JsonEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let source = editor.get_text()
  guard editor.get_proj_node() is Some(proj) else {
    return Err("no projection available")
  }
  let source_map = editor.get_source_map()
  match @json_edits.compute_json_edit(op, source, proj, source_map) {
    Ok(Some((edits, focus_hint))) => {
      editor.apply_span_edits(edits, focus_hint, timestamp_ms)
      Ok(())
    }
    Ok(None) => Err("unhandled edit op: " + op.to_string())
    Err(msg) => Err(msg)
  }
}
