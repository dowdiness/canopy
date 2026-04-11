// Pretty-printer FFI — ViewNode tree and ViewPatch streams for formatted display

///|
let pretty_view_states : Map[Int, @editor.ViewUpdateState] = Map::new()

///|
/// Get the pretty-printed ViewNode tree as JSON for a lambda editor.
pub fn get_pretty_view_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.get_pretty_view().to_json().stringify()
    None => "null"
  }
}

///|
/// Compute incremental pretty-view patches for a lambda editor.
/// Returns a JSON array of ViewPatch objects.
pub fn compute_pretty_patches_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => {
      let state = match pretty_view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::new()
          pretty_view_states[handle] = s
          s
        }
      }
      let patches = @editor.compute_pretty_patches(state, h.editor)
      Json::array(patches.map(fn(p) { p.to_json() })).stringify()
    }
    None => "[]"
  }
}
