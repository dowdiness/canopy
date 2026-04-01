// Projection JSON API (for ProseMirror bridge)

///|
/// Get the ProjNode tree as JSON string.
/// Returns "null" if no projection is available.
pub fn get_proj_node_json(handle : Int) -> String {
  match editors.get(handle) {
    Some(ed) =>
      match ed.get_proj_node() {
        Some(proj) => proj.to_json().stringify()
        None => "null"
      }
    None => "null"
  }
}

///|
/// Get the SourceMap as JSON string.
/// Returns an array of {node_id, start, end} entries.
pub fn get_source_map_json(handle : Int) -> String {
  match editors.get(handle) {
    Some(ed) => ed.get_source_map().to_json().stringify()
    None => "[]"
  }
}

///|
/// Apply a structural tree edit from a JSON-encoded TreeEditOp.
/// Returns "ok" on success, or "error: <message>" on failure.
pub fn apply_tree_edit_json(
  handle : Int,
  op_json : String,
  timestamp_ms : Int,
) -> String {
  match editors.get(handle) {
    Some(ed) => {
      let json = @json.parse(op_json) catch {
        _ => return "error: invalid JSON"
      }
      match @editor.parse_tree_edit_op(json) {
        Ok(op) =>
          match ed.apply_tree_edit(op, timestamp_ms) {
            Ok(_) => "ok"
            Err(err) => "error: " + err.message()
          }
        Err(err) => "error: " + err.message()
      }
    }
    None => "error: no editor"
  }
}
