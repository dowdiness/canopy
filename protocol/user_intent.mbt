// UserIntent: Actions from the UI layer to the editor.

///|
/// One user-originated action delivered from the frontend to the editor.
///
/// `UserIntent` is the inbound counterpart to [`ViewPatch`](view_patch.mbt):
/// the frontend sends intents (typing, selection, undo/redo, structural ops)
/// and the editor responds with patches. The JSON encoding is consumed by
/// `adapters/editor-adapter` on the TypeScript side; new variants must be
/// added in both places.
pub(all) enum UserIntent {
  TextEdit(from~ : Int, to~ : Int, insert~ : String)
  StructuralEdit(
    node_id~ : @core.NodeId,
    op~ : String,
    params~ : Map[String, String]
  )
  SelectNode(node_id~ : @core.NodeId)
  SetPmCursor(pm_tree_position~ : Int)
  SetDocCursor(doc_code_unit_offset~ : Int)
  Undo
  Redo
  CommitEdit(node_id~ : @core.NodeId, value~ : String)
} derive(Debug, Eq)

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
) -> Int raise @json.JsonDecodeError {
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
pub impl ToJson for UserIntent with fn to_json(self) {
  let m : Map[String, Json] = {}
  match self {
    TextEdit(from~, to~, insert~) => {
      m["type"] = "TextEdit".to_json()
      m["from"] = from.to_json()
      m["to"] = to.to_json()
      m["insert"] = insert.to_json()
    }
    StructuralEdit(node_id~, op~, params~) => {
      m["type"] = "StructuralEdit".to_json()
      m["node_id"] = node_id.to_json()
      m["op"] = op.to_json()
      let pm : Map[String, Json] = {}
      for k, v in params {
        pm[k] = v.to_json()
      }
      m["params"] = Json::object(pm)
    }
    SelectNode(node_id~) => {
      m["type"] = "SelectNode".to_json()
      m["node_id"] = node_id.to_json()
    }
    SetPmCursor(pm_tree_position~) => {
      m["type"] = "SetPmCursor".to_json()
      m["pm_tree_position"] = pm_tree_position.to_json()
    }
    SetDocCursor(doc_code_unit_offset~) => {
      m["type"] = "SetDocCursor".to_json()
      m["doc_code_unit_offset"] = doc_code_unit_offset.to_json()
    }
    Undo => m["type"] = "Undo".to_json()
    Redo => m["type"] = "Redo".to_json()
    CommitEdit(node_id~, value~) => {
      m["type"] = "CommitEdit".to_json()
      m["node_id"] = node_id.to_json()
      m["value"] = value.to_json()
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
      let params : Map[String, String] = {}
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
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key("type"), "UserIntent: unknown type '\{type_str}'"),
      )
  }
}
