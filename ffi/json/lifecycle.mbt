// JavaScript bindings for JSON CRDT Editor — lifecycle (create, destroy, text I/O)
// Exposes SyncEditor[@djson.JsonValue] API to JavaScript via FFI
// Handle registry starts at 10000 to avoid collision with lambda registry (1..9999)

///|
let json_editors : Map[Int, @editor.SyncEditor[@djson.JsonValue]] = Map::new()

///|
let json_next_handle : Ref[Int] = { val: 10000 }

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
