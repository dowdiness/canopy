// JavaScript bindings for JSON CRDT Editor
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

///|
/// Apply a structural JSON edit from a JSON-encoded JsonEditOp.
/// Returns "ok" on success, or "error: <message>" on failure.
pub fn json_apply_edit(
  handle : Int,
  op_json : String,
  timestamp_ms : Int,
) -> String {
  match json_editors.get(handle) {
    Some(ed) => {
      let json = @json.parse(op_json) catch {
        _ => return "error: invalid JSON"
      }
      match parse_json_edit_op(json) {
        Ok(op) =>
          match @json_companion.apply_json_edit(ed, op, timestamp_ms) {
            Ok(_) => "ok"
            Err(err) => "error: " + err
          }
        Err(err) => "error: " + err
      }
    }
    None => "error: no editor"
  }
}

///|
/// Parse a JsonEditOp from a JSON value (moonbitlang/core/json).
/// Expects objects like {"op": "Delete", "node_id": 3}.
pub fn parse_json_edit_op(
  json : Json,
) -> Result[@json_edits.JsonEditOp, String] {
  let obj = match json {
    Object(m) => m
    _ => return Err("expected object")
  }
  let op_field = match obj.get("op") {
    Some(String(s)) => s
    _ => return Err("missing or invalid 'op' field")
  }
  let node_id_result : (String) -> Result[@core.NodeId, String] = fn(key) {
    match obj.get(key) {
      Some(Number(n, ..)) => Ok(@core.NodeId::from_int(n.to_int()))
      _ => Err("missing or invalid '" + key + "' field")
    }
  }
  let int_result : (String) -> Result[Int, String] = fn(key) {
    match obj.get(key) {
      Some(Number(n, ..)) => Ok(n.to_int())
      _ => Err("missing or invalid '" + key + "' field")
    }
  }
  let string_result : (String) -> Result[String, String] = fn(key) {
    match obj.get(key) {
      Some(String(s)) => Ok(s)
      _ => Err("missing or invalid '" + key + "' field")
    }
  }
  match op_field {
    "Delete" => {
      let node_id = match node_id_result("node_id") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      Ok(@json_edits.JsonEditOp::Delete(node_id~))
    }
    "AddMember" => {
      let object_id = match node_id_result("object_id") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let key = match string_result("key") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      Ok(@json_edits.JsonEditOp::AddMember(object_id~, key~))
    }
    "AddElement" => {
      let array_id = match node_id_result("array_id") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      Ok(@json_edits.JsonEditOp::AddElement(array_id~))
    }
    "WrapInArray" => {
      let node_id = match node_id_result("node_id") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      Ok(@json_edits.JsonEditOp::WrapInArray(node_id~))
    }
    "WrapInObject" => {
      let node_id = match node_id_result("node_id") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let key = match string_result("key") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      Ok(@json_edits.JsonEditOp::WrapInObject(node_id~, key~))
    }
    "Unwrap" => {
      let node_id = match node_id_result("node_id") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      Ok(@json_edits.JsonEditOp::Unwrap(node_id~))
    }
    "ChangeType" => {
      let node_id = match node_id_result("node_id") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let new_type_str = match string_result("new_type") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let new_type = match new_type_str {
        "null" => @json_edits.JsonType::JNull
        "bool" => @json_edits.JsonType::JBool
        "number" => @json_edits.JsonType::JNumber
        "string" => @json_edits.JsonType::JString
        "array" => @json_edits.JsonType::JArray
        "object" => @json_edits.JsonType::JObject
        _ => return Err("unknown type: " + new_type_str)
      }
      Ok(@json_edits.JsonEditOp::ChangeType(node_id~, new_type~))
    }
    "RenameKey" => {
      let object_id = match node_id_result("object_id") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let key_index = match int_result("key_index") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let new_key = match string_result("new_key") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      Ok(@json_edits.JsonEditOp::RenameKey(object_id~, key_index~, new_key~))
    }
    "CommitEdit" => {
      let node_id = match node_id_result("node_id") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let new_value = match string_result("new_value") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      Ok(@json_edits.JsonEditOp::CommitEdit(node_id~, new_value~))
    }
    _ => Err("unknown op: " + op_field)
  }
}
