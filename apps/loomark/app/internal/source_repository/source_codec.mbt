///|
const SOURCE_KEY_PREFIX : String = "source/v1/"

///|
fn source_key(document_id : String) -> String? {
  guard document_id != "" else { return None }
  Some(SOURCE_KEY_PREFIX + document_id)
}

///|
fn encode_source(source : SourceRecord) -> String {
  encode_document(
    source.document_id(),
    source.text(),
    source.change_order().value(),
  )
}

///|
fn decode_source(
  key : String,
  encoded : String,
) -> Result[SourceRecord, SourceDecodeFailure] {
  guard key.strip_prefix(SOURCE_KEY_PREFIX) is Some(key_identity) &&
    !key_identity.is_empty() else {
    return Err(InvalidRecord)
  }
  match decode_source_value(encoded) {
    Err(failure) => Err(failure)
    Ok(source) =>
      if key_identity.equal_to_string(source.document_id()) {
        Ok(source)
      } else {
        Err(IdentityMismatch)
      }
  }
}

///|
extern "js" fn encode_document(
  document_id : String,
  text : String,
  change_order : Int64,
) -> String =
  #| (document_id, text, change_order) => JSON.stringify({
  #|   document_id,
  #|   text,
  #|   change_order: Number(change_order),
  #| })

///|
fn decode_source_value(
  encoded : String,
) -> Result[SourceRecord, SourceDecodeFailure] {
  let value = @json.parse(encoded) catch { _ => return Err(InvalidRecord) }
  guard value is Json::Object(fields) else { return Err(InvalidRecord) }
  let legacy_shape = match (fields.get("document_id"), fields.get("text")) {
    (Some(Json::String(document_id)), Some(Json::String(_))) =>
      document_id != ""
    _ => false
  }
  if fields.length() == 2 && legacy_shape {
    return Err(UnsupportedSchema)
  }
  guard fields.length() == 3 else { return Err(InvalidRecord) }
  let document_id = match fields.get("document_id") {
    Some(Json::String(document_id)) if document_id != "" => document_id
    _ => return Err(InvalidRecord)
  }
  let text = match fields.get("text") {
    Some(Json::String(text)) => text
    _ => return Err(InvalidRecord)
  }
  let change_order = match fields.get("change_order") {
    Some(Json::Number(number, ..)) if !number.is_nan() &&
      !number.is_inf() &&
      number >= 0.0 &&
      number <= 9_007_199_254_740_991.0 &&
      number.trunc() == number =>
      match ChangeOrder::from_int64(number.to_int64()) {
        Some(change_order) => change_order
        None => return Err(InvalidRecord)
      }
    _ => return Err(InvalidRecord)
  }
  match SourceRecord::new(document_id, text, change_order~) {
    Some(source) => Ok(source)
    None => Err(InvalidRecord)
  }
}
