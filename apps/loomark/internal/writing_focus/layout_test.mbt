///|
test "measurement is reused only for matching width, line height and unchanged focus lines" {
  let source = @writing_focus.TextLines("Before\n\nWriting\n\nAfter")
  let layout = @writing_focus.Layout(source)
  let focus = match layout.focus(8, 8) {
    @writing_focus.Focus::Lines(focus) => focus
    @writing_focus.Focus::Document(_) => fail("expected a line focus")
  }
  let pending = match focus.bounds(width=320.0, line_height=31.0) {
    @writing_focus.Bounds::Lines(pending) => pending
    _ => fail("fresh layout must request line measurements")
  }
  let (_, measured) = pending.between(80.0, 120.0)
  let edited = measured.replace_text("Before\n\nWriting\n\nChanged").unwrap()
  let focus_after_edit = match edited.focus(8, 8) {
    @writing_focus.Focus::Lines(focus) => focus
    @writing_focus.Focus::Document(_) => fail("expected a line focus")
  }
  let retained = match focus_after_edit.bounds(width=320.0, line_height=31.0) {
    @writing_focus.Bounds::Known(range) => range
    _ => fail("unchanged focus lines must retain their measured range")
  }
  assert_eq(retained.start, 80.0)
  assert_eq(retained.end, 120.0)
  let wrong_width = match
    focus_after_edit.bounds(width=400.0, line_height=31.0) {
    @writing_focus.Bounds::Lines(pending) => pending
    _ => fail("a width change must request a fresh measurement")
  }
  match wrong_width.layout_sync {
    @writing_focus.LayoutSync::CopyStyles(width) => assert_eq(width, 400.0)
    _ => fail("a width change must synchronize mirror styles")
  }
  let new_line_height = match
    focus_after_edit.bounds(width=320.0, line_height=25.5) {
    @writing_focus.Bounds::Lines(pending) => pending
    _ => fail("a line height change must request a fresh measurement")
  }
  match new_line_height.layout_sync {
    @writing_focus.LayoutSync::CopyStyles(width) => assert_eq(width, 320.0)
    _ => fail("a line height change must synchronize mirror styles")
  }
  let fresh = @writing_focus.Layout(measured.source())
  let fresh_focus = match fresh.focus(8, 8) {
    @writing_focus.Focus::Lines(focus) => focus
    _ => fail("expected a line focus")
  }
  let fresh_bounds = match fresh_focus.bounds(width=320.0, line_height=31.0) {
    @writing_focus.Bounds::Lines(pending) => pending
    _ => fail("a fresh context must not reuse prior measurements")
  }
  match fresh_bounds.layout_sync {
    @writing_focus.LayoutSync::CopyStyles(width) => assert_eq(width, 320.0)
    _ => fail("a fresh context must copy styles even at the same width")
  }
}

///|
test "appending text measures the former EOF instead of retaining infinity" {
  let layout = @writing_focus.Layout(
    @writing_focus.TextLines("Before\n\nWriting"),
  )
  let focus = match layout.focus(15, 15) {
    @writing_focus.Focus::Lines(focus) => focus
    @writing_focus.Focus::Document(_) => fail("expected a line focus")
  }
  let boundary = match focus.bounds(width=280.0, line_height=31.0) {
    @writing_focus.Bounds::LineStart(boundary) => boundary
    _ => fail("former final paragraph must have a start boundary")
  }
  assert_eq(boundary.line, 2)
  match boundary.layout_sync {
    @writing_focus.LayoutSync::CopyStyles(width) => assert_eq(width, 280.0)
    _ => fail("a fresh context must synchronize mirror styles")
  }
  let (range, measured) = boundary.at(75.0)
  assert_eq(range.start, 75.0)
  assert_eq(range.end, @double.infinity)
  let confirmed_focus = match measured.focus(15, 15) {
    @writing_focus.Focus::Lines(focus) => focus
    @writing_focus.Focus::Document(_) => fail("expected a line focus")
  }
  assert_true(
    confirmed_focus.bounds(width=280.0, line_height=31.0)
    is @writing_focus.Bounds::Known(_),
  )
  let appended = measured.replace_text("Before\n\nWriting\n\nAfter").unwrap()
  let focus_before_eof = match appended.focus(15, 15) {
    @writing_focus.Focus::Lines(focus) => focus
    @writing_focus.Focus::Document(_) => fail("expected a line focus")
  }
  let boundary = match focus_before_eof.bounds(width=280.0, line_height=31.0) {
    @writing_focus.Bounds::LineEnd(boundary) => boundary
    _ => fail("the former document end needs a finite line end")
  }
  assert_true(boundary.layout_sync is @writing_focus.LayoutSync::Reuse)
  let (range, _) = boundary.at(110.0)
  assert_eq(range.start, 75.0)
  assert_eq(range.end, 110.0)
}

///|
test "deferred edits invalidate only changed focus edges and restoration reuses measurement" {
  let source = @writing_focus.TextLines("Before\n\nWriting\n\nAfter")
  let layout = @writing_focus.Layout(source)
  let focus = match layout.focus(8, 8) {
    @writing_focus.Focus::Lines(focus) => focus
    @writing_focus.Focus::Document(_) => fail("expected a line focus")
  }
  let pending = match focus.bounds(width=320.0, line_height=31.0) {
    @writing_focus.Bounds::Lines(pending) => pending
    _ => fail("fresh layout must request line measurements")
  }
  let (_, measured) = pending.between(80.0, 120.0)
  assert_true(measured.replace_text(source.text()) is None)
  let changed_text = "Before\n\nChanged\n\nAfter"
  let deferred = measured.replace_text(changed_text).unwrap()
  assert_eq(deferred.source().text(), changed_text)
  assert_true(deferred.replace_text(changed_text) is None)
  let deferred_focus = match deferred.focus(8, 8) {
    @writing_focus.Focus::Lines(focus) => focus
    @writing_focus.Focus::Document(_) => fail("expected a line focus")
  }
  let missing_edge = match
    deferred_focus.bounds(width=320.0, line_height=31.0) {
    @writing_focus.Bounds::LineEnd(boundary) => boundary
    _ => fail("an edited focus edge must be measured again")
  }
  assert_eq(missing_edge.line, 2)
  assert_true(missing_edge.layout_sync is @writing_focus.LayoutSync::Reuse)
  let restored = deferred.replace_text(source.text()).unwrap()
  assert_eq(restored.source().text(), source.text())
  assert_true(restored.replace_text(source.text()) is None)
  let restored_focus = match restored.focus(8, 8) {
    @writing_focus.Focus::Lines(focus) => focus
    @writing_focus.Focus::Document(_) => fail("expected a line focus")
  }
  let restored_range = match
    restored_focus.bounds(width=320.0, line_height=31.0) {
    @writing_focus.Bounds::Known(range) => range
    _ => fail("restored text must reuse its original measurement")
  }
  assert_eq(restored_range.start, 80.0)
  assert_eq(restored_range.end, 120.0)
}

///|
test "invalid completion leaves original layout available for a valid completion" {
  let layout = @writing_focus.Layout(
    @writing_focus.TextLines("Before\n\nWriting\n\nAfter"),
  )
  let focus = match layout.focus(8, 8) {
    @writing_focus.Focus::Lines(focus) => focus
    @writing_focus.Focus::Document(_) => fail("expected a line focus")
  }
  let pending = match focus.bounds(width=320.0, line_height=31.0) {
    @writing_focus.Bounds::Lines(pending) => pending
    _ => fail("fresh layout must request line measurements")
  }
  let invalid : Result[
    (@writing_focus.Range, @writing_focus.Layout),
    @writing_focus.InvalidRange,
  ] = Ok(pending.between(100.0, 50.0)) catch { error => Err(error) }
  assert_true(invalid is Err(_))
  let still_pending = match focus.bounds(width=320.0, line_height=31.0) {
    @writing_focus.Bounds::Lines(pending) => pending
    _ => fail("failed completion must not mutate the original focus")
  }
  let (range, _) = still_pending.between(80.0, 120.0)
  assert_eq(range.start, 80.0)
  assert_eq(range.end, 120.0)
}

///|
test "mirror edits are diffed against the current source context" {
  let layout = @writing_focus.Layout(
    @writing_focus.TextLines("Before\n\nWriting\n\nAfter"),
  )
  let layout = layout.replace_text("Before\n\nChanged\n\nAfter").unwrap()
  let rendered = @writing_focus.TextLines("Other\n\nWriting\n\nAfter")
  let edit = layout.edit_from(rendered).unwrap()
  assert_eq(edit.first, 0)
  assert_eq(edit.removed, 3)
  assert_eq(edit.inserted.length(), 3)
  assert_eq(edit.inserted[0], "Before")
  assert_eq(edit.inserted[2], "Changed")
  assert_eq(edit.source.text(), "Before\n\nChanged\n\nAfter")
}
