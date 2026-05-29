///| Error type for ephemeral presence encoding/decoding.

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
