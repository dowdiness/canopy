///|
test "an inert editor sends focus to Recent documents in every mode" {
  for mode in [Text, Split, Preview] {
    assert_true(
      editor_focus_target(mode, editor_inert=true, mode_element_inert=true)
      is RecentDocuments,
    )
    assert_true(
      editor_focus_target(mode, editor_inert=false, mode_element_inert=false)
      is CurrentMode,
    )
  }
  // Only Preview's element (its mode tab) is hidden by Focus Mode chrome.
  assert_true(
    editor_focus_target(Preview, editor_inert=false, mode_element_inert=true)
    is FocusModeToggle,
  )
  assert_true(
    editor_focus_target(Text, editor_inert=false, mode_element_inert=true)
    is CurrentMode,
  )
}
