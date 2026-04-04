///|
test "typo_correction_system_prompt is non-empty" {
  let prompt = typo_correction_system_prompt
  assert_true(prompt.length() > 0)
  assert_true(prompt.contains("JSON"))
}

///|
test "structured_edit_system_prompt is non-empty" {
  let prompt = structured_edit_system_prompt
  assert_true(prompt.length() > 0)
  assert_true(prompt.contains("replace"))
}

///|
test "format_edit_user_message includes text and instruction" {
  let msg = format_edit_user_message("line1\nline2\nline3", "Fix line 2")
  assert_true(msg.contains("line1"))
  assert_true(msg.contains("line2"))
  assert_true(msg.contains("Fix line 2"))
  assert_true(msg.contains("1:"))
}
