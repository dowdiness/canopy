///|
priv struct RawSelectionTestContext {
  editor : @markdown.MarkdownEditor
  attachment : @md_markdown.MarkdownSemanticAttachment
  model : DriverModel
}

///|
fn RawSelectionTestContext::RawSelectionTestContext(
  agent_id : String,
  source : String,
) -> RawSelectionTestContext {
  let (editor, attachment) = try! @markdown.MarkdownEditor::with_semantic_attachment(
    agent_id~,
    source~,
  )
  {
    editor,
    attachment,
    model: test_model(try! editor.snapshot(), editor.version()),
  }
}

///|
fn RawSelectionTestContext::selection(
  self : RawSelectionTestContext,
  anchor : Int,
  head : Int,
) -> VersionedRawSelection {
  let selection = try! @markdown.MarkdownDocumentUtf16Selection(
    self.model.document,
    anchor~,
    head~,
  )
  VersionedRawSelection::VersionedRawSelection(
    document_id=self.model.document_id,
    version=self.model.document_version,
    selection~,
  )
}

///|
fn RawSelectionTestContext::commit(
  self : RawSelectionTestContext,
  model : DriverModel,
  selection : VersionedRawSelection,
  inserted : String,
) -> (DriverModel, RawSelectionEditOutcome) {
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let (next, outcome, _) = try! commit_raw_selection_edit(
    self.editor,
    self.attachment,
    model,
    ({ selection, inserted } : RawSelectionEditRequest),
    emit,
  )
  (next, outcome)
}

///|
fn assert_applied_raw_caret(
  outcome : RawSelectionEditOutcome,
  expected : Int,
) -> VersionedRawSelection raise {
  guard outcome is RawSelectionEditOutcome::Applied(selection) else {
    abort("expected an applied Raw selection edit")
  }
  assert_eq(selection.selection.anchor(), expected)
  assert_eq(selection.selection.head(), expected)
  selection
}

///|
test "directed cross-block Raw selections commit one ReplaceText transaction" {
  for
    case in [
      ("raw-selection-forward", 0, 11),
      ("raw-selection-backward", 11, 0),
    ] {
    let (agent_id, anchor, head) = case
    let context = RawSelectionTestContext::RawSelectionTestContext(
      agent_id, "alpha\n\nbeta",
    )
    let before = context.model
    let selection = context.selection(anchor, head)
    assert_eq(selection.selection.is_backward(), anchor > head)

    let (next, outcome) = context.commit(before, selection, "x")
    let accepted = assert_applied_raw_caret(outcome, 1)

    assert_eq(next.document.source(), "x")
    assert_eq(context.editor.snapshot().source(), "x")
    assert_eq(next.source_revision, before.source_revision + 1)
    assert_eq(next.committed_change_count, before.committed_change_count + 1)
    assert_false(next.document_version == before.document_version)
    assert_eq(accepted.document_id, before.document_id)
    assert_eq(accepted.version, next.document_version)
    assert_true(next.raw_selection == Some(accepted))
  }
}

///|
test "normalized Raw edit event consumes the Session selection" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-edit-event", "alpha\n\nbeta",
  )
  let selection = context.selection(11, 0)
  let selected = { ..context.model, raw_selection: Some(selection) }
  let latest_model : @ref.Ref[DriverModel?] = @ref.Ref(Some(selected))
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let raw_input_coordinator = RawInputCoordinator::RawInputCoordinator(None)
  ignore(raw_input_coordinator.enqueue("pending", emit))

  let (next, _) = try! update_editing(
    context.editor,
    context.attachment,
    raw_input_coordinator,
    BlockInputCoordinator::BlockInputCoordinator(),
    selected,
    latest_model,
    RawSelectionEdit(({ selection, inserted: "x" } : RawSelectionEditRequest)),
    emit,
  )

  assert_eq(next.document.source(), "x")
  assert_eq(next.committed_change_count, selected.committed_change_count + 1)
  guard next.raw_selection is Some(selection) else {
    abort("accepted Raw edit must install a Session selection")
  }
  assert_eq(selection.selection.anchor(), 1)
  assert_eq(selection.selection.head(), 1)
  assert_eq(raw_input_coordinator.display_source(next.document.source()), "x")
}

///|
test "collapsed Raw selection inserts and emoji range deletes" {
  let insertion = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-insert", "ab",
  )
  let (inserted, inserted_outcome) = insertion.commit(
    insertion.model,
    insertion.selection(1, 1),
    "x",
  )
  assert_eq(inserted.document.source(), "axb")
  ignore(assert_applied_raw_caret(inserted_outcome, 2))

  let deletion = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-delete-emoji", "a😀b",
  )
  let (deleted, deleted_outcome) = deletion.commit(
    deletion.model,
    deletion.selection(1, 3),
    "",
  )
  assert_eq(deleted.document.source(), "ab")
  ignore(assert_applied_raw_caret(deleted_outcome, 1))
}

///|
test "empty collapsed Raw edit preserves history and accepts the Session caret" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-unchanged", "abc",
  )
  let history_before = try! context.editor.history_since()

  let (next, outcome) = context.commit(
    context.model,
    context.selection(1, 1),
    "",
  )

  guard outcome is RawSelectionEditOutcome::Unchanged(selection) else {
    abort("empty collapsed edit must report an unchanged document")
  }
  assert_eq(next.document.source(), "abc")
  assert_eq(next.document_version, context.model.document_version)
  assert_eq(next.committed_change_count, context.model.committed_change_count)
  assert_eq(selection.selection.anchor(), 1)
  assert_eq(selection.selection.head(), 1)
  assert_true(try! (context.editor.history_since() == history_before))
}

///|
test "accepted Raw caret advances across joined grapheme clusters" {
  let cases = [
    ("raw-selection-combining-caret", "\u{0301}x", "e", 2),
    ("raw-selection-zwj-caret", "👩", "👨‍", 5),
    ("raw-selection-regional-caret", "🇯", "🇺", 4),
  ]
  for case in cases {
    let (agent_id, source, inserted, expected_caret) = case
    let context = RawSelectionTestContext::RawSelectionTestContext(
      agent_id, source,
    )
    let (next, outcome) = context.commit(
      context.model,
      context.selection(0, 0),
      inserted,
    )
    assert_eq(next.document.source(), inserted + source)
    ignore(assert_applied_raw_caret(outcome, expected_caret))
  }
}

///|
test "stale Raw selection is rejected before the editor call" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-stale", "alpha\n\nbeta",
  )
  let stale = context.selection(11, 0)
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)
  let (advanced, accepted, _, _) = try! commit_source(
    context.editor,
    context.model,
    context.model.state,
    "newer",
    "test-advance",
    emit,
  )
  assert_true(accepted)
  let armed = { ..advanced, fail_next_editor_commit: true }
  let history_before = try! context.editor.history_since()

  let (next, outcome) = context.commit(armed, stale, "x")

  assert_true(
    outcome
    is RawSelectionEditOutcome::Rejected(
      RawSelectionEditRejection::StaleVersion
    ),
  )
  assert_true(next == armed)
  assert_eq(context.editor.snapshot().source(), "newer")
  assert_true(try! (context.editor.history_since() == history_before))
  assert_true(next.fail_next_editor_commit)
}

///|
test "wrong-document Raw selection is rejected before the editor call" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-wrong-document", "alpha",
  )
  let selection = context.selection(0, 5)
  let other_document_id = @archive.LoomarkDocumentId::from_string(
    "other-document",
  ) catch {
    _ => abort("test document id must construct")
  }
  let wrong = { ..selection, document_id: other_document_id }
  let armed = { ..context.model, fail_next_editor_commit: true }

  let (next, outcome) = context.commit(armed, wrong, "x")

  assert_true(
    outcome
    is RawSelectionEditOutcome::Rejected(
      RawSelectionEditRejection::WrongDocument
    ),
  )
  assert_true(next == armed)
  assert_eq(context.editor.snapshot().source(), "alpha")
  assert_true(next.fail_next_editor_commit)
}

///|
test "failed Raw selection commit preserves accepted document and selection" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-failure", "alpha\n\nbeta",
  )
  let backward = context.selection(11, 0)
  let before = {
    ..context.model,
    raw_selection: Some(backward),
    fail_next_editor_commit: true,
  }
  let history_before = try! context.editor.history_since()

  let (next, outcome) = context.commit(before, backward, "x")

  assert_true(
    outcome
    is RawSelectionEditOutcome::Rejected(
      RawSelectionEditRejection::EditorCommitFailed
    ),
  )
  assert_eq(next.document, before.document)
  assert_eq(next.document_version, before.document_version)
  assert_eq(next.source_revision, before.source_revision)
  assert_eq(next.committed_change_count, before.committed_change_count)
  assert_true(next.raw_selection == before.raw_selection)
  assert_true(next.raw_selection.unwrap().selection.is_backward())
  assert_eq(context.editor.snapshot().source(), before.document.source())
  assert_true(try! (context.editor.history_since() == history_before))
}

///|
test "Raw selection is revalidated against the bound Session snapshot" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-revalidation", "a😀b",
  )
  let other = try! @markdown.MarkdownEditor(
    agent_id="raw-selection-other-shape",
    source="abcd",
  )
  let other_selection = try! @markdown.MarkdownDocumentUtf16Selection(
    other.snapshot(),
    anchor=2,
    head=3,
  )
  let invalid = VersionedRawSelection::VersionedRawSelection(
    document_id=context.model.document_id,
    version=context.model.document_version,
    selection=other_selection,
  )
  let armed = { ..context.model, fail_next_editor_commit: true }

  let (next, outcome) = context.commit(armed, invalid, "x")

  assert_true(
    outcome
    is RawSelectionEditOutcome::Rejected(
      RawSelectionEditRejection::InvalidSelection
    ),
  )
  assert_true(next == armed)
  assert_eq(context.editor.snapshot().source(), "a😀b")
  assert_true(next.fail_next_editor_commit)
}

///|
test "mode-stale Raw selection is rejected before the editor call" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-mode-stale", "alpha",
  )
  let selection = context.selection(0, 5)
  let blocked = {
    ..context.model,
    state: @core.ApplicationState::ApplicationState(@core.Block),
    fail_next_editor_commit: true,
  }

  let (next, outcome) = context.commit(blocked, selection, "x")

  assert_true(
    outcome
    is RawSelectionEditOutcome::Rejected(RawSelectionEditRejection::ModeStale),
  )
  assert_true(next == blocked)
  assert_eq(context.editor.snapshot().source(), "alpha")
  assert_true(next.fail_next_editor_commit)
}

///|
test "unrelated accepted commits clear a version-bound Raw selection" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-clear-on-commit", "alpha",
  )
  let selected = {
    ..context.model,
    raw_selection: Some(context.selection(5, 0)),
  }
  let emit : @cmd.Emit[DriverEvent] = @cmd.Emit(_ => @rabbita_runtime.none)

  let (next, accepted, _, _) = try! commit_source(
    context.editor,
    selected,
    selected.state,
    "changed",
    "test-replacement",
    emit,
  )

  assert_true(accepted)
  assert_true(next.raw_selection is None)
}

///|
test "Raw selection DOM effect revalidates Session state and unmount" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-effect-decision", "alpha\n\nbeta",
  )
  let backward = context.selection(11, 0)
  let current = { ..context.model, raw_selection: Some(backward) }

  guard raw_selection_effect_value(Some(current), backward) is Some(dom) else {
    abort("current Raw selection must produce one DOM effect value")
  }
  assert_eq(dom.start(), 0)
  assert_eq(dom.end(), 11)
  assert_eq(dom.direction(), @dom_boundary.Backward)
  assert_true(raw_selection_effect_value(None, backward) is None)
  assert_true(
    raw_selection_effect_value(
      Some({
        ..current,
        state: @core.ApplicationState::ApplicationState(@core.Block),
      }),
      backward,
    )
    is None,
  )
  assert_true(
    raw_selection_effect_value(
      Some({ ..current, raw_selection: None }),
      backward,
    )
    is None,
  )
}

///|
test "Raw DOM selection conversion maps normalized CRLF and CR offsets" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-dom-line-endings", "a\r\nb\rc\n",
  )
  let dom = @dom_boundary.TextSelection(2, 4, @dom_boundary.Backward)
  let markdown = try! markdown_document_utf16_selection_from_dom(
    context.model.document,
    dom,
  )

  assert_eq(markdown.anchor(), 5)
  assert_eq(markdown.head(), 3)
  let round_trip = dom_selection_from_markdown_document_utf16(
    context.model.document.source(),
    markdown,
  )
  guard round_trip is Some(round_trip) else {
    abort("valid canonical line-ending boundaries must map back to the DOM")
  }
  assert_eq(round_trip.start(), 2)
  assert_eq(round_trip.end(), 4)
  assert_eq(round_trip.direction(), @dom_boundary.Backward)
}

///|
test "Raw DOM selection conversion rejects offsets beyond normalized value" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-dom-invalid-offset", "a\r\nb",
  )
  let invalid : Result[
    @markdown.MarkdownDocumentUtf16Selection,
    RawDomSelectionConversionError,
  ] = Ok(
    markdown_document_utf16_selection_from_dom(
      context.model.document,
      @dom_boundary.TextSelection(4, 4, @dom_boundary.NoDirection),
    ),
  ) catch {
    error => Err(error)
  }

  assert_true(
    invalid is Err(RawDomSelectionConversionError::DomOffsetOutOfBounds(..)),
  )
}

///|
test "Raw DOM selection conversion preserves forward backward and collapsed direction" {
  let context = RawSelectionTestContext::RawSelectionTestContext(
    "raw-selection-dom-conversion", "alpha\n\nbeta",
  )
  let cases = [
    (
      @dom_boundary.TextSelection(0, 11, @dom_boundary.Forward),
      0,
      11,
      @dom_boundary.Forward,
    ),
    (
      @dom_boundary.TextSelection(0, 11, @dom_boundary.Backward),
      11,
      0,
      @dom_boundary.Backward,
    ),
    (
      @dom_boundary.TextSelection(5, 5, @dom_boundary.NoDirection),
      5,
      5,
      @dom_boundary.NoDirection,
    ),
  ]
  for case in cases {
    let (dom, anchor, head, expected_direction) = case
    let markdown = try! markdown_document_utf16_selection_from_dom(
      context.model.document,
      dom,
    )
    assert_eq(markdown.anchor(), anchor)
    assert_eq(markdown.head(), head)
    let round_trip = dom_selection_from_markdown_document_utf16(
      context.model.document.source(),
      markdown,
    )
    guard round_trip is Some(round_trip) else {
      abort("valid Markdown selection must map back to the Raw DOM")
    }
    assert_eq(round_trip.start(), dom.start())
    assert_eq(round_trip.end(), dom.end())
    assert_eq(round_trip.direction(), expected_direction)
  }
}
