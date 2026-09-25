///|
test "preview demand changes only when visibility crosses the Text boundary" {
  let area = @text_area.TextArea::TextArea("visibility-text")
  let engine = @preview.PreviewEngine::PreviewEngine()
  let emit = @cmd.Emit(_ => @cmd.none)
  let (text_only, _) = activate(area, engine, 1, "# First\n", false, emit)
  let (visible, _) = visibility_changed(
    engine, text_only, 1, "# First\n", false, true, emit,
  )
  assert_false(visible == text_only)
  let (still_visible, _) = visibility_changed(
    engine, visible, 1, "# First\n", true, true, emit,
  )
  assert_true(still_visible == visible)
  let (hidden, _) = visibility_changed(
    engine, still_visible, 1, "# First\n", true, false, emit,
  )
  assert_false(hidden == visible)
  let (still_hidden, _) = visibility_changed(
    engine, hidden, 1, "# First\n", false, false, emit,
  )
  assert_true(still_hidden == hidden)
}
