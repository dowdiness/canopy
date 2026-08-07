// Whitebox tests for `SyncEditor::new_with_builder` (generic language SPI
// deepening, Phase 2). The probe package owns the neutral TestExpr grammar and
// its projection-memo builder, so it is the natural home for constructor-level
// tests that the editor package cannot build.

///|
test "new_with_builder returns the language-owned extras E" {
  let (editor, extras) = @editor.SyncEditor::new_with_builder(
    "test",
    (source_id, source, runtime) => {
      @loom.new_parser(source_id, source, test_grammar, runtime?)
    },
    fn(parser, _channel) {
      let memos = build_test_projection_memos(parser)
      (
        memos.0,
        memos.1,
        memos.2,
        @editor.LanguageCapabilities::default(),
        "extras-42",
      )
    },
  )
  inspect(extras, content="extras-42")
  // The constructed editor is fully functional over the shared construction
  // tail shared by every language constructor.
  editor.set_text("f(x) y")
  let _ = editor.get_proj_node()
  inspect(editor.get_text(), content="f(x) y")
}
