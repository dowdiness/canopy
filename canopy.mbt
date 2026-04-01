// JavaScript bindings for CRDT Editor
// Exposes SyncEditor API to JavaScript via FFI

// Handle-based editor registry (supports multiple concurrent editors)

///|
let editors : Map[Int, @editor.SyncEditor[@ast.Term]] = Map::new()

///|
let next_handle : Ref[Int] = { val: 1 }

///|
let last_created_handle : Ref[Int?] = { val: None }

///|
/// Get the most recently created editor for legacy MoonBit consumers.
pub fn get_sync_editor() -> @editor.SyncEditor[@ast.Term]? {
  match last_created_handle.val {
    Some(handle) => editors.get(handle)
    None => None
  }
}

///|
/// Create a new SyncEditor instance.
/// Returns a unique handle for this editor.
pub fn create_editor(agent_id : String) -> Int {
  let handle = next_handle.val
  next_handle.val = handle + 1
  editors[handle] = @editor.SyncEditor::new_lambda(agent_id)
  last_created_handle.val = Some(handle)
  handle
}

///|
/// Destroy an editor instance and free its resources.
pub fn destroy_editor(handle : Int) -> Unit {
  editors.remove(handle)
  view_states.remove(handle)
  if last_created_handle.val == Some(handle) {
    last_created_handle.val = None
  }
}

///|
/// Get current text content
pub fn get_text(handle : Int) -> String {
  match editors.get(handle) {
    Some(ed) => ed.get_text()
    None => ""
  }
}

///|
/// Set text content directly (replaces entire document)
pub fn set_text(handle : Int, new_text : String) -> Unit {
  match editors.get(handle) {
    Some(ed) => ed.set_text(new_text)
    None => ()
  }
}

///|
/// Get AST as DOT format with name resolution coloring
pub fn get_ast_dot_resolved(handle : Int) -> String {
  match editors.get(handle) {
    Some(ed) => ed.get_dot_resolved()
    None => "digraph { }"
  }
}

///|
/// Get AST as pretty-printed string (expression + debug tree)
pub fn get_ast_pretty(handle : Int) -> String {
  match editors.get(handle) {
    Some(ed) => ed.get_ast_pretty()
    None => ""
  }
}

///|
/// Get parse errors as JSON array
pub fn get_errors_json(handle : Int) -> String {
  match editors.get(handle) {
    Some(ed) => ed.get_errors().to_json().stringify()
    None => "[]"
  }
}

///|
/// Export all operations as a SyncMessage JSON string.
pub fn export_all_json(handle : Int) -> String {
  match editors.get(handle) {
    Some(ed) =>
      ed.export_all().to_json_string() catch {
        _ => "{\"ops\":[],\"heads\":[]}"
      }
    None => "{\"ops\":[],\"heads\":[]}"
  }
}

///|
/// Export operations since a peer's version as a SyncMessage JSON string.
pub fn export_since_json(handle : Int, peer_version_json : String) -> String {
  match editors.get(handle) {
    Some(ed) =>
      try {
        let ver = @text.Version::from_json_string(peer_version_json)
        ed.export_since(ver).to_json_string()
      } catch {
        _ => "{\"ops\":[],\"heads\":[]}"
      }
    None => "{\"ops\":[],\"heads\":[]}"
  }
}

///|
/// Apply a SyncMessage received from a peer.
pub fn apply_sync_json(handle : Int, sync_json : String) -> String {
  match editors.get(handle) {
    Some(ed) =>
      try {
        let msg = @text.SyncMessage::from_json_string(sync_json)
        ed.apply_sync(msg)
        "ok"
      } catch {
        err => "{\"error\":\"\{err}\"}"
      }
    None => "{\"error\":\"invalid handle\"}"
  }
}

///|
/// Get the current version as a JSON string.
pub fn get_version_json(handle : Int) -> String {
  match editors.get(handle) {
    Some(ed) => ed.get_version().to_json_string()
    None => "\"\""
  }
}
