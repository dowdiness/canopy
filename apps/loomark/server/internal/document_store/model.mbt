///|
#derive(Debug, Eq)
pub(all) suberror StoreError {
  InvalidMutation
  InvalidStoredData
}

///|
/// A present document's text with the client's Change time for it, in
/// milliseconds since the epoch. The server stores the time; it never sets it.
pub struct Content {
  text : String
  changed_at : Double
}

///|
pub fn Content::Content(
  text : String,
  changed_at : Double,
) -> Content raise StoreError {
  guard valid_change_time(changed_at) else { raise InvalidMutation }
  { text, changed_at, }
}

///|
/// `content` is `None` for a deletion.
pub struct Mutation {
  operation_id : String
  base_revision : Double
  content : Content?
}

///|
pub fn Mutation::Mutation(
  operation_id : String,
  base_revision : Double,
  content : Content?,
) -> Mutation raise StoreError {
  guard valid_identity(operation_id) &&
    valid_revision(base_revision, saved=false) else {
    raise InvalidMutation
  }
  { operation_id, base_revision, content, }
}

///|
/// What discovery lists about a present document.
pub struct Summary {
  preview : String
  changed_at : Double
}

///|
/// `summary` is `None` for a tombstone.
pub struct Metadata {
  id : String
  revision : Double
  summary : Summary?
}

///|
/// `content` is `None` for a tombstone.
pub struct Document {
  id : String
  revision : Double
  content : Content?
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
      guard value[i] is ('0'..<='9' | 'a'..<='f' | 'A'..<='F') else {
        return false
      }
    }
  }
  value[14] is ('1'..<='8') && value[19] is ('8' | '9' | 'a' | 'b' | 'A' | 'B')
}

///|
fn valid_revision(value : Double, saved~ : Bool) -> Bool {
  let minimum = if saved { 1.0 } else { 0.0 }
  let maximum = if saved { 9007199254740991.0 } else { 9007199254740990.0 }
  value >= minimum && value <= maximum && @double.floor(value) == value
}

///|
/// Milliseconds since the epoch, as `Date.now()` reports them.
fn valid_change_time(value : Double) -> Bool {
  value >= 0.0 && value <= 9007199254740991.0 && @double.floor(value) == value
}

///|
fn decode_head(row : Json) -> (String, Double, Double?) raise StoreError {
  guard row
    is {
      "id": String(id),
      "revision": Number(revision, ..),
      "deleted": Number(deleted, ..),
      "changed_at": changed_at,
      ..
    } &&
    valid_identity(id) &&
    valid_revision(revision, saved=true) else {
    raise InvalidStoredData
  }
  match (deleted, changed_at) {
    (0.0, Number(changed_at, ..)) if valid_change_time(changed_at) =>
      (id, revision, Some(changed_at))
    (1.0, Null) => (id, revision, None)
    _ => raise InvalidStoredData
  }
}

///|
fn decode_metadata(row : Json) -> Metadata raise StoreError {
  let (id, revision, changed_at) = decode_head(row)
  let summary = match (changed_at, row) {
    (Some(changed_at), { "preview": String(preview), .. }) if preview.char_length() <=
      80 => Some({ preview, changed_at, })
    (None, { "preview": Null, .. }) => None
    _ => raise InvalidStoredData
  }
  { id, revision, summary, }
}

///|
fn decode_document(row : Json) -> Document raise StoreError {
  let (id, revision, changed_at) = decode_head(row)
  let content = match (changed_at, row) {
    (Some(changed_at), { "text": String(text), .. }) =>
      Some({ text, changed_at, })
    (None, { "text": Null, .. }) => None
    _ => raise InvalidStoredData
  }
  { id, revision, content, }
}

///|
pub extend StoreError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend StoreError with Eq::{equal, not_equal}
