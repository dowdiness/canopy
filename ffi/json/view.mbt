// JSON editor ViewNode tree + ViewPatch stream

///|
let json_view_states : Map[Int, @editor.ViewUpdateState] = Map::new()

///|
/// Get the ViewNode tree as JSON for a JSON editor.
/// Returns "null" if no projection is available.
pub fn json_get_view_tree_json(handle : Int) -> String {
  match json_editors.get(handle) {
    Some(ed) =>
      match ed.get_view_tree() {
        Some(view_node) => view_node.to_json().stringify()
        None => "null"
      }
    None => "null"
  }
}

///|
/// Compute incremental view patches for a JSON editor.
/// Returns a JSON array of ViewPatch objects.
pub fn json_compute_view_patches_json(handle : Int) -> String {
  match json_editors.get(handle) {
    Some(ed) => {
      let state = match json_view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::new()
          json_view_states[handle] = s
          s
        }
      }
      let patches = @editor.compute_view_patches(state, ed)
      Json::array(patches.map(fn(p) { p.to_json() })).stringify()
    }
    None => "[]"
  }
}
