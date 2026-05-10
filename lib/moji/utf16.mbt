// UTF-16 codepoint decoding helpers.
//
// MoonBit `String` is UTF-16. Surrogate pairs occupy two `String::at`
// indices. These helpers decode one codepoint at a time without aborting
// on lone surrogates (rare in well-formed `String`s but possible at the
// FFI boundary).

///|
/// Decode the codepoint starting at `i` in `text`.
///
/// Returns `(codepoint, next_index)`. For a well-formed surrogate pair,
/// advances by 2; otherwise by 1. Lone surrogates are returned as their
/// code-unit value (0xD800..0xDFFF), which falls through every UAX #29
/// property table to `GCB::Other` — equivalent to default-break behaviour.
///
/// Precondition: `0 <= i < text.length()`.
pub fn decode_codepoint_at(text : String, i : Int) -> (Int, Int) {
  let cu = text.at(i).to_int()
  if cu >= 0xD800 && cu <= 0xDBFF && i + 1 < text.length() {
    let cu2 = text.at(i + 1).to_int()
    if cu2 >= 0xDC00 && cu2 <= 0xDFFF {
      let cp = 0x10000 + (((cu - 0xD800) << 10) | (cu2 - 0xDC00))
      return (cp, i + 2)
    }
  }
  (cu, i + 1)
}

///|
/// True iff `i` is the index of a UTF-16 trailing (low) surrogate inside
/// `text`. Used to test for mid-codepoint offsets.
pub fn is_trailing_surrogate_at(text : String, i : Int) -> Bool {
  if i < 0 || i >= text.length() {
    return false
  }
  let cu = text.at(i).to_int()
  cu >= 0xDC00 && cu <= 0xDFFF
}
