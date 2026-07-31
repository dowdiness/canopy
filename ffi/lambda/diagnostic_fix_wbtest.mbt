///|
fn reset_diagnostic_fix_handles() -> Unit {
  lambda_registry.clear()
  pretty_view_states.clear()
  last_created_handle.val = None
}

///|
test "Lambda missing-else fix applies through revision-bound FFI and clears" {
  reset_diagnostic_fix_handles()
  let handle = create_editor("lambda-diagnostic-fix")
  set_text(handle, "if x then y")
  let published = compute_view_patches_json(handle)
  inspect(
    published.contains("\"code\":\"loom.lambda.expected_else\""),
    content="true",
  )
  inspect(published.contains("\"snapshot_id\":0"), content="true")
  inspect(published.contains("\"diagnostic_id\":0"), content="true")
  inspect(
    published.contains("\"title\":\"Insert missing else branch\""),
    content="true",
  )
  inspect(handle_diagnostic_fix_intent(handle, 0, 0, 0, 101), content="true")
  inspect(get_text(handle), content="if x then y else _")
  inspect(handle_diagnostic_fix_intent(handle, 0, 0, 0, 102), content="false")
  let cleared = compute_view_patches_json(handle)
  inspect(
    cleared.contains("\"code\":\"loom.lambda.expected_else\""),
    content="false",
  )
  inspect(
    cleared.contains("\"code\":\"lambda.unresolved_reference\""),
    content="true",
  )
  destroy_editor(handle)
}

///|
test "Lambda diagnostic fix FFI rejects stale publication after source edit" {
  reset_diagnostic_fix_handles()
  let handle = create_editor("lambda-diagnostic-fix-stale")
  set_text(handle, "if x then y")
  let published = compute_view_patches_json(handle)
  inspect(published.contains("\"snapshot_id\":0"), content="true")
  handle_text_intent(handle, 0, 0, " ", 101)
  inspect(handle_diagnostic_fix_intent(handle, 0, 0, 0, 102), content="false")
  inspect(get_text(handle), content=" if x then y")
  destroy_editor(handle)
}
