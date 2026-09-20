///|
pub(all) suberror StoreError {
  InvalidMutation
  InvalidStoredData
} derive(Debug, Eq)

///|
pub struct Mutation {
  operation_id : String
  base_revision : Double
  text : String?
}

///|
pub fn Mutation::Mutation(
  operation_id : String,
  base_revision : Double,
  text : String?,
) -> Mutation raise StoreError {
  guard valid_identity(operation_id) &&
    valid_revision(base_revision, saved=false) else {
    raise InvalidMutation
  }
  { operation_id, base_revision, text, }
}

///|
pub struct Metadata {
  id : String
  revision : Double
  deleted : Bool
  preview : String?
}

///|
pub struct Document {
  metadata : Metadata
  text : String?
}

///|
pub struct Page {
  documents : ArrayView[Metadata]
  next : String?
}

///|
pub enum CommitResult {
  Saved(revision~ : Double)
  Conflict
  OperationReused
}

///|
pub fn valid_identity(value : String) -> Bool {
  guard value.length() == 36 else { return false }
  for i in 0..<36 {
    if i == 8 || i == 13 || i == 18 || i == 23 {
      guard value[i] == '-' else { return false }
    } else {
      guard value[i] is ('0'..='9' | 'a'..='f' | 'A'..='F') else {
        return false
      }
    }
  }
  value[14] is ('1'..='8') && value[19] is ('8' | '9' | 'a' | 'b' | 'A' | 'B')
}

///|
fn valid_revision(value : Double, saved~ : Bool) -> Bool {
  let minimum = if saved { 1.0 } else { 0.0 }
  let maximum = if saved { 9007199254740991.0 } else { 9007199254740990.0 }
  value >= minimum && value <= maximum && @double.floor(value) == value
}

///|
fn decode_metadata(row : Json) -> Metadata raise StoreError {
  guard row
    is {
      "id": String(id),
      "revision": Number(revision, ..),
      "deleted": Number(deleted, ..),
      "preview": preview,
      ..
    } &&
    valid_identity(id) &&
    valid_revision(revision, saved=true) &&
    (deleted == 0.0 || deleted == 1.0) else {
    raise InvalidStoredData
  }
  let preview = match (deleted, preview) {
    (0.0, String(preview)) if preview.char_length() <= 80 => Some(preview)
    (1.0, Null) => None
    _ => raise InvalidStoredData
  }
  { id, revision, deleted: deleted == 1.0, preview, }
}

///|
fn decode_document(row : Json) -> Document raise StoreError {
  let metadata = decode_metadata(row)
  let text = match row {
    { "text": String(text), .. } if !metadata.deleted => Some(text)
    { "text": Null, .. } if metadata.deleted => None
    _ => raise InvalidStoredData
  }
  { metadata, text, }
}
