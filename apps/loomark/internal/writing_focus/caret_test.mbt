///|
fn caret(
  x : Double,
  y : Double,
  scroll_top? : Double = 0.0,
) -> @writing_focus.Caret {
  { x, y, scroll_top, }
}

///|
test "navigation glides but typing keeps pace with the character" {
  guard @writing_focus.caret_move(
      caret(10.0, 40.0),
      caret(19.0, 40.0),
      Navigation,
    )
    is Glide else {
    fail("navigation through unchanged text must glide")
  }
  guard @writing_focus.caret_move(caret(10.0, 40.0), caret(19.0, 40.0), Edit)
    is Jump else {
    fail("typing must move with the character")
  }
}

///|
test "scrolling or a new layout moves the caret with the text" {
  guard @writing_focus.caret_move(
      caret(10.0, 40.0),
      caret(10.0, 40.0, scroll_top=30.0),
      Navigation,
    )
    is Scroll else {
    fail("a scroll must neither glide nor restart the blink")
  }
  guard @writing_focus.caret_move(
      caret(10.0, 40.0),
      caret(10.0, 71.0, scroll_top=31.0),
      Navigation,
    )
    is Jump else {
    fail("a new line that scrolls must jump with the text")
  }
  guard @writing_focus.caret_move(caret(10.0, 40.0), caret(24.0, 40.0), Reflow)
    is Jump else {
    fail("a resized layout must not glide")
  }
  guard @writing_focus.caret_move(caret(10.0, 40.0), caret(10.0, 40.0), Reflow)
    is Still else {
    fail("an unchanged caret must keep its blink")
  }
}

///|
test "only a collapsed selection in a focused, editable area draws a caret" {
  guard @writing_focus.selection_end(4, 4, backward=false, editable_focus=true)
    is Collapsed(4) else {
    fail("a collapsed selection, including an IME composition caret, is drawn")
  }
  guard @writing_focus.selection_end(4, 6, backward=false, editable_focus=true)
    is Endpoint(6) else {
    fail("a forward selection, including a converted clause, ends at its end")
  }
  guard @writing_focus.selection_end(4, 6, backward=true, editable_focus=true)
    is Endpoint(4) else {
    fail("a backward selection ends at its start")
  }
  guard @writing_focus.selection_end(4, 4, backward=false, editable_focus=false)
    is Endpoint(4) else {
    fail("an unfocused or read-only area keeps the native rendering")
  }
}

///|
test "a caret measured on the same text and offset is reused; others are measured by cause" {
  let measured : @writing_focus.MeasuredCaret = { offset: 7, x: 12.5, y: 40.0, }
  match @writing_focus.caret_measure(SameText(measured), 7) {
    Cached({ x: 12.5, y: 40.0, .. }) => ()
    _ => fail("an unchanged caret must not read layout")
  }
  match @writing_focus.caret_measure(SameText(measured), 8) {
    Measure(Navigation) => ()
    _ => fail("a move through unchanged text is navigation")
  }
  match @writing_focus.caret_measure(OtherText, 7) {
    Measure(Edit) => ()
    _ => fail("a caret on changed text is an edit")
  }
  match @writing_focus.caret_measure(Unmeasured, 7) {
    Measure(Reflow) => ()
    _ => fail("a caret on a rebuilt layout is a reflow")
  }
}

///|
test "the bar stays inside the content box like the native caret" {
  assert_eq(
    @writing_focus.drawn_caret_x(0.25, layer_width=680.0, half_width=0.75),
    0.75,
  )
  assert_eq(
    @writing_focus.drawn_caret_x(698.25, layer_width=680.0, half_width=0.75),
    679.25,
  )
  assert_eq(
    @writing_focus.drawn_caret_x(19.5, layer_width=680.0, half_width=0.75),
    19.5,
  )
}

///|
test "a caret is marked by the glyph after it, or by the last glyph at a line end" {
  guard @writing_focus.caret_glyph("", 0) is EmptyLine else {
    fail("an empty line has no glyph")
  }
  guard @writing_focus.caret_glyph("ab", 1) is Before(start=1, end=2) else {
    fail("a caret inside a line is the left edge of the next glyph")
  }
  guard @writing_focus.caret_glyph("ab", 2) is After(start=1, end=2) else {
    fail("a caret at the line end is the right edge of the last glyph")
  }
  // U+1F600 is the surrogate pair D83D DE00.
  guard @writing_focus.caret_glyph("a\u{1F600}", 1) is Before(start=1, end=3) else {
    fail("a glyph before the caret spans its whole surrogate pair")
  }
  guard @writing_focus.caret_glyph("a\u{1F600}", 3) is After(start=1, end=3) else {
    fail("a glyph after the caret spans its whole surrogate pair")
  }
}
