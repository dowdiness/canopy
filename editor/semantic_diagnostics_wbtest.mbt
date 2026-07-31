///|
fn semantic_merge_test_set(message : String) -> @loom_core.DiagnosticSet {
  @loom_core.DiagnosticSet::single(
    @loom_core.Diagnostic(
      source=@loom_core.DiagnosticSource(message),
      severity=@loom_core.Diagnostic::lexer_error("fixture").severity(),
      message~,
    ),
  )
}

///|
test "semantic diagnostics merge only equal source snapshots in producer order" {
  let parser = semantic_merge_test_set("parser")
  let semantic = semantic_merge_test_set("semantic")
  let merged = merge_current_diagnostics(
    "current",
    "current",
    parser,
    Some(("current", semantic)),
  )
  debug_inspect(
    merged.items().map(diagnostic => diagnostic.message()),
    content="[\"parser\", \"semantic\"]",
  )
}

///|
test "semantic diagnostics source mismatch keeps only current parser diagnostics" {
  let merged = merge_current_diagnostics(
    "current",
    "current",
    semantic_merge_test_set("parser"),
    Some(("stale", semantic_merge_test_set("semantic"))),
  )
  debug_inspect(
    merged.items().map(diagnostic => diagnostic.message()),
    content="[\"parser\"]",
  )
}

///|
test "stale parser snapshot publishes no diagnostics" {
  let merged = merge_current_diagnostics(
    "current",
    "stale",
    semantic_merge_test_set("parser"),
    Some(("current", semantic_merge_test_set("semantic"))),
  )
  inspect(merged.length(), content="0")
}

///|
test "diagnostic merge owns a defensive result" {
  let parser = semantic_merge_test_set("parser")
  let semantic = semantic_merge_test_set("semantic")
  let merged = merge_current_diagnostics(
    "current",
    "current",
    parser,
    Some(("current", semantic)),
  )
  parser.push(@loom_core.Diagnostic::lexer_error("late parser mutation"))
  semantic.push(@loom_core.Diagnostic::lexer_error("late semantic mutation"))
  inspect(merged.length(), content="2")
}
