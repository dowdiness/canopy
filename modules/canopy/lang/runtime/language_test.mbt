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
  _hints : @core.IdentityHintConsumer,
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
  project? : (@loom.Parser[@djson.JsonValue], @core.IdentityHintConsumer) -> (
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

///|
test "apply_edit hint policy: only resolved InvalidTarget taints pending hints" {
  let recorded : Ref[Array[Array[@core.IdentityTransform]]] = Ref([])
  let probe : Ref[@incr.Derived[@core.ProjNode[@djson.JsonValue]?]?] = Ref(None)
  let lang = stub_lang(
    (op, ctx) => {
      match op {
        "seed" =>
          EditResult::Edits(
            [{ start: 1, delete_len: 1, inserted: "3" }],
            @core.FocusHint::RestoreCursor,
            Some(@core.IdentityTransform::Wrap(inner=ctx.proj_node.id())),
          )
        "missing" =>
          raise @core.EditError::NodeNotInSourceMap(
            action="Resolve",
            node_id=ctx.proj_node.id(),
          )
        _ => raise @core.EditError::InvalidTarget(detail="illegal move")
      }
    },
    project=fn(parser, identity_hints) {
      let main = default_json_project(parser, identity_hints)
      let hinted = @core.build_projection_memos_with_identity_hints(
        parser.runtime(),
        parser.syntax_tree(),
        @json_proj.syntax_to_proj_node,
        @json_proj.populate_token_spans,
        (old, new_, counter, pending, trace_ref) => {
          recorded.val.push(pending)
          @core.reconcile(old, new_, counter, trace_ref~)
        },
        identity_hints~,
        label="runtime_hint_policy_probe",
      )
      probe.val = Some(hinted.0)
      main
    },
  )
  let (editor, _) = lang.build("error-hint-test")
  editor.set_text("42")
  let probe_memo = probe.val.unwrap()
  // Establish the probe's previous projection without watching it. The seed
  // edit then leaves this memo dirty, allowing the test to inspect one pending
  // batch only after both error paths have run.
  let _ = probe_memo.read_or_abort()
  guard lang.apply_edit(editor, "seed", 0) is Ok(_) else {
    fail("expected seed edit to succeed")
  }
  match lang.apply_edit(editor, "missing", 1) {
    Err(@core.EditError::NodeNotInSourceMap(action~, ..)) =>
      inspect(action, content="Resolve")
    Err(e) => fail("expected NodeNotInSourceMap, got: " + e.message())
    Ok(_) => fail("expected resolution failure")
  }
  match lang.apply_edit(editor, "invalid", 2) {
    Err(@core.EditError::InvalidTarget(detail~)) =>
      inspect(detail, content="illegal move")
    Err(e) => fail("expected InvalidTarget, got: " + e.message())
    Ok(_) => fail("expected legality failure")
  }
  let _ = probe_memo.read_or_abort()
  inspect(recorded.val.length(), content="1")
  let pending = recorded.val[0]
  inspect(pending.length(), content="2")
  inspect(pending[0] is @core.IdentityTransform::Wrap(inner=_), content="true")
  inspect(pending[1] is @core.IdentityTransform::Opaque, content="true")
  inspect(editor.get_text(), content="43")
}

///|
test "apply_edit Edits path: applies spans, returns the patch trace, moves cursor" {
  let lang = stub_lang((_op, _ctx) => {
    EditResult::Edits(
      [{ start: 0, delete_len: 1, inserted: "x" }],
      @core.FocusHint::MoveCursor(position=2),
      None,
    )
  })
  let (editor, _) = lang.build("edits-test")
  editor.set_text("42")
  match lang.apply_edit(editor, "StubOp", 0) {
    Ok(edits) => {
      // The applied patch trace comes back verbatim.
      inspect(edits.length(), content="1")
      inspect(edits[0].inserted, content="x")
      // The spans were spliced into the document and the cursor moved per
      // the FocusHint.
      inspect(editor.get_text(), content="x2")
      inspect(editor.get_cursor(), content="2")
    }
    Err(e) => fail("expected Ok from Edits, got: " + e.message())
  }
}
