// JSON editor structural edits: apply_edit + JsonEditOp JSON parser

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
      let json = @core_json.parse(op_json) catch {
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
