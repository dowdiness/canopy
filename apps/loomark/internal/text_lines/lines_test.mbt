///|
test "replacing a UTF-16 line updates following offsets without mutating the old index" {
  let original = @text_lines.TextLines("😀 one\n\nsecond\n\nthird")
  let updated = original
    .replace_text("😃 one\nnext\n\nsecond\n\nthird")
    .unwrap().source
  assert_eq(updated.text(), "😃 one\nnext\n\nsecond\n\nthird")
  assert_eq(updated.position(13).line, 3)
  assert_eq(original.position(8).line, 2)
  assert_eq(original.text(), "😀 one\n\nsecond\n\nthird")
}

///|
test "text positions after a line break belong to the following line" {
  let lines = @text_lines.TextLines("ab\n\ncd")
  let start = lines.position(0)
  let line_end = lines.position(2)
  let empty = lines.position(3)
  let next = lines.position(4)
  let end = lines.position(6)
  assert_eq((start.line, start.column), (0, 0))
  assert_eq((line_end.line, line_end.column), (0, 2))
  assert_eq((empty.line, empty.column), (1, 0))
  assert_eq((next.line, next.column), (2, 0))
  assert_eq((end.line, end.column), (2, 2))
}

///|
test "panic an offset outside the text is a caller error" {
  @text_lines.TextLines("abc").position(4) |> ignore
}
