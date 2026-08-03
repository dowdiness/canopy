// Tests for the markdown empty-paragraph sentinel role.
//
// The sentinel rule is intentionally narrow: exact equality with U+200B
// and nothing else. Mixed content containing the sentinel must NOT be
// classified as an empty paragraph.

///|
test "is_empty_paragraph_text: exact sentinel matches" {
  assert_eq(is_empty_paragraph_text(EMPTY_PARAGRAPH_SENTINEL), true)
}

///|
test "is_empty_paragraph_text: empty string is not the sentinel" {
  assert_eq(is_empty_paragraph_text(""), false)
}

///|
test "is_empty_paragraph_text: two sentinels do not match" {
  let s = EMPTY_PARAGRAPH_SENTINEL + EMPTY_PARAGRAPH_SENTINEL
  assert_eq(is_empty_paragraph_text(s), false)
}

///|
test "is_empty_paragraph_text: sentinel mixed with other text does not match" {
  let s = EMPTY_PARAGRAPH_SENTINEL + "a"
  assert_eq(is_empty_paragraph_text(s), false)
  let s2 = "a" + EMPTY_PARAGRAPH_SENTINEL
  assert_eq(is_empty_paragraph_text(s2), false)
}

///|
test "EMPTY_PARAGRAPH_SENTINEL aliases @moji.ZERO_WIDTH_SPACE" {
  assert_eq(EMPTY_PARAGRAPH_SENTINEL, @moji.ZERO_WIDTH_SPACE)
}
