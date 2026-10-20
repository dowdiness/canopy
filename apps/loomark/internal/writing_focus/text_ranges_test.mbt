///|
fn groups(text : String) -> @writing_focus.WritingGroups {
  @writing_focus.WritingGroups(@text_lines.TextLines(text))
}

///|
fn focused_lines(
  groups : @writing_focus.WritingGroups,
  start : Int,
  end : Int,
) -> @writing_focus.LineRange raise {
  groups.focus_lines(start, end)
}

///|
test "quote-only lines separate focused paragraphs" {
  let text = "> first\n>\n> second"
  let layout = groups(text)
  let first = focused_lines(layout, 0, 0)
  let second = focused_lines(layout, text.length(), text.length())
  assert_eq(first.first, 0)
  assert_eq(first.last, 0)
  assert_eq(second.first, 2)
  assert_eq(second.last, 2)
}

///|
test "nested quoted paragraphs exclude leading and trailing empty quote lines" {
  let layout = groups("> >\n> > first\n> >\n> > second\n> >")
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
  let layout = groups(text)
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
  let layout = groups(text)
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
  let layout = groups(text)
  let focused = focused_lines(layout, 11, 11)
  assert_eq(focused.first, 0)
  assert_eq(focused.last, 4)
  let following = focused_lines(layout, text.length(), text.length())
  assert_eq(following.first, 6)
  assert_eq(following.last, 6)
}

///|
test "quoted fences keep their empty source lines in the focused group" {
  let layout = groups("> ```\n> first\n\n> second\n> ```\n\nnext")
  let focused = focused_lines(layout, 8, 8)
  assert_eq(focused.first, 0)
  assert_eq(focused.last, 4)
}

///|
test "blank lines join indented code without absorbing following plain content" {
  let text = "    first\n\n    second\n\nnext"
  let layout = groups(text)
  assert_eq(focused_lines(layout, 5, 5).last, 2)
  assert_eq(focused_lines(layout, text.length(), text.length()).first, 4)
}

///|
test "a selection ending at the next group's start does not focus that group" {
  let layout = groups("😀 first\n\nsecond")
  let focused = focused_lines(layout, 2, 10)
  assert_eq(focused.first, 0)
  assert_eq(focused.last, 1)
}

///|
test "a caret on a blank writing line keeps the preceding thought readable" {
  let layout = groups("first\n\n\nsecond")
  let focused = focused_lines(layout, 7, 7)
  assert_eq(focused.first, 0)
  assert_eq(focused.last, 2)
}

///|
test "the outer groups extend to the document edges and inner edges are measured" {
  let text = groups("first\n\nsecond\n\nthird")
  let range = (start, top, bottom) => {
    let focus = text.focus_range(text.focus_lines(start, start), top~, bottom~)
    (focus.start, focus.end)
  }
  assert_eq(range(0, 14.0, 44.0), (0.0, 44.0))
  assert_eq(range(8, 74.0, 104.0), (74.0, 104.0))
  assert_eq(range(15, 134.0, 164.0), (134.0, @double.infinity))
  let empty = groups("")
  let whole = empty.focus_range(empty.focus_lines(0, 0), top=14.0, bottom=44.0)
  assert_eq((whole.start, whole.end), (0.0, @double.infinity))
}

///|
test "selection outside its text is rejected rather than clamped" {
  let layout = groups("abc")
  for (start, end) in [(0, 4), (2, 1)] {
    let result : Result[
      @writing_focus.LineRange,
      @writing_focus.InvalidSelection,
    ] = Ok(layout.focus_lines(start, end)) catch { error => Err(error) }
    match result {
      Err(OutsideText(start=actual_start, end=actual_end, length~)) =>
        assert_eq((actual_start, actual_end, length), (start, end, 3))
      Ok(_) => fail("an invalid selection must not produce a focus")
    }
  }
}
