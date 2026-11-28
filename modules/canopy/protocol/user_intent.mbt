// UserIntent: Actions from the UI layer to the editor.

///|
/// One user-originated action delivered from the frontend to the editor.
///
/// `UserIntent` is the inbound counterpart to [`ViewPatch`](view_patch.mbt):
/// the frontend sends intents (typing, selection, undo/redo, structural ops)
/// and the editor responds with patches. The JSON encoding is consumed by
/// `adapters/editor` on the TypeScript side; new variants must be
/// added in both places.
#derive(Debug, Eq)
pub(all) enum UserIntent {
  TextEdit(from~ : Int32, to~ : Int32, insert~ : String)
  StructuralEdit(
    node_id~ : @core.NodeId,
    op~ : String,
    params~ : Map[String, String],
  )
  SelectNode(node_id~ : @core.NodeId)
  SetPmCursor(pm_tree_position~ : Int32)
  SetDocCursor(doc_code_unit_offset~ : Int32)
  Undo
  Redo
  CommitEdit(node_id~ : @core.NodeId, value~ : String)
  ApplyDiagnosticFix(
    snapshot_id~ : Int32,
    diagnostic_id~ : Int32,
    fix_id~ : Int32,
  )
}

///|
pub impl Show for UserIntent with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
fn user_intent_number_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
  owner : String,
) -> Int32 raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(Json::Number(n, ..)) => n.to_int()
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key(key), "\{owner}: '\{key}' must be a number"),
      )
  }
}

///|
fn user_intent_string_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
  owner : String,
) -> String raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(Json::String(s)) => s
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key(key), "\{owner}: '\{key}' must be a string"),
      )
  }
}

///|
fn user_intent_nonnegative_id_field(
  fields : Map[String, Json],
  path : @json.JsonPath,
  key : String,
  owner : String,
) -> Int32 raise @json.JsonDecodeError {
  match fields.get(key) {
    Some(Json::Number(number, ..)) => {
      let value = number.to_int()
      if value >= 0 && number == value.to_double() {
        value
      } else {
        raise @json.JsonDecodeError(
          (
            path.add_key(key),
            "\{owner}: '\{key}' must be a non-negative integer",
          ),
        )
      }
    }
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key(key), "\{owner}: '\{key}' must be a non-negative integer"),
      )
  }
}

///|
pub impl ToJson for UserIntent with fn to_json(self) {
  let m : Map[String, Json] = Map([])
  match self {
    TextEdit(from~, to~, insert~) => {
      m["type"] = Json("TextEdit")
      m["from"] = Json(from)
      m["to"] = Json(to)
      m["insert"] = Json(insert)
    }
    StructuralEdit(node_id~, op~, params~) => {
      m["type"] = Json("StructuralEdit")
      m["node_id"] = node_id.to_json()
      m["op"] = Json(op)
      let pm : Map[String, Json] = Map([])
      for k, v in params {
        pm[k] = Json(v)
      }
      m["params"] = Json::object(pm)
    }
    SelectNode(node_id~) => {
      m["type"] = Json("SelectNode")
      m["node_id"] = node_id.to_json()
    }
    SetPmCursor(pm_tree_position~) => {
      m["type"] = Json("SetPmCursor")
      m["pm_tree_position"] = Json(pm_tree_position)
    }
    SetDocCursor(doc_code_unit_offset~) => {
      m["type"] = Json("SetDocCursor")
      m["doc_code_unit_offset"] = Json(doc_code_unit_offset)
    }
    Undo => m["type"] = Json("Undo")
    Redo => m["type"] = Json("Redo")
    CommitEdit(node_id~, value~) => {
      m["type"] = Json("CommitEdit")
      m["node_id"] = node_id.to_json()
      m["value"] = Json(value)
    }
    ApplyDiagnosticFix(snapshot_id~, diagnostic_id~, fix_id~) => {
      m["type"] = Json("ApplyDiagnosticFix")
      m["snapshot_id"] = Json(snapshot_id)
      m["diagnostic_id"] = Json(diagnostic_id)
      m["fix_id"] = Json(fix_id)
    }
  }
  Json::object(m)
}

///|
pub impl @json.FromJson for UserIntent with fn from_json(json, path) {
  let m = match json {
    Json::Object(m) => m
    _ => raise @json.JsonDecodeError((path, "UserIntent: expected JSON object"))
  }
  let type_str = match m.get("type") {
    Some(Json::String(s)) => s
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key("type"), "UserIntent: missing or invalid 'type' field"),
      )
  }
  match type_str {
    "TextEdit" => {
      let from = user_intent_number_field(m, path, "from", "TextEdit")
      let to = user_intent_number_field(m, path, "to", "TextEdit")
      let insert = user_intent_string_field(m, path, "insert", "TextEdit")
      UserIntent::TextEdit(from~, to~, insert~)
    }
    "StructuralEdit" => {
      let node_id = @core.NodeId::from_int(
        user_intent_number_field(m, path, "node_id", "StructuralEdit"),
      )
      let op = user_intent_string_field(m, path, "op", "StructuralEdit")
      let params : Map[String, String] = Map([])
      match m.get("params") {
        Some(Json::Object(pm)) =>
          for k, v in pm {
            match v {
              Json::String(s) => params[k] = s
              _ =>
                raise @json.JsonDecodeError(
                  (
                    path.add_key("params").add_key(k),
                    "StructuralEdit: param value must be a string",
                  ),
                )
            }
          }
        Some(_) =>
          raise @json.JsonDecodeError(
            (
              path.add_key("params"),
              "StructuralEdit: 'params' must be an object",
            ),
          )
        None => ()
      }
      UserIntent::StructuralEdit(node_id~, op~, params~)
    }
    "SelectNode" => {
      let node_id = @core.NodeId::from_int(
        user_intent_number_field(m, path, "node_id", "SelectNode"),
      )
      UserIntent::SelectNode(node_id~)
    }
    "SetPmCursor" => {
      let pm_tree_position = user_intent_number_field(
        m, path, "pm_tree_position", "SetPmCursor",
      )
      UserIntent::SetPmCursor(pm_tree_position~)
    }
    "SetDocCursor" => {
      let doc_code_unit_offset = user_intent_number_field(
        m, path, "doc_code_unit_offset", "SetDocCursor",
      )
      UserIntent::SetDocCursor(doc_code_unit_offset~)
    }
    "Undo" => UserIntent::Undo
    "Redo" => UserIntent::Redo
    "CommitEdit" => {
      let node_id = @core.NodeId::from_int(
        user_intent_number_field(m, path, "node_id", "CommitEdit"),
      )
      let value = user_intent_string_field(m, path, "value", "CommitEdit")
      UserIntent::CommitEdit(node_id~, value~)
    }
    "ApplyDiagnosticFix" => {
      let snapshot_id = user_intent_nonnegative_id_field(
        m, path, "snapshot_id", "ApplyDiagnosticFix",
      )
      let diagnostic_id = user_intent_nonnegative_id_field(
        m, path, "diagnostic_id", "ApplyDiagnosticFix",
      )
      let fix_id = user_intent_nonnegative_id_field(
        m, path, "fix_id", "ApplyDiagnosticFix",
      )
      UserIntent::ApplyDiagnosticFix(snapshot_id~, diagnostic_id~, fix_id~)
    }
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key("type"), "UserIntent: unknown type '\{type_str}'"),
      )
  }
}

///|
pub extend UserIntent with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend UserIntent with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend UserIntent with Eq::{equal, not_equal}

///|
pub extend UserIntent with Show::{output, to_string}

///|
pub extend UserIntent with ToJson::{to_json}
