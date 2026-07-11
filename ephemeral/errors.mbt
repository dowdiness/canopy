///| Error type for ephemeral presence encoding/decoding.

///|
pub(all) suberror EphemeralError {
  /// Transport-level failure surfaced from the `byte_codec` decoders
  /// (unexpected EOF, malformed varint, …).
  Codec(@byte_codec.CodecError)
  InvalidBoolValue
  InvalidValueTag
  InvalidPeerKey(key~ : String)
}

///|
pub fn EphemeralError::message(self : EphemeralError) -> String {
  match self {
    Codec(err) => err.message()
    InvalidBoolValue => "invalid bool value"
    InvalidValueTag => "invalid ephemeral value tag"
    InvalidPeerKey(key=_) => "ephemeral key must be a numeric peer ID"
  }
}
