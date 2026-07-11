///|
test "compute_view_patches clears stale ast-grep decorations" {
  let handle = create_editor("analysis-stale-decorations")
  set_text(handle, "x")
  let result = apply_ast_grep_results_json(
    handle, "[{\"byte_start\":0,\"byte_end\":1,\"pattern_id\":\"fn-def\"}]",
  )
  inspect(result, content="ok")
  let initial_patches = compute_view_patches_json(handle)
  assert_true(initial_patches.contains("analysis-match pattern-fn-def"))
  set_text(handle, "xy")
  let stale_patches = compute_view_patches_json(handle)
  assert_false(stale_patches.contains("analysis-match pattern-fn-def"))
  destroy_editor(handle)
}

///|
test "apply_ast_grep_results_json converts byte offsets to utf16 decorations" {
  let handle = create_editor("analysis-unicode-offsets")
  set_text(handle, "éx")
  let result = apply_ast_grep_results_json(
    handle, "[{\"byte_start\":2,\"byte_end\":3,\"pattern_id\":\"unicode-id\"}]",
  )
  inspect(result, content="ok")
  let patches = compute_view_patches_json(handle)
  assert_true(patches.contains("\"from\":1"))
  assert_true(patches.contains("\"to\":2"))
  assert_true(patches.contains("analysis-match pattern-unicode-id"))
  destroy_editor(handle)
}

///|
test "apply_ast_grep_results_json sanitizes pattern ids for css classes" {
  let handle = create_editor("analysis-css-class-sanitize")
  set_text(handle, "x")
  let result = apply_ast_grep_results_json(
    handle, "[{\"byte_start\":0,\"byte_end\":1,\"pattern_id\":\"fn/def:α\"}]",
  )
  inspect(result, content="ok")
  let patches = compute_view_patches_json(handle)
  assert_true(patches.contains("analysis-match pattern-fn-def--"))
  assert_true(patches.contains("\"data\":\"fn/def:α\""))
  destroy_editor(handle)
}
