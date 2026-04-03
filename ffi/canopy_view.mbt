// View FFI — ViewNode tree and ViewPatch streams for both lambda and JSON editors

///|
let view_states : Map[Int, @editor.ViewUpdateState] = Map::new()

///|
let json_view_states : Map[Int, @editor.ViewUpdateState] = Map::new()

///|
/// Get the ViewNode tree as JSON for a lambda editor.
/// Returns "null" if no projection is available.
pub fn get_view_tree_json(handle : Int) -> String {
  match editors.get(handle) {
    Some(ed) =>
      match ed.get_view_tree_with_eval() {
        Some(view_node) => view_node.to_json().stringify()
        None => "null"
      }
    None => "null"
  }
}

///|
/// Compute incremental view patches for a lambda editor (with eval annotations).
/// Returns a JSON array of ViewPatch objects.
pub fn compute_view_patches_json(handle : Int) -> String {
  match editors.get(handle) {
    Some(ed) => {
      let state = match view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::new()
          view_states[handle] = s
          s
        }
      }
      let patches = @editor.compute_view_patches_with_eval(state, ed)
      Json::array(patches.map(fn(p) { p.to_json() })).stringify()
    }
    None => "[]"
  }
}

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
