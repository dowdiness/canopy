///|
const SOURCE_KEY_PREFIX : String = "source/v1/"

///|
fn source_key(document_id : String) -> String? {
  guard document_id != "" else { return None }
  Some(SOURCE_KEY_PREFIX + document_id)
}

///|
fn encode_source(source : SourceRecord) -> String {
  encode_document(source.document_id(), source.text())
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
fn encode_document(document_id : String, text : String) -> String {
  Json::object({
    "document_id": Json::string(document_id),
    "text": Json::string(text),
  }).stringify()
}

///|
fn decode_source_value(
  encoded : String,
) -> Result[SourceRecord, SourceDecodeFailure] {
  let value = @json.parse(encoded) catch { _ => return Err(InvalidRecord) }
  guard value is Json::Object(fields) && fields.length() == 2 else {
    return Err(InvalidRecord)
  }
  let document_id = match fields.get("document_id") {
    Some(Json::String(document_id)) if document_id != "" => document_id
    _ => return Err(InvalidRecord)
  }
  match fields.get("text") {
    Some(Json::String(text)) =>
      match SourceRecord::new(document_id, text) {
        Some(source) => Ok(source)
        None => Err(InvalidRecord)
      }
    _ => Err(InvalidRecord)
  }
}
