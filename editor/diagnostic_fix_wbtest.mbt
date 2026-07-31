///|
fn test_diagnostic_fix(
  source_id : @loom_core.SourceId,
  title : String,
  start : Int,
  end : Int,
  replacement : String,
) -> @loom_core.DiagnosticFix {
  try! @loom_core.DiagnosticFix(title, @loom_core.FixApplicability::Always, [
    @loom_core.TextReplacement(
      @loom_core.SourceSpan(
        source_id,
        try! @loom_core.TextRange::from_offsets(start, end),
      ),
      replacement,
    ),
  ])
}

///|
fn test_diagnostic(
  source_id : @loom_core.SourceId,
  fixes : Array[@loom_core.DiagnosticFix],
) -> @loom_core.Diagnostic {
  @loom_core.Diagnostic(
    source=@loom_core.DiagnosticSource::parser(),
    severity=@loom_core.Diagnostic::lexer_error("fixture").severity(),
    code=Some(@loom_core.DiagnosticCode("test.fix")),
    message="replace source",
    labels=[
      @loom_core.DiagnosticLabel(
        @loom_core.LabelStyle::Primary,
        @loom_core.SourceSpan(
          source_id,
          try! @loom_core.TextRange::from_offsets(1, 2),
        ),
        Some("replace this range"),
      ),
    ],
    notes=["apply the suggested edit"],
    fixes~,
  )
}

///|
test "diagnostic fix publication renders source and applies exactly once" {
  let editor = try! @probe.new_test_editor("diagnostic-fix-current")
  editor.set_text_and_record("abcd", 100)
  let source_id = editor.parser_source_id()
  let state = ViewUpdateState::ViewUpdateState()
  let rows = state.publish_diagnostics(
    editor,
    @loom_core.DiagnosticSet::single(
      test_diagnostic(source_id, [
        test_diagnostic_fix(source_id, "replace bc", 1, 3, "X"),
      ]),
    ),
  )
  guard rows is [row] else { fail("expected one diagnostic row") }
  inspect(row.message.contains("<input>"), content="true")
  guard (row.snapshot_id, row.diagnostic_id, row.fixes)
    is (Some(snapshot_id), Some(diagnostic_id), [fix]) else {
    fail("expected one registered fix")
  }
  inspect(fix.id, content="0")
  inspect(fix.title, content="replace bc")
  inspect(fix.applicability, content="always")
  inspect(
    state.apply_diagnostic_fix(
      editor,
      snapshot_id~,
      diagnostic_id~,
      fix_id=fix.id,
      timestamp_ms=101,
    ),
    content="true",
  )
  inspect(editor.get_text(), content="aXd")
  inspect(
    state.apply_diagnostic_fix(
      editor,
      snapshot_id~,
      diagnostic_id~,
      fix_id=fix.id,
      timestamp_ms=102,
    ),
    content="false",
  )
  inspect(editor.get_text(), content="aXd")
}

///|
test "diagnostic fix registry rejects stale version and unknown opaque ids" {
  let editor = try! @probe.new_test_editor("diagnostic-fix-stale")
  editor.set_text_and_record("abcd", 100)
  let source_id = editor.parser_source_id()
  let state = ViewUpdateState::ViewUpdateState()
  let rows = state.publish_diagnostics(
    editor,
    @loom_core.DiagnosticSet::single(
      test_diagnostic(source_id, [
        test_diagnostic_fix(source_id, "replace b", 1, 2, "X"),
      ]),
    ),
  )
  guard rows is [row] else { fail("expected one diagnostic row") }
  let snapshot_id = row.snapshot_id.unwrap()
  let diagnostic_id = row.diagnostic_id.unwrap()
  inspect(
    state.apply_diagnostic_fix(
      editor,
      snapshot_id=snapshot_id + 1,
      diagnostic_id~,
      fix_id=0,
      timestamp_ms=101,
    ),
    content="false",
  )
  inspect(
    state.apply_diagnostic_fix(
      editor,
      snapshot_id~,
      diagnostic_id=diagnostic_id + 1,
      fix_id=0,
      timestamp_ms=101,
    ),
    content="false",
  )
  inspect(
    state.apply_diagnostic_fix(
      editor,
      snapshot_id~,
      diagnostic_id~,
      fix_id=1,
      timestamp_ms=101,
    ),
    content="false",
  )
  editor.insert_at(0, "!", 102)
  inspect(
    state.apply_diagnostic_fix(
      editor,
      snapshot_id~,
      diagnostic_id~,
      fix_id=0,
      timestamp_ms=103,
    ),
    content="false",
  )
  inspect(editor.get_text(), content="!abcd")
}

///|
test "diagnostic fix selection preserves candidate order" {
  let editor = try! @probe.new_test_editor("diagnostic-fix-candidates")
  editor.set_text_and_record("abcd", 100)
  let source_id = editor.parser_source_id()
  let state = ViewUpdateState::ViewUpdateState()
  let rows = state.publish_diagnostics(
    editor,
    @loom_core.DiagnosticSet::single(
      test_diagnostic(source_id, [
        test_diagnostic_fix(source_id, "choose X", 1, 2, "X"),
        test_diagnostic_fix(source_id, "choose Y", 1, 2, "Y"),
      ]),
    ),
  )
  guard rows is [row] else { fail("expected one diagnostic row") }
  guard row.fixes is [first, second] else { fail("expected two fixes") }
  inspect(first.id, content="0")
  inspect(first.title, content="choose X")
  inspect(second.id, content="1")
  inspect(second.title, content="choose Y")
  inspect(
    state.apply_diagnostic_fix(
      editor,
      snapshot_id=row.snapshot_id.unwrap(),
      diagnostic_id=row.diagnostic_id.unwrap(),
      fix_id=second.id,
      timestamp_ms=101,
    ),
    content="true",
  )
  inspect(editor.get_text(), content="aYcd")
}

///|
test "multi-edit diagnostic fix is one isolated undo group" {
  let editor = try! @probe.new_test_editor(
    "diagnostic-fix-undo",
    capture_timeout_ms=500,
  )
  editor.set_text_and_record("abcd", 100)
  let source_id = editor.parser_source_id()
  let fix = try! @loom_core.DiagnosticFix(
    "replace endpoints",
    @loom_core.FixApplicability::Always,
    [
      @loom_core.TextReplacement(
        @loom_core.SourceSpan(
          source_id,
          try! @loom_core.TextRange::from_offsets(0, 1),
        ),
        "X",
      ),
      @loom_core.TextReplacement(
        @loom_core.SourceSpan(
          source_id,
          try! @loom_core.TextRange::from_offsets(3, 4),
        ),
        "Z",
      ),
    ],
  )
  let state = ViewUpdateState::ViewUpdateState()
  let rows = state.publish_diagnostics(
    editor,
    @loom_core.DiagnosticSet::single(test_diagnostic(source_id, [fix])),
  )
  guard rows is [row] else { fail("expected one diagnostic row") }
  inspect(
    state.apply_diagnostic_fix(
      editor,
      snapshot_id=row.snapshot_id.unwrap(),
      diagnostic_id=row.diagnostic_id.unwrap(),
      fix_id=0,
      timestamp_ms=101,
    ),
    content="true",
  )
  inspect(editor.get_text(), content="XbcZ")
  editor.insert_at(4, "!", 102)
  inspect(editor.get_text(), content="XbcZ!")
  inspect(editor.undo(), content="true")
  inspect(editor.get_text(), content="XbcZ")
  inspect(editor.undo(), content="true")
  inspect(editor.get_text(), content="abcd")
  inspect(editor.undo(), content="true")
  inspect(editor.get_text(), content="")
}

///|
test "foreign-source fixes are not registered as current-source actions" {
  let editor = try! @probe.new_test_editor("diagnostic-fix-foreign")
  editor.set_text("abcd")
  let source_id = editor.parser_source_id()
  let other_source = @loom_core.SourceId("other-source")
  let state = ViewUpdateState::ViewUpdateState()
  let rows = state.publish_diagnostics(
    editor,
    @loom_core.DiagnosticSet::single(
      test_diagnostic(source_id, [
        test_diagnostic_fix(other_source, "foreign", 1, 2, "X"),
      ]),
    ),
  )
  guard rows is [row] else { fail("expected one diagnostic row") }
  @debug.assert_eq(row.snapshot_id, None)
  @debug.assert_eq(row.diagnostic_id, None)
  inspect(row.fixes.length(), content="0")
}
