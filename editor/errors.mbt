///| User-facing error types for editor boundary code.

///|
pub(all) suberror EphemeralError {
  UnexpectedEndOfInput
  VarintTooLong
  VarintValueTooLarge
  InvalidBoolValue
  InvalidValueTag
  InvalidPeerKey(key~ : String)
}

///|
pub fn EphemeralError::message(self : EphemeralError) -> String {
  match self {
    UnexpectedEndOfInput => "unexpected end of input"
    VarintTooLong => "varint too long"
    VarintValueTooLarge => "varint value exceeds maximum safe Int size"
    InvalidBoolValue => "invalid bool value"
    InvalidValueTag => "invalid ephemeral value tag"
    InvalidPeerKey(key=_) => "ephemeral key must be a numeric peer ID"
  }
}

///|
pub(all) suberror TreeEditError {
  ExpectedJsonObject
  MissingField(field~ : String)
  FieldMustBeString(field~ : String)
  FieldMustBeNumber(field~ : String)
  UnknownBop(name~ : String)
  UnknownOpType(op_type~ : String)
  FlatProjUnavailable
  UnhandledOperation(detail~ : String)
  NodeNotInSourceMap(action~ : String, node_id~ : @core.NodeId)
  NodeNotInRegistry(action~ : String, node_id~ : @core.NodeId)
  TextTransformFailed(detail~ : String)
  ProjectionEdit(detail~ : String)
}

///|
pub fn TreeEditError::message(self : TreeEditError) -> String {
  match self {
    ExpectedJsonObject => "expected JSON object"
    MissingField(field~) => "missing \{field} field"
    FieldMustBeString(field~) => "\{field} must be a string"
    FieldMustBeNumber(field~) => "\{field} must be a number"
    UnknownBop(name~) => "unknown bop: \{name}"
    UnknownOpType(op_type~) => "unknown op type: \{op_type}"
    FlatProjUnavailable => "No FlatProj available"
    UnhandledOperation(detail~) => "Unhandled tree edit op: \{detail}"
    NodeNotInSourceMap(action~, node_id~) =>
      "\{action}: node \{node_id} not in source map"
    NodeNotInRegistry(action~, node_id~) =>
      "\{action}: node \{node_id} not in registry"
    TextTransformFailed(detail~) => "apply_text_transform: \{detail}"
    ProjectionEdit(detail~) => detail
  }
}

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
