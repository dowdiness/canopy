// Lambda editor intent handling — text intents, structural intents, tree edits, ProseMirror bridge.

///|
/// Insert text at a specific position without moving the cursor.
/// Records the operation for undo. Used by ProseMirror bridge.
pub fn insert_at(
  handle : Int,
  position : Int,
  text : String,
  timestamp_ms : Int,
) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.insert_at(position, text, timestamp_ms)
    None => ()
  }
}

///|
/// Delete the character at a specific position without moving the cursor.
/// Records the operation for undo. Returns false if position is out of bounds.
/// Used by ProseMirror bridge.
pub fn delete_at(handle : Int, position : Int, timestamp_ms : Int) -> Bool {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.delete_at(position, timestamp_ms)
    None => false
  }
}

///|
/// Apply a structural tree edit from a JSON-encoded TreeEditOp.
/// Returns "ok" on success, or "error: <message>" on failure.
pub fn apply_tree_edit_json(
  handle : Int,
  op_json : String,
  timestamp_ms : Int,
) -> String {
  match lambda_handles.get(handle) {
    Some(h) => {
      let json = @json.parse(op_json) catch {
        _ => return "error: invalid JSON"
      }
      let op = try? @lang_lambda.parse_tree_edit_op(json)
      match op {
        Ok(op) =>
          match
            @lang_lambda.apply_lambda_tree_edit(
              h.editor,
              h.companion,
              op,
              timestamp_ms,
            ) {
            Ok(_) => "ok"
            Err(err) => "error: " + err.message()
          }
        Err(err) => "error: " + err.message()
      }
    }
    None => "error: no editor"
  }
}

///|
/// Snap-splice variant: endpoints are expanded to enclosing grapheme
/// boundaries per §1.1. For exact-splice semantics that reject non-boundary
/// endpoints, use `handle_text_intent_checked`.
pub fn handle_text_intent(
  handle : Int,
  from : Int,
  deleted_len : Int,
  insert : String,
  timestamp_ms : Int,
) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.apply_text_edit(from, deleted_len, insert, timestamp_ms)
    None => ()
  }
}

///|
/// Exact-splice variant: returns `false` if the splice endpoints are not
/// grapheme boundaries OR are out of bounds. Doc unchanged on rejection. Used
/// by the JS bridge (`bridge.ts::applySpliceChanges`) to maintain its own
/// posOffset bookkeeping; silently snapping inside the seam would cause the
/// bookkeeping to drift.
pub fn handle_text_intent_checked(
  handle : Int,
  from : Int,
  deleted_len : Int,
  insert : String,
  timestamp_ms : Int,
) -> Bool {
  match lambda_handles.get(handle) {
    Some(h) =>
      h.editor.apply_text_edit_exact(from, deleted_len, insert, timestamp_ms)
    None => false
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
