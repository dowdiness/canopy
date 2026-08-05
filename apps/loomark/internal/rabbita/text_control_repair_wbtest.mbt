///|
test "rejected insertion maps a non-BMP UTF-16 text cursor back to accepted source" {
  let selection = rejected_text_selection(
    "A😀B",
    "A😀XB",
    @dom_boundary.TextSelection(4, 4, @dom_boundary.NoDirection),
  )
  inspect(selection.start(), content="3")
  inspect(selection.end(), content="3")
}

///|
test "rejected replacement maps a range around the accepted span" {
  let selection = rejected_text_selection(
    "abcdef",
    "abXef",
    @dom_boundary.TextSelection(2, 3, @dom_boundary.Backward),
  )
  inspect(selection.start(), content="2")
  inspect(selection.end(), content="4")
  guard selection.direction() is @dom_boundary.Backward else {
    fail("expected selection direction to be preserved")
  }
}
