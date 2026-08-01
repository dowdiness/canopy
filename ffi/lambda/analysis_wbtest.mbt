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

///|
test "pattern match list exposes current utf16 ranges and drops stale facts" {
  let handle = create_editor("analysis-match-list")
  set_text(handle, "😀\nfn alpha(x : Int) { x }")
  let result = apply_ast_grep_results_json(
    handle, "[{\"byte_start\":5,\"byte_end\":13,\"pattern_id\":\"moonbit-fn-def\"}]",
  )
  inspect(result, content="ok")
  let current = get_pattern_matches_json(handle)
  assert_true(current.contains("\"from\":3"))
  assert_true(current.contains("\"to\":11"))
  assert_true(current.contains("\"pattern_id\":\"moonbit-fn-def\""))
  set_text(handle, "😀\nfn alpha(x : Int) { x } ")
  inspect(get_pattern_matches_json(handle), content="[]")
  set_text(handle, "😀\nfn alpha(x : Int) { x }")
  inspect(get_pattern_matches_json(handle), content="[]")
  destroy_editor(handle)
}

///|
test "ast-grep input rejects invalid byte ranges" {
  let handle = create_editor("analysis-invalid-byte-ranges")
  set_text(handle, "éx")
  for
    matches_json in [
      "[{\"byte_start\":-1,\"byte_end\":1,\"pattern_id\":\"negative\"}]", "[{\"byte_start\":2,\"byte_end\":1,\"pattern_id\":\"reversed\"}]",
      "[{\"byte_start\":0,\"byte_end\":4,\"pattern_id\":\"past-end\"}]",
    ] {
    inspect(
      apply_ast_grep_results_json(handle, matches_json),
      content="parse error: match byte range is out of bounds",
    )
  }
  destroy_editor(handle)
}
