// JSON parser for TreeEditOp — enables structural edits from JavaScript.
// Used by the apply_tree_edit_json FFI function in crdt.mbt.

///|
/// Parse a JSON value into a TreeEditOp.
/// Expected formats:
///   {"type": "Delete", "node_id": 5}
///   {"type": "WrapInLambda", "node_id": 5, "var_name": "x"}
///   {"type": "Select", "node_id": 5}
pub fn parse_tree_edit_op(json : Json) -> Result[@proj.TreeEditOp, String] {
  let m = match json {
    Json::Object(m) => m
    _ => return Err("expected JSON object")
  }
  let op_type = match m.get("type") {
    Some(Json::String(s)) => s
    _ => return Err("missing type field")
  }
  // Helper to extract node_id
  let node_id = match m.get("node_id") {
    Some(Json::Number(n, ..)) => @proj.NodeId::from_int(n.to_int())
    _ => return Err("missing node_id field")
  }
  match op_type {
    "Delete" => Ok(@proj.TreeEditOp::Delete(node_id~))
    "WrapInLambda" => {
      let var_name = match m.get("var_name") {
        Some(Json::String(s)) => s
        None => "x"
        Some(_) => return Err("var_name must be a string")
      }
      Ok(@proj.TreeEditOp::WrapInLambda(node_id~, var_name~))
    }
    "WrapInApp" => Ok(@proj.TreeEditOp::WrapInApp(node_id~))
    "Select" => Ok(@proj.TreeEditOp::Select(node_id~))
    "Collapse" => Ok(@proj.TreeEditOp::Collapse(node_id~))
    "Expand" => Ok(@proj.TreeEditOp::Expand(node_id~))
    _ => Err("unknown op type: " + op_type)
  }
}
