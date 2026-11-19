///|
const MAX_TEXT_BYTES : Int = 1024 * 1024

///|
const MAX_REQUEST_BYTES : Int = 6 * MAX_TEXT_BYTES + 1024

///|
fn decode_mutation(value : Json, deleting~ : Bool) -> @store.Mutation? {
  guard value is Object(fields) &&
    fields.length() == (if deleting { 2 } else { 4 }) else {
    return None
  }
  guard fields.get("operationId") is Some(String(operation_id)) else {
    return None
  }
  guard fields.get("baseRevision") is Some(Number(base_revision, ..)) else {
    return None
  }
  let content = if deleting {
    None
  } else {
    guard fields.get("text") is Some(String(text)) &&
      fields.get("changedAt") is Some(Number(changed_at, ..)) else {
      return None
    }
    Some(@store.Content(text, changed_at)) catch {
      _ => return None
    }
  }
  Some(@store.Mutation(operation_id, base_revision, content)) catch {
    _ => None
  }
}

///|
fn metadata_json(value : @store.Metadata) -> Json {
  match value.summary {
    Some({ preview, changed_at, }) =>
      {
        "id": value.id.to_json(),
        "revision": value.revision.to_json(),
        "deleted": false,
        "preview": preview.to_json(),
        "changedAt": changed_at.to_json(),
      }
    None =>
      {
        "id": value.id.to_json(),
        "revision": value.revision.to_json(),
        "deleted": true,
      }
  }
}

///|
fn document_json(value : @store.Document) -> Json {
  match value.content {
    Some({ text, changed_at, }) =>
      {
        "id": value.id.to_json(),
        "revision": value.revision.to_json(),
        "deleted": false,
        "text": text.to_json(),
        "changedAt": changed_at.to_json(),
      }
    None =>
      {
        "id": value.id.to_json(),
        "revision": value.revision.to_json(),
        "deleted": true,
        "text": Json::null(),
      }
  }
}
