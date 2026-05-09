// FFI surface for the JSON editor: lifecycle, text I/O, diagnostics, and
// view patches. Handle registry starts at 10000 to avoid collision with
// lambda registry (1..9999). Structural edits live in edit.mbt.

///|
let json_editors : Map[Int, @editor.SyncEditor[@djson.JsonValue]] = Map::new()

///|
let json_next_handle : Ref[Int] = { val: 10000 }

///|
let json_view_states : Map[Int, @editor.ViewUpdateState] = Map::new()

// ── Lifecycle ────────────────────────────────────────────────────────────

///|
/// Create a new JSON SyncEditor instance.
/// Returns a unique handle for this editor.
pub fn create_json_editor(agent_id : String) -> Int {
  let handle = json_next_handle.val
  json_next_handle.val = handle + 1
  json_editors[handle] = @json_companion.new_json_editor(agent_id)
  handle
}

///|
/// Destroy a JSON editor instance and free its resources.
pub fn destroy_json_editor(handle : Int) -> Unit {
  json_editors.remove(handle)
  json_view_states.remove(handle)
}

///|
/// Get current text content of the JSON editor.
pub fn json_get_text(handle : Int) -> String {
  match json_editors.get(handle) {
    Some(ed) => ed.get_text()
    None => ""
  }
}

///|
/// Set text content directly (replaces entire JSON document).
pub fn json_set_text(handle : Int, new_text : String) -> Unit {
  match json_editors.get(handle) {
    Some(ed) => ed.set_text(new_text)
    None => ()
  }
}

// ── Diagnostics ──────────────────────────────────────────────────────────

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

// ── View patches ─────────────────────────────────────────────────────────

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
          let s = @editor.ViewUpdateState::ViewUpdateState()
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
