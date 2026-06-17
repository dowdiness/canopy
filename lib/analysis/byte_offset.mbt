///|
// Converts an ast-grep UTF-8 byte offset to the UTF-16 code unit offset used
// by Canopy's internal ranges. Must be called at the adapter boundary, not inside
// the analysis layer — byte offsets must never cross the boundary.
// Offsets that fall mid-codepoint snap left to the preceding char boundary.
pub fn byte_offset_to_utf16(source : String, byte_offset : Int) -> Int {
  let mut bytes_seen = 0
  let mut utf16_offset = 0
  for c in source {
    if bytes_seen >= byte_offset {
      break
    }
    let cp = c.to_int()
    bytes_seen += if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
    utf16_offset += if cp >= 0x10000 { 2 } else { 1 }
  }
  utf16_offset
}
