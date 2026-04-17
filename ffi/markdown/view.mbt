// Markdown editor ViewPatch stream

///|
let markdown_view_states : Map[Int, @editor.ViewUpdateState] = Map::new()

///|
pub fn markdown_compute_view_patches_json(handle : Int) -> String {
  match markdown_editors.get(handle) {
    Some(ed) => {
      let state = match markdown_view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::new()
          markdown_view_states[handle] = s
          s
        }
      }
      let patches = @editor.compute_view_patches(state, ed)
      Json::array(patches.map(fn(p) { p.to_json() })).stringify()
    }
    None => "[]"
  }
}
