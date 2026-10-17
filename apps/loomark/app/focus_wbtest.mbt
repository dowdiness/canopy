///|
test "restored editor focus prefers the sidebar when the editor is inert" {
  for mode in [Text, Split, Preview] {
    assert_true(
      restored_editor_focus(mode, editor_inert=true, target_inert=true)
      is FocusSidebar,
    )
    assert_true(
      restored_editor_focus(mode, editor_inert=false, target_inert=false)
      is FocusEditor,
    )
  }
  // Only Preview's target (its mode tab) is hidden by Focus Mode chrome.
  assert_true(
    restored_editor_focus(Preview, editor_inert=false, target_inert=true)
    is FocusToggle,
  )
  assert_true(
    restored_editor_focus(Text, editor_inert=false, target_inert=true)
    is FocusEditor,
  )
}
