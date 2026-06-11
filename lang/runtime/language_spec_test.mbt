// Blackbox tests for the LanguageSpec bridge. These pin the runtime-owned
// message contract — the "no projection available" guard and the
// NoEditPolicy branches — including paths a concrete language surface may
// not be able to reach (an empty JSON doc still yields a recovered
// projection root, so the guard is unreachable from lang/json/companion).
// Stubs are built over the real JSON grammar/memo pipeline.

///|
/// Spec whose compute_edit is stubbed; Op = String so describe_op is identity.
/// build_memos defaults to the real JSON pipeline; the guard test overrides
/// it with an always-None projection memo.
fn stub_spec(
  compute_edit : (
    String,
    String,
    @core.ProjNode[@djson.JsonValue],
    @core.SourceMap,
  ) -> Result[(Array[@core.SpanEdit], @core.FocusHint)?, String],
  no_edit_policy : @runtime.NoEditPolicy,
  build_memos? : (@loom.Parser[@djson.JsonValue]) -> (
    @incr.Derived[@core.ProjNode[@djson.JsonValue]?],
    @incr.Derived[Map[@core.NodeId, @core.ProjNode[@djson.JsonValue]]],
    @incr.Derived[@core.SourceMap],
  ) = @json_proj.build_json_projection_memos,
) -> @runtime.LanguageSpec[@djson.JsonValue, String] {
  @runtime.LanguageSpec::LanguageSpec(
    make_parser=fn(s, rt) {
      @loom.new_parser(s, @djson.json_grammar, runtime?=rt)
    },
    build_memos~,
    compute_edit~,
    describe_op=fn(op) { op },
    no_edit_policy~,
  )
}

///|
test "apply_edit guard pin: None projection -> no projection available" {
  // build_memos variant whose proj memo always yields None — the
  // known-positive control for the guard branch.
  let spec = stub_spec(
    fn(_op, _src, _proj, _sm) {
      Err("compute_edit must not be reached when projection is None")
    },
    @runtime.NoEditPolicy::ErrorUnhandled,
    build_memos=fn(parser) {
      let (_proj, registry, source_map) = @json_proj.build_json_projection_memos(
        parser,
      )
      let none_proj : @incr.Derived[@core.ProjNode[@djson.JsonValue]?] = @incr.Derived::Derived(
        parser.runtime(),
        fn() { None },
      )
      (none_proj, registry, source_map)
    },
  )
  let editor = spec.new_editor("guard-test")
  editor.set_text("42")
  match spec.apply_edit(editor, "AnyOp", 0) {
    Err(msg) => inspect(msg, content="no projection available")
    Ok(_) => fail("expected Err when projection is None")
  }
}

///|
test "apply_edit policy pin: Ok(None) + ErrorUnhandled -> unhandled edit op" {
  let spec = stub_spec(
    fn(_op, _src, _proj, _sm) { Ok(None) },
    @runtime.NoEditPolicy::ErrorUnhandled,
  )
  let editor = spec.new_editor("policy-test")
  editor.set_text("42")
  match spec.apply_edit(editor, "StubOp", 0) {
    Err(msg) => inspect(msg, content="unhandled edit op: StubOp")
    Ok(_) => fail("expected Err under ErrorUnhandled")
  }
}

///|
test "apply_edit policy pin: Ok(None) + SilentNoOp -> Ok, doc untouched" {
  let spec = stub_spec(
    fn(_op, _src, _proj, _sm) { Ok(None) },
    @runtime.NoEditPolicy::SilentNoOp,
  )
  let editor = spec.new_editor("noop-test")
  editor.set_text("42")
  inspect(spec.apply_edit(editor, "StubOp", 0) is Ok(_), content="true")
  inspect(editor.get_text(), content="42")
}

///|
test "apply_edit passthrough pin: compute Err propagates verbatim" {
  let spec = stub_spec(
    fn(_op, _src, _proj, _sm) { Err("boom") },
    @runtime.NoEditPolicy::ErrorUnhandled,
  )
  let editor = spec.new_editor("err-test")
  editor.set_text("42")
  match spec.apply_edit(editor, "StubOp", 0) {
    Err(msg) => inspect(msg, content="boom")
    Ok(_) => fail("expected Err passthrough")
  }
}
