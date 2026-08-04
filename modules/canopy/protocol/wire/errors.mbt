///|
pub(all) suberror ProtocolError {
  MessageTooShort(length~ : Int)
  UnsupportedVersion(version~ : Byte)
  UnknownMessageType(msg_type~ : Byte)
  MissingNamespace
  InvalidNamespace(tag~ : Byte)
  MissingRoomControlSubtype
  InvalidRoomControlSubtype(sub_type~ : Byte)
  MissingField(field~ : String)
  InvalidSyncJson(detail~ : String)
  InvalidVersionJson(detail~ : String)
}

///|
pub fn ProtocolError::message(self : ProtocolError) -> String {
  match self {
    MessageTooShort(length~) =>
      "protocol message too short: expected at least 3 bytes, got \{length}"
    UnsupportedVersion(version~) =>
      "unsupported protocol version: \{version.to_int()}"
    UnknownMessageType(msg_type~) =>
      "unknown protocol message type: \{msg_type.to_int()}"
    MissingNamespace => "missing ephemeral namespace byte"
    InvalidNamespace(tag~) =>
      "invalid ephemeral namespace byte: \{tag.to_int()}"
    MissingRoomControlSubtype => "missing room control subtype"
    InvalidRoomControlSubtype(sub_type~) =>
      "invalid room control subtype: \{sub_type.to_int()}"
    MissingField(field~) => "missing \{field} field"
    InvalidSyncJson(detail~) => "invalid sync JSON: \{detail}"
    InvalidVersionJson(detail~) => "invalid version JSON: \{detail}"
  }
}
