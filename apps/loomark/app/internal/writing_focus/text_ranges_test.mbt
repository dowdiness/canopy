///|
test "quote-only lines separate focused paragraphs" {
  let text = "> first\n>\n> second"
  let lines = @writing_focus.TextLines(text)
  let first = lines.focus_lines(0, 0).unwrap()
  let second = lines.focus_lines(text.length(), text.length()).unwrap()
  assert_eq(first.first, 0)
  assert_eq(first.last, 0)
  assert_eq(second.first, 2)
  assert_eq(second.last, 2)
}

///|
test "nested quoted paragraphs exclude leading and trailing empty quote lines" {
  let lines = @writing_focus.TextLines("> >\n> > first\n> >\n> > second\n> >")
  let first = lines.focus_lines(4, 4).unwrap()
  let second = lines.focus_lines(18, 18).unwrap()
  assert_eq(first.first, 1)
  assert_eq(first.last, 1)
  assert_eq(second.first, 3)
  assert_eq(second.last, 3)
}

///|
test "quoted fences keep internal blanks but not the following paragraph" {
  let text = "> ```\n> first\n>\n> second\n> ```\n>\n> next"
  let lines = @writing_focus.TextLines(text)
  let code = lines.focus_lines(0, 0).unwrap()
  let following = lines.focus_lines(text.length(), text.length()).unwrap()
  assert_eq(code.first, 0)
  assert_eq(code.last, 4)
  assert_eq(following.first, 6)
  assert_eq(following.last, 6)
}

///|
test "quoted indented code keeps internal blanks but not the following paragraph" {
  let text = ">     >\n>\n>     second\n>\n> next"
  let lines = @writing_focus.TextLines(text)
  let code = lines.focus_lines(0, 0).unwrap()
  let following = lines.focus_lines(text.length(), text.length()).unwrap()
  assert_eq(code.first, 0)
  assert_eq(code.last, 2)
  assert_eq(following.first, 4)
  assert_eq(following.last, 4)
}

///|
test "empty lines inside fenced code remain in one writing group" {
  let text = "```moonbit\nfirst\n\nsecond\n```\n\nnext"
  let lines = @writing_focus.TextLines(text)
  let focused = lines.focus_lines(11, 11).unwrap()
  assert_eq(focused.first, 0)
  assert_eq(focused.last, 4)
  let following = lines.focus_lines(text.length(), text.length()).unwrap()
  assert_eq(following.first, 6)
  assert_eq(following.last, 6)
}

///|
test "quoted fences keep their empty source lines in the focused group" {
  let lines = @writing_focus.TextLines(
    "> ```\n> first\n\n> second\n> ```\n\nnext",
  )
  let focused = lines.focus_lines(8, 8).unwrap()
  assert_eq(focused.first, 0)
  assert_eq(focused.last, 4)
}

///|
test "blank lines join indented code without absorbing following plain content" {
  let text = "    first\n\n    second\n\nnext"
  let lines = @writing_focus.TextLines(text)
  assert_eq(lines.focus_lines(5, 5).unwrap().last, 2)
  assert_eq(lines.focus_lines(text.length(), text.length()).unwrap().first, 4)
}

///|
test "a selection ending at the next group's start does not focus that group" {
  let lines = @writing_focus.TextLines("😀 first\n\nsecond")
  let focused = lines.focus_lines(2, 10).unwrap()
  assert_eq(focused.first, 0)
  assert_eq(focused.last, 1)
}

///|
test "a caret on a blank writing line keeps the preceding thought readable" {
  let lines = @writing_focus.TextLines("first\n\n\nsecond")
  let focused = lines.focus_lines(7, 7).unwrap()
  assert_eq(focused.first, 0)
  assert_eq(focused.last, 2)
}

///|
test "an empty document still has a writing line" {
  let lines = @writing_focus.TextLines("")
  let focused = lines.focus_lines(0, 0).unwrap()
  assert_eq(focused.first, 0)
  assert_eq(focused.last, 0)
}

///|
test "selection outside its text is rejected rather than clamped" {
  let lines = @writing_focus.TextLines("abc")
  assert_true(lines.focus_lines(0, 4) is Err(_))
  assert_true(lines.focus_lines(2, 1) is Err(_))
}

///|
test "replacing a UTF-16 line updates following offsets without mutating the old index" {
  let original = @writing_focus.TextLines("😀 one\n\nsecond\n\nthird")
  let replacement = original
    .replace_text("😃 one\nnext\n\nsecond\n\nthird")
    .unwrap()
  assert_eq(replacement.first, 0)
  assert_eq(replacement.removed, 1)
  assert_eq(replacement.inserted.to_owned(), ["😃 one", "next"])
  assert_eq(replacement.text_lines.focus_lines(13, 13).unwrap().first, 3)
  assert_eq(original.focus_lines(8, 8).unwrap().first, 2)
}
