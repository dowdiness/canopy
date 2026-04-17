// View FFI — ViewNode tree and ViewPatch streams for lambda editors

///|
let view_states : Map[Int, @editor.ViewUpdateState] = Map::new()

///|
/// Get the ViewNode tree as JSON for a lambda editor.
/// Returns "null" if no projection is available.
pub fn get_view_tree_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) =>
      match h.editor.get_view_tree() {
        Some(view_node) => view_node.to_json().stringify()
        None => "null"
      }
    None => "null"
  }
}

///|
/// Compute incremental view patches for a lambda editor.
/// Returns a JSON array of ViewPatch objects.
pub fn compute_view_patches_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => {
      let state = match view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::new()
          view_states[handle] = s
          s
        }
      }
      let patches = @editor.compute_view_patches(state, h.editor)
      Json::array(patches.map(fn(p) { p.to_json() })).stringify()
    }
    None => "[]"
  }
}
