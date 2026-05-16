// Tests for is_default_ignorable_code_point.
//
// Representative codepoints span the UCD ranges: combining marks,
// format characters in the BMP, variation selectors, BOM, and the
// language-tag block beyond the BMP. Negative cases assert ordinary
// scriptural codepoints (ASCII, CJK, emoji) are NOT default-ignorable.

///|
test "is_default_ignorable_code_point: positive samples" {
  // Mn / Cf representatives across BMP
  assert_eq(is_default_ignorable_code_point(0x00AD), true) // SOFT HYPHEN
  assert_eq(is_default_ignorable_code_point(0x034F), true) // CGJ
  assert_eq(is_default_ignorable_code_point(0x061C), true) // ARABIC LETTER MARK
  assert_eq(is_default_ignorable_code_point(0x200B), true) // ZWSP
  assert_eq(is_default_ignorable_code_point(0x200C), true) // ZWNJ
  assert_eq(is_default_ignorable_code_point(0x200D), true) // ZWJ
  assert_eq(is_default_ignorable_code_point(0x200E), true) // LRM
  assert_eq(is_default_ignorable_code_point(0xFEFF), true) // BOM
  // Variation selectors
  assert_eq(is_default_ignorable_code_point(0xFE0F), true) // VS-16
  assert_eq(is_default_ignorable_code_point(0xE0100), true) // VS-17 (supplementary)
  // Beyond BMP: language tags
  assert_eq(is_default_ignorable_code_point(0xE0001), true) // LANGUAGE TAG
  assert_eq(is_default_ignorable_code_point(0xE0020), true) // TAG SPACE
  // Pin the upper boundary of the merged E0000..E0FFF mega-range
  assert_eq(is_default_ignorable_code_point(0xE0FFF), true) // last codepoint in range
}

///|
test "is_default_ignorable_code_point: boundary just outside range" {
  // Codepoint immediately above the E0000..E0FFF mega-range must NOT be ignorable.
  assert_eq(is_default_ignorable_code_point(0xE1000), false)
}

///|
test "is_default_ignorable_code_point: negative samples" {
  assert_eq(is_default_ignorable_code_point(0x0041), false) // 'A'
  assert_eq(is_default_ignorable_code_point(0x0061), false) // 'a'
  assert_eq(is_default_ignorable_code_point(0x0020), false) // SPACE
  assert_eq(is_default_ignorable_code_point(0x4E00), false) // CJK '一'
  assert_eq(is_default_ignorable_code_point(0x1F600), false) // 😀
  assert_eq(is_default_ignorable_code_point(0x1F1E6), false) // 🇦 RI-A
}

///|
test "ZERO_WIDTH_SPACE constant is U+200B" {
  // The named constant must be exactly the one codepoint, and that
  // codepoint must be default-ignorable.
  inspect(ZERO_WIDTH_SPACE.length(), content="1")
  let (cp, _) = decode_codepoint_at(ZERO_WIDTH_SPACE, 0)
  assert_eq(cp, 0x200B)
  assert_eq(is_default_ignorable_code_point(cp), true)
}
