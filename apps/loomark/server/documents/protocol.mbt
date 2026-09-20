///|
const MAX_TEXT_BYTES : Int = 1024 * 1024

///|
const MAX_REQUEST_BYTES : Int = 6 * MAX_TEXT_BYTES + 1024

///|
fn decode_mutation(value : Json, deleting~ : Bool) -> @store.Mutation? {
  guard value is Object(fields) &&
    fields.length() == (if deleting { 2 } else { 3 }) else {
    return None
  }
  guard fields.get("operationId") is Some(String(operation_id)) else {
    return None
  }
  guard fields.get("baseRevision") is Some(Number(base_revision, ..)) else {
    return None
  }
  let text = if deleting {
    None
  } else {
    guard fields.get("text") is Some(String(text)) else { return None }
    Some(text)
  }
  Some(@store.Mutation(operation_id, base_revision, text)) catch {
    _ => None
  }
}

///|
fn metadata_json(value : @store.Metadata) -> Json {
  let fields : Map[String, Json] = {
    "id": value.id.to_json(),
    "revision": value.revision.to_json(),
    "deleted": value.deleted.to_json(),
  }
  match value.preview {
    Some(preview) => fields["preview"] = preview.to_json()
    None => ()
  }
  Json::object(fields)
}

///|
fn document_json(value : @store.Document) -> Json {
  let text = match value.text {
    Some(text) => text.to_json()
    None => Json::null()
  }
  {
    "id": value.metadata.id.to_json(),
    "revision": value.metadata.revision.to_json(),
    "deleted": value.metadata.deleted.to_json(),
    "text": text,
  }
}
