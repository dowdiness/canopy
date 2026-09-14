///|
test "fallback keeps the first line separate from the description" {
  let lead = fallback_lead("\u{0000} first\n\n    indented follow-up\n")
  assert_eq(lead.primary(), "\u{0000} first")
  assert_eq(lead.description(), "    indented follow-up")
}
