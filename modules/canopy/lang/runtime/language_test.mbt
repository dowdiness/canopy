// Blackbox tests for the deepened `Language` bridge (ADR 2026-08-07). These
// pin the runtime-owned contract — the "no projection available" guard, the
// `Edits`/`NoEdit` routing, and structured error passthrough — including
// paths a concrete language surface may not reach (an empty JSON doc still
// yields a recovered projection root, so the guard is unreachable from
// lang/json/companion). Stubs are built over the real JSON grammar/memo
// pipeline; Op = String, E = Unit.

///|
/// Default projection: the real JSON 3-memo pipeline, E = Unit.
fn default_json_project(
  parser : @loom.Parser[@djson.JsonValue],
  _hints : Ref[Array[@core.IdentityTransform]],
) -> (
  @incr.Derived[@core.ProjNode[@djson.JsonValue]?],
  @incr.Derived[Map[@core.NodeId, @core.ProjNode[@djson.JsonValue]]],
  @incr.Derived[@core.SourceMap],
  Unit,
) {
  let memos = @json_proj.build_json_projection_memos(parser)
  (memos.0, memos.1, memos.2, ())
}

///|
/// Language whose edit port is stubbed; the guard test overrides `project`
/// with an always-None projection memo.
fn stub_lang(
  edit : (String, EditContext[@djson.JsonValue]) -> EditResult raise @core.EditError,
  project? : (
    @loom.Parser[@djson.JsonValue],
    Ref[Array[@core.IdentityTransform]],
  ) -> (
    @incr.Derived[@core.ProjNode[@djson.JsonValue]?],
    @incr.Derived[Map[@core.NodeId, @core.ProjNode[@djson.JsonValue]]],
    @incr.Derived[@core.SourceMap],
    Unit,
  ) = default_json_project,
) -> Language[@djson.JsonValue, String, Unit] {
  Language::Language(
    parse=(source_id, source, runtime) => {
      @loom.new_parser(source_id, source, @djson.json_grammar, runtime?)
    },
    project~,
    edit~,
    capabilities=_e => @editor.LanguageCapabilities::default(),
  )
}

///|
test "apply_edit guard pin: None projection -> ProjectionUnavailable" {
  // project variant whose proj memo always yields None — the known-positive
  // control for the guard branch.
  let lang = stub_lang(
    (_op, _ctx) => {
      raise @core.EditError::Invariant(
        detail="edit must not be reached when projection is None",
      )
    },
    project=fn(parser, _hints) {
      let (_proj, registry, source_map) = @json_proj.build_json_projection_memos(
        parser,
      )
      let none_proj : @incr.Derived[@core.ProjNode[@djson.JsonValue]?] = @incr.Derived::Derived(
        parser.runtime(),
        fn() { None },
      )
      (none_proj, registry, source_map, ())
    },
  )
  let (editor, _) = lang.build("guard-test")
  editor.set_text("42")
  match lang.apply_edit(editor, "AnyOp", 0) {
    Err(@core.EditError::ProjectionUnavailable) => ()
    Err(e) => fail("expected ProjectionUnavailable, got: " + e.message())
    Ok(_) => fail("expected Err when projection is None")
  }
}

///|
test "apply_edit no-edit pin: language raise propagates" {
  let lang = stub_lang((_op, _ctx) => {
    raise @core.EditError::UnsupportedOperation(
      detail="unhandled edit op: StubOp",
    )
  })
  let (editor, _) = lang.build("no-edit-test")
  editor.set_text("42")
  match lang.apply_edit(editor, "StubOp", 0) {
    Err(@core.EditError::UnsupportedOperation(detail~)) =>
      inspect(detail, content="unhandled edit op: StubOp")
    Err(e) => fail("expected UnsupportedOperation, got: " + e.message())
    Ok(_) => fail("expected Err from language raise")
  }
}

///|
test "apply_edit no-edit pin: NoEdit -> doc untouched" {
  let lang = stub_lang((_op, _ctx) => EditResult::NoEdit)
  let (editor, _) = lang.build("noop-test")
  editor.set_text("42")
  match lang.apply_edit(editor, "StubOp", 0) {
    Ok(edits) => {
      inspect(edits.is_empty(), content="true")
      inspect(editor.get_text(), content="42")
    }
    Err(e) => fail("expected Ok from NoEdit, got: " + e.message())
  }
}

///|
test "apply_edit passthrough pin: compute raise propagates verbatim" {
  let lang = stub_lang((_op, _ctx) => {
    raise @core.EditError::Invariant(detail="boom")
  })
  let (editor, _) = lang.build("err-test")
  editor.set_text("42")
  match lang.apply_edit(editor, "StubOp", 0) {
    Err(@core.EditError::Invariant(detail~)) => inspect(detail, content="boom")
    Err(e) => fail("expected Invariant, got: " + e.message())
    Ok(_) => fail("expected Err passthrough")
  }
}
