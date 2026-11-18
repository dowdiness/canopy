// Pure wire-payload parsing and error-classification helpers for the sync
// session. Moved from editor/sync_editor_ws.mbt in redesign S2.

///|
using @byte_codec {type Reader}

///|
fn parse_sync_message_json(
  payload : Bytes,
) -> Result[@text.SyncMessage, @wire.ProtocolError] {
  let json_str = payload.to_unchecked_string()
  Ok(@text.SyncMessage::from_json_string(json_str)) catch {
    err => Err(@wire.ProtocolError::InvalidSyncJson(detail=err.message()))
  }
}

///|
fn parse_sync_request_payload(
  payload : Bytes,
) -> Result[(String, String, String), @wire.ProtocolError] {
  let reader = Reader::new(payload)
  let sender = match
    (Ok(@wire.read_string_field(reader, "sender")) catch { e => Err(e) }) {
    Ok(sender) => sender
    Err(err) => return Err(err)
  }
  let request_id = match
    (Ok(@wire.read_string_field(reader, "request_id")) catch { e => Err(e) }) {
    Ok(request_id) => request_id
    Err(err) => return Err(err)
  }
  let version_json = match
    (Ok(@wire.read_string_field(reader, "version_json")) catch { e => Err(e) }) {
    Ok(version_json) => version_json
    Err(err) => return Err(err)
  }
  Ok((sender, request_id, version_json))
}

///|
fn parse_sync_response_payload(
  payload : Bytes,
) -> Result[(String, String, String), @wire.ProtocolError] {
  let reader = Reader::new(payload)
  let sender = match
    (Ok(@wire.read_string_field(reader, "sender")) catch { e => Err(e) }) {
    Ok(sender) => sender
    Err(err) => return Err(err)
  }
  let request_id = match
    (Ok(@wire.read_string_field(reader, "request_id")) catch { e => Err(e) }) {
    Ok(request_id) => request_id
    Err(err) => return Err(err)
  }
  let sync_json = match
    (Ok(@wire.read_string_field(reader, "sync_json")) catch { e => Err(e) }) {
    Ok(sync_json) => sync_json
    Err(err) => return Err(err)
  }
  Ok((sender, request_id, sync_json))
}

///|
fn should_retry_sync_error(err : Error) -> Bool {
  match err {
    @text.TextError::SyncFailed(@sync.Failure::MissingDependency(..)) => true
    @text.TextError::VersionNotFound => true
    @text.TextError::ProjectionRecoveryRequired => true
    _ => false
  }
}
