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
  // tail (same as new_generic).
  editor.set_text("f(x) y")
  let _ = editor.get_proj_node()
  inspect(editor.get_text(), content="f(x) y")
}

///|
test "new_with_builder shares the caller's hint channel with apply_span_edits" {
  // The Ref threaded in as `identity_hints?` must be the editor's
  // pending_transforms: a hint pushed by the apply path lands in the same
  // Ref the caller owns (and passes to the projection memo builder).
  let hints : Ref[Array[@core.IdentityTransform]] = Ref([])
  let (editor, _) = @editor.SyncEditor::new_with_builder(
    "test",
    (source_id, source, runtime) => {
      @loom.new_parser(source_id, source, test_grammar, runtime?)
    },
    fn(parser, _channel) {
      let memos = build_test_projection_memos(parser)
      (memos.0, memos.1, memos.2, @editor.LanguageCapabilities::default(), ())
    },
    identity_hints=hints,
  )
  // The channel handed to build_parts is the same Ref the caller threaded
  // in: the apply path's push must be visible on `hints`.
  editor.set_text("a b")
  editor.apply_span_edits(
    [{ start: 0, delete_len: 1, inserted: "x" }],
    @core.FocusHint::RestoreCursor,
    0,
    hint=@core.IdentityTransform::Opaque,
  )
  inspect(hints.val.length(), content="1")
}
