///|
test "distinct characters keep their first order and whole surrogate pairs" {
  assert_eq(
    @fonts.distinct_characters("𠮷野家の𠮷野家"),
    "𠮷野家の",
  )
  assert_eq(@fonts.distinct_characters(""), "")
}
