///|
const SYNC_KEY_PREFIX : String = "sync/"

///|
const SYNC_FRAME_PREFIX : String = "loomark-sync\n"

///|
fn sync_key(account : AccountId, document_id : String) -> String {
  let account_id = account.value()
  SYNC_KEY_PREFIX +
  account_id.length().to_string() +
  "/" +
  account_id +
  "/" +
  document_id
}

///|
fn intern_text(texts : Array[String], text : String) -> Int {
  match texts.view().search_by(existing => existing == text) {
    Some(index) => index
    None => {
      let index = texts.length()
      texts.push(text)
      index
    }
  }
}

///|
fn encode_remote(remote : RemoteDocument, texts : Array[String]) -> Json {
  match remote {
    Missing => Json::object({ "kind": "missing" })
    Present(revision, text) =>
      Json::object({
        "kind": "present",
        "revision": revision.value(),
        "text": intern_text(texts, text),
      })
    Deleted(revision) =>
      Json::object({ "kind": "deleted", "revision": revision.value() })
  }
}

///|
fn decode_text(value : Json?, texts : Array[String]) -> String? {
  guard value is Some(Json::Number(index, ..)) &&
    index >= 0.0 &&
    index < texts.length().to_double() &&
    @double.floor(index) == index else {
    return None
  }
  Some(texts[index.to_int()])
}

///|
fn decode_remote(value : Json, texts : Array[String]) -> RemoteDocument? {
  guard value is Json::Object(fields) else { return None }
  match fields.get("kind") {
    Some(Json::String("missing")) if fields.length() == 1 =>
      Some(RemoteDocument::Missing)
    Some(Json::String("present")) if fields.length() == 3 => {
      guard fields.get("revision") is Some(Json::Number(revision, ..)) &&
        decode_text(fields.get("text"), texts) is Some(text) else {
        return None
      }
      let revision = SavedRevision::parse(revision) catch { _ => return None }
      Some(RemoteDocument::Present(revision, text))
    }
    Some(Json::String("deleted")) if fields.length() == 2 => {
      guard fields.get("revision") is Some(Json::Number(revision, ..)) else {
        return None
      }
      let revision = SavedRevision::parse(revision) catch { _ => return None }
      Some(RemoteDocument::Deleted(revision))
    }
    _ => None
  }
}

///|
fn decode_remote_field(value : Json?, texts : Array[String]) -> RemoteDocument? {
  match value {
    Some(value) => decode_remote(value, texts)
    None => None
  }
}

///|
fn encode_operation(
  operation : PendingOperation,
  texts : Array[String],
) -> Json {
  match operation.content {
    Save(text) =>
      Json::object({
        "kind": "save",
        "operation_id": operation.operation_id.value(),
        "base_revision": operation.base_revision,
        "text": intern_text(texts, text),
      })
    Delete =>
      Json::object({
        "kind": "delete",
        "operation_id": operation.operation_id.value(),
        "base_revision": operation.base_revision,
      })
  }
}

///|
fn decode_operation(value : Json, texts : Array[String]) -> PendingOperation? {
  guard value is Json::Object(fields) else { return None }
  guard fields.get("operation_id") is Some(Json::String(operation_id_value)) &&
    fields.get("base_revision") is Some(Json::Number(base_revision, ..)) &&
    base_revision >= 0.0 &&
    base_revision <= 9007199254740990.0 &&
    @double.floor(base_revision) == base_revision else {
    return None
  }
  let operation_id = OperationId::parse(operation_id_value) catch {
    _ => return None
  }
  match fields.get("kind") {
    Some(Json::String("save")) if fields.length() == 4 =>
      match decode_text(fields.get("text"), texts) {
        Some(text) =>
          Some({
            operation_id,
            base_revision,
            content: PendingContent::Save(text),
          })
        None => None
      }
    Some(Json::String("delete")) if fields.length() == 3 =>
      Some({ operation_id, base_revision, content: PendingContent::Delete, })
    _ => None
  }
}

///|
fn encode_phase(phase : SyncPhase, texts : Array[String]) -> Json {
  match phase {
    Ready => Json::object({ "kind": "ready" })
    Sending(operation) =>
      Json::object({
        "kind": "sending",
        "operation": encode_operation(operation, texts),
      })
    RemoteUpdate(remote) =>
      Json::object({
        "kind": "remote_update",
        "remote": encode_remote(remote, texts),
      })
    Conflict(recovery) =>
      Json::object({ "kind": "conflict", "recovery_document_id": recovery.id() })
  }
}

///|
fn decode_phase(
  value : Json,
  document_id : String,
  texts : Array[String],
) -> SyncPhase? {
  guard value is Json::Object(fields) else { return None }
  match fields.get("kind") {
    Some(Json::String("ready")) if fields.length() == 1 =>
      Some(SyncPhase::Ready)
    Some(Json::String("sending")) if fields.length() == 2 =>
      match fields.get("operation") {
        Some(value) =>
          decode_operation(value, texts).map(operation => {
            SyncPhase::Sending(operation)
          })
        None => None
      }
    Some(Json::String("remote_update")) if fields.length() == 2 =>
      match decode_remote_field(fields.get("remote"), texts) {
        Some(remote) => Some(SyncPhase::RemoteUpdate(remote))
        None => None
      }
    Some(Json::String("conflict")) if fields.length() == 2 => {
      guard fields.get("recovery_document_id")
        is Some(Json::String(recovery_document_id)) else {
        return None
      }
      let recovery = recovery_identity(document_id, recovery_document_id) catch {
        _ => return None
      }
      Some(SyncPhase::Conflict(recovery))
    }
    _ => None
  }
}

///|
fn encode_checkpoint(checkpoint : SyncCheckpoint) -> String {
  let texts : Array[String] = []
  let current = intern_text(texts, checkpoint.document.text())
  let baseline = encode_remote(checkpoint.baseline, texts)
  let phase = encode_phase(checkpoint.phase, texts)
  let header = Json::object({
    "account_id": checkpoint.account.value(),
    "document_id": checkpoint.document.id(),
    "generation": checkpoint.generation,
    "current": current,
    "baseline": baseline,
    "phase": phase,
    "text_lengths": Json::array(texts.map(text => text.length().to_json())),
  }).stringify()
  let output = StringBuilder()
  output
  ..write_string(SYNC_FRAME_PREFIX)
  ..write_string(header.length().to_string())
  ..write_char('\n')
  .write_string(header)
  for text in texts {
    output.write_string(text)
  }
  output.to_string()
}

///|
fn decode_header_length(encoded : String) -> (Int, Int)? {
  guard encoded.has_prefix(SYNC_FRAME_PREFIX) else { return None }
  let mut cursor = SYNC_FRAME_PREFIX.length()
  let start = cursor
  let mut length = 0
  while cursor < encoded.length() && encoded[cursor] != '\n' {
    guard encoded[cursor] is ('0'..='9') else { return None }
    let digit = encoded[cursor].to_int() - '0'.to_int()
    guard length <= (encoded.length() - digit) / 10 else { return None }
    length = length * 10 + digit
    cursor += 1
  }
  guard cursor > start &&
    cursor < encoded.length() &&
    encoded[cursor] == '\n' &&
    (cursor == start + 1 || encoded[start] != '0') else {
    return None
  }
  Some((length, cursor + 1))
}

///|
fn decode_texts(value : Json?, encoded : String, start : Int) -> Array[String]? {
  guard value is Some(Json::Array(length_values)) &&
    length_values.length() >= 1 &&
    length_values.length() <= 4 else {
    return None
  }
  let texts : Array[String] = []
  let mut cursor = start
  for value in length_values {
    guard value is Json::Number(length, ..) &&
      length >= 0.0 &&
      length <= (encoded.length() - cursor).to_double() &&
      @double.floor(length) == length else {
      return None
    }
    let end = cursor + length.to_int()
    let text = encoded[cursor:end].to_owned()
    guard texts.iter().all(existing => existing != text) else { return None }
    texts.push(text)
    cursor = end
  }
  if cursor == encoded.length() {
    Some(texts)
  } else {
    None
  }
}

///|
fn decode_checkpoint(storage_key : String, encoded : String) -> SyncCheckpoint? {
  guard storage_key.strip_prefix(SYNC_KEY_PREFIX) is Some(_) &&
    decode_header_length(encoded) is Some((header_length, header_start)) &&
    header_length <= encoded.length() - header_start else {
    return None
  }
  let payload_start = header_start + header_length
  let header = @json.parse(encoded[header_start:payload_start].to_owned()) catch {
    _ => return None
  }
  guard header is Json::Object(fields) &&
    fields.length() == 7 &&
    decode_texts(fields.get("text_lengths"), encoded, payload_start)
    is Some(texts) else {
    return None
  }
  guard fields.get("account_id") is Some(Json::String(account_id)) &&
    fields.get("document_id") is Some(Json::String(document_id)) &&
    fields.get("generation") is Some(Json::Number(generation, ..)) &&
    decode_text(fields.get("current"), texts) is Some(text) &&
    decode_remote_field(fields.get("baseline"), texts) is Some(baseline) &&
    (match fields.get("phase") {
      Some(value) => decode_phase(value, document_id, texts)
      None => None
    })
    is Some(phase) else {
    return None
  }
  let account = AccountId::parse(account_id) catch { _ => return None }
  guard sync_key(account, document_id) == storage_key else { return None }
  let document = Document::create(document_id, text) catch { _ => return None }
  Some(
    checkpoint_from_storage(account, document, generation, baseline, phase) catch {
      _ => return None
    },
  )
}
