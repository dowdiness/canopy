// UserIntent: Actions from the UI layer to the editor.
// Deserialized from JSON sent by TypeScript adapters.

///|
pub(all) enum UserIntent {
  TextEdit(from~ : Int, to~ : Int, insert~ : String)
  StructuralEdit(
    node_id~ : @core.NodeId,
    op~ : String,
    params~ : Map[String, String]
  )
  SelectNode(node_id~ : @core.NodeId)
  SetCursor(position~ : Int)
  Undo
  Redo
  CommitEdit(node_id~ : @core.NodeId, value~ : String)
} derive(Show, Eq)

///|
pub impl ToJson for UserIntent with to_json(self) {
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
      m["node_id"] = node_id_to_json(node_id)
      m["op"] = op.to_json()
      let pm : Map[String, Json] = {}
      for k, v in params {
        pm[k] = v.to_json()
      }
      m["params"] = Json::object(pm)
    }
    SelectNode(node_id~) => {
      m["type"] = "SelectNode".to_json()
      m["node_id"] = node_id_to_json(node_id)
    }
    SetCursor(position~) => {
      m["type"] = "SetCursor".to_json()
      m["position"] = position.to_json()
    }
    Undo => m["type"] = "Undo".to_json()
    Redo => m["type"] = "Redo".to_json()
    CommitEdit(node_id~, value~) => {
      m["type"] = "CommitEdit".to_json()
      m["node_id"] = node_id_to_json(node_id)
      m["value"] = value.to_json()
    }
  }
  Json::object(m)
}

///|
pub impl @json.FromJson for UserIntent with from_json(json, path) {
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
      let from = match m.get("from") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ =>
          raise @json.JsonDecodeError(
            (
              path.add_key("from"),
              "UserIntent.TextEdit: 'from' must be a number",
            ),
          )
      }
      let to = match m.get("to") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ =>
          raise @json.JsonDecodeError(
            (path.add_key("to"), "UserIntent.TextEdit: 'to' must be a number"),
          )
      }
      let insert = match m.get("insert") {
        Some(Json::String(s)) => s
        _ =>
          raise @json.JsonDecodeError(
            (
              path.add_key("insert"),
              "UserIntent.TextEdit: 'insert' must be a string",
            ),
          )
      }
      UserIntent::TextEdit(from~, to~, insert~)
    }
    "StructuralEdit" => {
      let node_id = match m.get("node_id") {
        Some(Json::Number(n, ..)) => @core.NodeId::from_int(n.to_int())
        _ =>
          raise @json.JsonDecodeError(
            (
              path.add_key("node_id"),
              "UserIntent.StructuralEdit: 'node_id' must be a number",
            ),
          )
      }
      let op = match m.get("op") {
        Some(Json::String(s)) => s
        _ =>
          raise @json.JsonDecodeError(
            (
              path.add_key("op"),
              "UserIntent.StructuralEdit: 'op' must be a string",
            ),
          )
      }
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
                    "UserIntent.StructuralEdit: param value must be a string",
                  ),
                )
            }
          }
        Some(_) =>
          raise @json.JsonDecodeError(
            (
              path.add_key("params"),
              "UserIntent.StructuralEdit: 'params' must be an object",
            ),
          )
        None => () // params is optional, default to empty map
      }
      UserIntent::StructuralEdit(node_id~, op~, params~)
    }
    "SelectNode" => {
      let node_id = match m.get("node_id") {
        Some(Json::Number(n, ..)) => @core.NodeId::from_int(n.to_int())
        _ =>
          raise @json.JsonDecodeError(
            (
              path.add_key("node_id"),
              "UserIntent.SelectNode: 'node_id' must be a number",
            ),
          )
      }
      UserIntent::SelectNode(node_id~)
    }
    "SetCursor" => {
      let position = match m.get("position") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ =>
          raise @json.JsonDecodeError(
            (
              path.add_key("position"),
              "UserIntent.SetCursor: 'position' must be a number",
            ),
          )
      }
      UserIntent::SetCursor(position~)
    }
    "Undo" => UserIntent::Undo
    "Redo" => UserIntent::Redo
    "CommitEdit" => {
      let node_id = match m.get("node_id") {
        Some(Json::Number(n, ..)) => @core.NodeId::from_int(n.to_int())
        _ =>
          raise @json.JsonDecodeError(
            (
              path.add_key("node_id"),
              "UserIntent.CommitEdit: 'node_id' must be a number",
            ),
          )
      }
      let value = match m.get("value") {
        Some(Json::String(s)) => s
        _ =>
          raise @json.JsonDecodeError(
            (
              path.add_key("value"),
              "UserIntent.CommitEdit: 'value' must be a string",
            ),
          )
      }
      UserIntent::CommitEdit(node_id~, value~)
    }
    _ =>
      raise @json.JsonDecodeError(
        (path.add_key("type"), "UserIntent: unknown type '\{type_str}'"),
      )
  }
}
