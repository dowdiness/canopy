///|
const SOURCE_KEY_PREFIX : String = "source/v1/"

///|
const EDITING_DOCUMENT_KEY : String = "editing-document"

///|
fn source_key(document_id : String) -> String? {
  if document_id == "" {
    None
  } else {
    Some(SOURCE_KEY_PREFIX + document_id)
  }
}

///|
fn encode_document(document : Document) -> String {
  Json::object({
    "document_id": document.id().to_json(),
    "text": document.text().to_json(),
  }).stringify()
}

///|
fn decode_document(storage_key : String, encoded : String) -> Document? {
  guard storage_key.strip_prefix(SOURCE_KEY_PREFIX) is Some(identity) &&
    !identity.is_empty() else {
    return None
  }
  let value = @json.parse(encoded) catch { _ => return None }
  guard value is Json::Object(fields) && fields.length() == 2 else {
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
  Some(Document::create(id, text) catch { _ => return None })
}
