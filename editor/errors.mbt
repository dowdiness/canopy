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
  UnknownBop(name~ : String)
  UnknownOpType(op_type~ : String)
  FlatProjUnavailable
  UnhandledOperation(detail~ : String)
  NodeNotInSourceMap(action~ : String, node_id~ : @proj.NodeId)
  NodeNotInRegistry(action~ : String, node_id~ : @proj.NodeId)
  TextTransformFailed(detail~ : String)
  ProjectionEdit(detail~ : String)
}

///|
pub fn TreeEditError::message(self : TreeEditError) -> String {
  match self {
    ExpectedJsonObject => "expected JSON object"
    MissingField(field~) => "missing \{field} field"
    FieldMustBeString(field~) => "\{field} must be a string"
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
