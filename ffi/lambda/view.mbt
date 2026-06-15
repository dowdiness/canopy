// View FFI — ViewNode tree and ViewPatch streams for lambda editors

///|
/// Get the ViewNode tree as JSON for a lambda editor.
/// Returns "null" if no projection is available or any protected read fails.
pub fn get_view_tree_json(handle : Int) -> String {
  match lambda_registry.get(handle) {
    Some(h) => {
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.cached_proj_node) {
        Ok(v) => v
        Err(report) => {
          println("get_view_tree_json proj read: \{report}")
          return "null"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.source_map_memo) {
        Ok(v) => v
        Err(report) => {
          println("get_view_tree_json source_map read: \{report}")
          return "null"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.parser_source) {
        Ok(v) => v
        Err(report) => {
          println("get_view_tree_json source read: \{report}")
          return "null"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.escalation_memo) {
        Ok(v) => v
        Err(report) => {
          println("get_view_tree_json eval read: \{report}")
          return "null"
        }
      }
      match h.editor.get_view_tree() {
        Some(view_node) => view_node.to_json().stringify()
        None => "null"
      }
    }
    None => "null"
  }
}

///|
/// Compute incremental view patches for a lambda editor.
/// Returns a JSON array of ViewPatch objects, or "[]" if any protected read
/// fails.
pub fn compute_view_patches_json(handle : Int) -> String {
  match lambda_registry.get(handle) {
    Some(h) => {
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.cached_proj_node) {
        Ok(v) => v
        Err(report) => {
          println("compute_view_patches_json proj read: \{report}")
          return "[]"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.source_map_memo) {
        Ok(v) => v
        Err(report) => {
          println("compute_view_patches_json source_map read: \{report}")
          return "[]"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.parser_source) {
        Ok(v) => v
        Err(report) => {
          println("compute_view_patches_json source read: \{report}")
          return "[]"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.parser_diagnostics) {
        Ok(v) => v
        Err(report) => {
          println("compute_view_patches_json diagnostics read: \{report}")
          return "[]"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.escalation_memo) {
        Ok(v) => v
        Err(report) => {
          println("compute_view_patches_json eval read: \{report}")
          return "[]"
        }
      }
      let state = lambda_registry.view_state(handle)
      let patches = @editor.compute_view_patches(state, h.editor)
      Json::array(patches.map(fn(p) { p.to_json() })).stringify()
    }
    None => "[]"
  }
}
