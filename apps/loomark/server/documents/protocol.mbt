///|
const MAX_TEXT_BYTES : Int32 = 1024 * 1024

///|
const MAX_REQUEST_BYTES : Int32 = 6 * MAX_TEXT_BYTES + 1024

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
    "id": Json(value.id),
    "revision": Json(value.revision),
    "deleted": Json(value.deleted),
  }
  match value.preview {
    Some(preview) => fields["preview"] = Json(preview)
    None => ()
  }
  Json::object(fields)
}

///|
fn document_json(value : @store.Document) -> Json {
  let text = match value.text {
    Some(text) => Json(text)
    None => Json::null()
  }
  {
    "id": Json(value.metadata.id),
    "revision": Json(value.metadata.revision),
    "deleted": Json(value.metadata.deleted),
    "text": text,
  }
}
