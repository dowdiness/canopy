// JSON edit bridge: applies structural JsonEditOps through the text CRDT.

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
