// JSON parser for TreeEditOp — enables structural edits from JavaScript.
// Used by the apply_tree_edit_json FFI function.

///|
using @lambda_edits {type TreeEditOp}

///|
/// Extract a NodeId from a JSON map at the given key.
fn require_node_id(
  m : Map[String, Json],
  key : String,
) -> @core.NodeId raise @editor.TreeEditError {
  match m.get(key) {
    Some(Json::Number(n, ..)) => {
      let i = n.to_int()
      guard i.to_double() == n else {
        raise @editor.TreeEditError::FieldMustBeNumber(field=key)
      }
      @core.NodeId::from_int(i)
    }
    None => raise @editor.TreeEditError::MissingField(field=key)
    Some(_) => raise @editor.TreeEditError::FieldMustBeNumber(field=key)
  }
}

///|
/// Parse a binary operator name string into an ast Bop.
fn parse_bop_string(s : String) -> @ast.Bop raise @editor.TreeEditError {
  match s {
    "Plus" => @ast.Bop::Plus
    "Minus" => @ast.Bop::Minus
    _ => raise @editor.TreeEditError::UnknownBop(name=s)
  }
}

///|
/// Extract a required Bop from a JSON map at the given key.
fn require_bop(
  m : Map[String, Json],
  key : String,
) -> @ast.Bop raise @editor.TreeEditError {
  match m.get(key) {
    Some(Json::String(s)) => parse_bop_string(s)
    None => raise @editor.TreeEditError::MissingField(field=key)
    Some(_) => raise @editor.TreeEditError::FieldMustBeString(field=key)
  }
}

///|
/// Extract a required string from a JSON map at the given key.
fn require_string(
  m : Map[String, Json],
  key : String,
) -> String raise @editor.TreeEditError {
  match m.get(key) {
    Some(Json::String(s)) => s
    None => raise @editor.TreeEditError::MissingField(field=key)
    Some(_) => raise @editor.TreeEditError::FieldMustBeString(field=key)
  }
}

///|
/// Parse a JSON value into a TreeEditOp.
pub fn parse_tree_edit_op(
  json : Json,
) -> TreeEditOp raise @editor.TreeEditError {
  let m = match json {
    Json::Object(m) => m
    _ => raise @editor.TreeEditError::ExpectedJsonObject
  }
  let op_type = match m.get("type") {
    Some(Json::String(s)) => s
    None => raise @editor.TreeEditError::MissingField(field="type")
    Some(_) => raise @editor.TreeEditError::FieldMustBeString(field="type")
  }
  match op_type {
    "Delete" => {
      let node_id = require_node_id(m, "node_id")
      TreeEditOp::Delete(node_id~)
    }
    "WrapInLambda" => {
      let node_id = require_node_id(m, "node_id")
      let var_name = match m.get("var_name") {
        Some(Json::String(s)) => s
        None => "x"
        Some(_) =>
          raise @editor.TreeEditError::FieldMustBeString(field="var_name")
      }
      TreeEditOp::WrapInLambda(node_id~, var_name~)
    }
    "WrapInApp" => {
      let node_id = require_node_id(m, "node_id")
      TreeEditOp::WrapInApp(node_id~)
    }
    "Select" => {
      let node_id = require_node_id(m, "node_id")
      TreeEditOp::Select(node_id~)
    }
    "Collapse" => {
      let node_id = require_node_id(m, "node_id")
      TreeEditOp::Collapse(node_id~)
    }
    "Expand" => {
      let node_id = require_node_id(m, "node_id")
      TreeEditOp::Expand(node_id~)
    }
    "Unwrap" => {
      let node_id = require_node_id(m, "node_id")
      let keep_child_index = match m.get("keep_child_index") {
        Some(Json::Number(n, ..)) => {
          let i = n.to_int()
          guard i.to_double() == n else {
            raise @editor.TreeEditError::FieldMustBeNumber(
              field="keep_child_index",
            )
          }
          i
        }
        None =>
          raise @editor.TreeEditError::MissingField(field="keep_child_index")
        Some(_) =>
          raise @editor.TreeEditError::FieldMustBeNumber(
            field="keep_child_index",
          )
      }
      TreeEditOp::Unwrap(node_id~, keep_child_index~)
    }
    "SwapChildren" => {
      let node_id = require_node_id(m, "node_id")
      TreeEditOp::SwapChildren(node_id~)
    }
    "WrapInIf" => {
      let node_id = require_node_id(m, "node_id")
      TreeEditOp::WrapInIf(node_id~)
    }
    "WrapInBop" => {
      let node_id = require_node_id(m, "node_id")
      let op = require_bop(m, "op")
      TreeEditOp::WrapInBop(node_id~, op~)
    }
    "ChangeOperator" => {
      let node_id = require_node_id(m, "node_id")
      let new_op = require_bop(m, "new_op")
      TreeEditOp::ChangeOperator(node_id~, new_op~)
    }
    "ExtractToLet" => {
      let node_id = require_node_id(m, "node_id")
      let var_name = require_string(m, "var_name")
      TreeEditOp::ExtractToLet(node_id~, var_name~)
    }
    "InlineDefinition" => {
      let node_id = require_node_id(m, "node_id")
      TreeEditOp::InlineDefinition(node_id~)
    }
    "Rename" => {
      let node_id = require_node_id(m, "node_id")
      let new_name = require_string(m, "new_name")
      TreeEditOp::Rename(node_id~, new_name~)
    }
    "DeleteBinding" => {
      let binding_node_id = require_node_id(m, "binding_node_id")
      TreeEditOp::DeleteBinding(binding_node_id~)
    }
    "InlineAllUsages" => {
      let binding_node_id = require_node_id(m, "binding_node_id")
      TreeEditOp::InlineAllUsages(binding_node_id~)
    }
    "DuplicateBinding" => {
      let binding_node_id = require_node_id(m, "binding_node_id")
      TreeEditOp::DuplicateBinding(binding_node_id~)
    }
    "MoveBindingUp" => {
      let binding_node_id = require_node_id(m, "binding_node_id")
      TreeEditOp::MoveBindingUp(binding_node_id~)
    }
    "MoveBindingDown" => {
      let binding_node_id = require_node_id(m, "binding_node_id")
      TreeEditOp::MoveBindingDown(binding_node_id~)
    }
    "AddBinding" => {
      let module_node_id = require_node_id(m, "module_node_id")
      TreeEditOp::AddBinding(module_node_id~)
    }
    "CommitEdit" => {
      let node_id = require_node_id(m, "node_id")
      let new_value = require_string(m, "new_value")
      TreeEditOp::CommitEdit(node_id~, new_value~)
    }
    _ => raise @editor.TreeEditError::UnknownOpType(op_type~)
  }
}
