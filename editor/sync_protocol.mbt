///| Deprecated compatibility shims for the sync wire protocol.
///
/// The wire codec moved to `dowdiness/canopy/protocol/wire` in redesign S1
/// (docs/plans/2026-06-11-s1-protocol-wire-extraction.md). These transparent
/// aliases and forwarding functions keep the historical `@editor` surface
/// compiling for downstream consumers; new code should use `@wire` directly.
/// The `SyncTransport` trait (transport seam, S2 scope) lives in
/// `sync_transport.mbt`.

///|
#deprecated("Use @wire.SyncMessage", skip_current_package=true)
pub type SyncMessage = @wire.SyncMessage

///|
#deprecated("Use @wire.ProtocolError", skip_current_package=true)
pub type ProtocolError = @wire.ProtocolError

///|
#deprecated("Use @wire.encode_message", skip_current_package=true)
pub fn encode_message(msg : @wire.SyncMessage) -> Bytes {
  @wire.encode_message(msg)
}

///|
#deprecated("Use @wire.encode_relayed_crdt_ops", skip_current_package=true)
pub fn encode_relayed_crdt_ops(sender : String, payload : Bytes) -> Bytes {
  @wire.encode_relayed_crdt_ops(sender, payload)
}

///|
#deprecated("Use @wire.encode_sync_request", skip_current_package=true)
pub fn encode_sync_request(
  target~ : String,
  request_id~ : String,
  version_json~ : String,
) -> Bytes {
  @wire.encode_sync_request(target~, request_id~, version_json~)
}

///|
#deprecated("Use @wire.encode_sync_response", skip_current_package=true)
pub fn encode_sync_response(
  target~ : String,
  request_id~ : String,
  sync_json~ : String,
) -> Bytes {
  @wire.encode_sync_response(target~, request_id~, sync_json~)
}

///|
#deprecated("Use @wire.decode_message_result", skip_current_package=true)
pub fn decode_message_result(
  data : Bytes,
) -> Result[@wire.SyncMessage, @wire.ProtocolError] {
  @wire.decode_message_result(data)
}

///|
#deprecated("Use @wire.decode_message", skip_current_package=true)
pub fn decode_message(data : Bytes) -> @wire.SyncMessage? {
  @wire.decode_message(data)
}
