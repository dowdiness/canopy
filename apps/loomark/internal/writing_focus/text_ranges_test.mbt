///|
fn focused_lines(
  layout : @writing_focus.Layout,
  start : Int,
  end : Int,
) -> @writing_focus.LineRange raise {
  match layout.focus(start, end) {
    Lines(focus) => focus.lines
    Document(_) => fail("expected a partial document focus")
  }
}

///|
test "quote-only lines separate focused paragraphs" {
  let text = "> first\n>\n> second"
  let layout = @writing_focus.Layout(@writing_focus.TextLines(text))
  let first = focused_lines(layout, 0, 0)
  let second = focused_lines(layout, text.length(), text.length())
  assert_eq(first.first, 0)
  assert_eq(first.last, 0)
  assert_eq(second.first, 2)
  assert_eq(second.last, 2)
}

///|
test "nested quoted paragraphs exclude leading and trailing empty quote lines" {
  let layout = @writing_focus.Layout(
    @writing_focus.TextLines("> >\n> > first\n> >\n> > second\n> >"),
  )
  let first = focused_lines(layout, 4, 4)
  let second = focused_lines(layout, 18, 18)
  assert_eq(first.first, 1)
  assert_eq(first.last, 1)
  assert_eq(second.first, 3)
  assert_eq(second.last, 3)
}

///|
test "quoted fences keep internal blanks but not the following paragraph" {
  let text = "> ```\n> first\n>\n> second\n> ```\n>\n> next"
  let layout = @writing_focus.Layout(@writing_focus.TextLines(text))
  let code = focused_lines(layout, 0, 0)
  let following = focused_lines(layout, text.length(), text.length())
  assert_eq(code.first, 0)
  assert_eq(code.last, 4)
  assert_eq(following.first, 6)
  assert_eq(following.last, 6)
}

///|
test "quoted indented code keeps internal blanks but not the following paragraph" {
  let text = ">     >\n>\n>     second\n>\n> next"
  let layout = @writing_focus.Layout(@writing_focus.TextLines(text))
  let code = focused_lines(layout, 0, 0)
  let following = focused_lines(layout, text.length(), text.length())
  assert_eq(code.first, 0)
  assert_eq(code.last, 2)
  assert_eq(following.first, 4)
  assert_eq(following.last, 4)
}

///|
test "empty lines inside fenced code remain in one writing group" {
  let text = "```moonbit\nfirst\n\nsecond\n```\n\nnext"
  let layout = @writing_focus.Layout(@writing_focus.TextLines(text))
  let focused = focused_lines(layout, 11, 11)
  assert_eq(focused.first, 0)
  assert_eq(focused.last, 4)
  let following = focused_lines(layout, text.length(), text.length())
  assert_eq(following.first, 6)
  assert_eq(following.last, 6)
}

///|
test "quoted fences keep their empty source lines in the focused group" {
  let layout = @writing_focus.Layout(
    @writing_focus.TextLines("> ```\n> first\n\n> second\n> ```\n\nnext"),
  )
  let focused = focused_lines(layout, 8, 8)
  assert_eq(focused.first, 0)
  assert_eq(focused.last, 4)
}

///|
test "blank lines join indented code without absorbing following plain content" {
  let text = "    first\n\n    second\n\nnext"
  let layout = @writing_focus.Layout(@writing_focus.TextLines(text))
  assert_eq(focused_lines(layout, 5, 5).last, 2)
  assert_eq(focused_lines(layout, text.length(), text.length()).first, 4)
}

///|
test "a selection ending at the next group's start does not focus that group" {
  let layout = @writing_focus.Layout(
    @writing_focus.TextLines("😀 first\n\nsecond"),
  )
  let focused = focused_lines(layout, 2, 10)
  assert_eq(focused.first, 0)
  assert_eq(focused.last, 1)
}

///|
test "a caret on a blank writing line keeps the preceding thought readable" {
  let layout = @writing_focus.Layout(
    @writing_focus.TextLines("first\n\n\nsecond"),
  )
  let focused = focused_lines(layout, 7, 7)
  assert_eq(focused.first, 0)
  assert_eq(focused.last, 2)
}

///|
test "an empty document remains fully readable" {
  let layout = @writing_focus.Layout(@writing_focus.TextLines(""))
  match layout.focus(0, 0) {
    Document(range) => {
      assert_eq(range.start, 0.0)
      assert_eq(range.end, @double.infinity)
    }
    Lines(_) => fail("an empty document must not need line measurement")
  }
}

///|
test "selection outside its text is rejected rather than clamped" {
  let layout = @writing_focus.Layout(@writing_focus.TextLines("abc"))
  for (start, end) in [(0, 4), (2, 1)] {
    let result : Result[@writing_focus.Focus, @writing_focus.InvalidSelection] = Ok(
      layout.focus(start, end),
    ) catch {
      error => Err(error)
    }
    match result {
      Err(OutsideText(start=actual_start, end=actual_end, length~)) =>
        assert_eq((actual_start, actual_end, length), (start, end, 3))
      Ok(_) => fail("an invalid selection must not produce a focus")
    }
  }
}

///|
test "replacing a UTF-16 line updates following offsets without mutating the old index" {
  let original = @writing_focus.Layout(
    @writing_focus.TextLines("😀 one\n\nsecond\n\nthird"),
  )
  let updated = original
    .replace_text("😃 one\nnext\n\nsecond\n\nthird")
    .unwrap()
  assert_eq(updated.source().text(), "😃 one\nnext\n\nsecond\n\nthird")
  assert_eq(focused_lines(updated, 13, 13).first, 3)
  assert_eq(focused_lines(original, 8, 8).first, 2)
  assert_eq(original.source().text(), "😀 one\n\nsecond\n\nthird")
}

///|
test "text positions after a line break belong to the following line" {
  let lines = @writing_focus.TextLines("ab\n\ncd")
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
  try lines.position(7) catch {
    OutsideText(start=7, end=7, length=6) => ()
    _ => fail("a position past the text must report its offset")
  } noraise {
    _ => fail("a position past the text must be rejected")
  }
}
