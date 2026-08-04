///| Transport-level error type for byte-stream decoding.
///
/// These failures are wire-format-agnostic: the byte stream ended early, a
/// varint is malformed, or a length-prefixed string is not valid UTF-16.
/// Domain layers (presence, relay, …) own their own *semantic* errors and
/// convert `CodecError` at their boundary, so this package depends on no
/// caller's error type.

///|
pub(all) suberror CodecError {
  UnexpectedEndOfInput
  VarintTooLong
  VarintValueTooLarge
  /// Strict UTF-16 decode failure. `read_string` decodes leniently today via
  /// `Bytes::to_unchecked_string`; this variant reserves the codec's ownership
  /// of UTF-16 decode errors so a strict reader can raise it without inverting
  /// the layering onto a caller's error type.
  InvalidUtf16
}

///|
pub fn CodecError::message(self : CodecError) -> String {
  match self {
    UnexpectedEndOfInput => "unexpected end of input"
    VarintTooLong => "varint too long"
    VarintValueTooLarge => "varint value exceeds maximum safe Int size"
    InvalidUtf16 => "invalid UTF-16 in length-prefixed string"
  }
}
