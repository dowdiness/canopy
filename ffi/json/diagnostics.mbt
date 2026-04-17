// JSON editor diagnostics: parse errors, ProjNode, SourceMap

///|
/// Get parse errors as JSON array of strings.
pub fn json_get_errors(handle : Int) -> String {
  match json_editors.get(handle) {
    Some(ed) => ed.get_errors().to_json().stringify()
    None => "[]"
  }
}

///|
/// Get the ProjNode tree as JSON string.
/// Returns "null" if no projection is available.
pub fn json_get_proj_node_json(handle : Int) -> String {
  match json_editors.get(handle) {
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
pub fn json_get_source_map_json(handle : Int) -> String {
  match json_editors.get(handle) {
    Some(ed) => ed.get_source_map().to_json().stringify()
    None => "[]"
  }
}
