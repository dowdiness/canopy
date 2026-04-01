// Protocol-based intent handlers.

///|
pub fn handle_text_intent(
  handle : Int,
  from : Int,
  deleted_len : Int,
  insert : String,
  timestamp_ms : Int,
) -> Unit {
  match editors.get(handle) {
    Some(ed) => ed.apply_text_edit(from, deleted_len, insert, timestamp_ms)
    None => ()
  }
}

///|
pub fn handle_undo(handle : Int) -> Bool {
  undo_manager_undo(handle)
}

///|
pub fn handle_redo(handle : Int) -> Bool {
  undo_manager_redo(handle)
}

///|
/// Apply a structural edit intent with optional params.
/// params_json is a JSON object string like '{"var_name":"x"}' or ''.
pub fn handle_structural_intent(
  handle : Int,
  op : String,
  node_id_str : String,
  timestamp_ms : Int,
  params_json : String,
) -> String {
  let m : Map[String, Json] = {}
  m["type"] = op.to_json()
  let node_id_int = @string.parse_int(node_id_str) catch {
    _ => return "error: invalid node_id"
  }
  m["node_id"] = node_id_int.to_json()
  // Merge extra params (var_name, new_name, op, etc.)
  if params_json != "" {
    try {
      match @json.parse(params_json) {
        Json::Object(pm) =>
          for k, v in pm {
            m[k] = v
          }
        _ => ()
      }
    } catch {
      _ => ()
    }
  }
  apply_tree_edit_json(handle, Json::object(m).stringify(), timestamp_ms)
}
