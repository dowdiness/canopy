// Pretty-printer FFI — ViewNode tree and ViewPatch streams for formatted display

///|
let pretty_view_states : Map[Int, @editor.ViewUpdateState] = Map::default()

///|
/// Get the pretty-printed ViewNode tree as JSON for a lambda editor.
/// Returns "null" if any protected read fails.
pub fn get_pretty_view_json(handle : Int) -> String {
  match lambda_registry.get(handle) {
    Some(h) => {
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.parser_ast) {
        Ok(v) => v
        Err(report) => {
          println("get_pretty_view_json ast read: \{report}")
          return "null"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.escalation_memo) {
        Ok(v) => v
        Err(report) => {
          println("get_pretty_view_json eval read: \{report}")
          return "null"
        }
      }
      h.editor.get_pretty_view().to_json().stringify()
    }
    None => "null"
  }
}

///|
/// Compute incremental pretty-view patches for a lambda editor.
/// Returns a JSON array of ViewPatch objects, or "[]" if any protected read
/// fails.
pub fn compute_pretty_patches_json(handle : Int) -> String {
  match lambda_registry.get(handle) {
    Some(h) => {
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.parser_ast) {
        Ok(v) => v
        Err(report) => {
          println("compute_pretty_patches_json ast read: \{report}")
          return "[]"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.escalation_memo) {
        Ok(v) => v
        Err(report) => {
          println("compute_pretty_patches_json eval read: \{report}")
          return "[]"
        }
      }
      let state = match pretty_view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::ViewUpdateState()
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
