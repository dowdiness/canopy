///|
const SOURCE_KEY_PREFIX : String = "source/v1/"

///|
const EDITING_DOCUMENT_KEY : String = "editing-document"

///|
fn source_key(document_id : DocumentId) -> String {
  SOURCE_KEY_PREFIX + document_id.value()
}

///|
fn encode_document(document : Document) -> String {
  Json::object({
    "document_id": Json(document.id().value()),
    "text": Json(document.text()),
    "changed_at": Json(document.changed_at().value()),
  }).stringify()
}

///|
fn decode_change_time(value : Json?) -> ChangeTime? {
  guard value is Some(Json::Number(time, ..)) else { return None }
  Some(ChangeTime::parse(time)) catch {
    _ => None
  }
}

///|
fn decode_document(storage_key : String, encoded : String) -> Document? {
  guard storage_key.strip_prefix(SOURCE_KEY_PREFIX) is Some(identity) &&
    !identity.is_empty() else {
    return None
  }
  let value = @json.parse(encoded) catch { _ => return None }
  guard value is Json::Object(fields) &&
    fields.length() == 3 &&
    decode_change_time(fields.get("changed_at")) is Some(changed_at) else {
    return None
  }
  let id = match fields.get("document_id") {
    Some(Json::String(value)) => value
    _ => return None
  }
  let text = match fields.get("text") {
    Some(Json::String(value)) => value
    _ => return None
  }
  guard identity.equal_to_string(id) else { return None }
  let id = DocumentId::parse(id) catch { _ => return None }
  Some(Document::create(id, text, changed_at))
}
