///|
/// One Raw source selection together with the exact Session document frontier
/// against which it was read.
priv struct VersionedRawSelection {
  document_id : @archive.LoomarkDocumentId
  version : @markdown.MarkdownDocumentVersion
  selection : @markdown.MarkdownDocumentUtf16Selection
} derive(Eq)

///|
fn VersionedRawSelection::VersionedRawSelection(
  document_id~ : @archive.LoomarkDocumentId,
  version~ : @markdown.MarkdownDocumentVersion,
  selection~ : @markdown.MarkdownDocumentUtf16Selection,
) -> VersionedRawSelection {
  { document_id, version, selection }
}

///|
/// One normalized Raw replacement. Native browser-event pairing is owned by
/// #1204; this value is the Session input that pairing will produce.
priv struct RawSelectionEditRequest {
  selection : VersionedRawSelection
  inserted : String
}

///|
priv enum RawSelectionEditRejection {
  WrongDocument
  StaleVersion
  ModeStale
  InvalidSelection
  EditorCommitFailed
}

///|
priv enum RawSelectionEditOutcome {
  Applied(VersionedRawSelection)
  Unchanged(VersionedRawSelection)
  Rejected(RawSelectionEditRejection)
}

///|
fn markdown_document_utf16_selection_error_detail(
  error : @markdown.MarkdownDocumentUtf16SelectionError,
) -> String {
  match error {
    @markdown.MarkdownDocumentUtf16SelectionError::OutOfBounds(..) =>
      "selection endpoint is out of bounds"
    @markdown.MarkdownDocumentUtf16SelectionError::MidGraphemeBoundary(..) =>
      "selection endpoint is not a grapheme boundary"
  }
}

///|
fn raw_selection_edit_rejection_reason(
  rejection : RawSelectionEditRejection,
) -> String {
  match rejection {
    RawSelectionEditRejection::WrongDocument => "wrong-document"
    RawSelectionEditRejection::StaleVersion => "stale-version"
    RawSelectionEditRejection::ModeStale => "mode-stale"
    RawSelectionEditRejection::InvalidSelection => "invalid-selection"
    RawSelectionEditRejection::EditorCommitFailed => "editor-commit-failed"
  }
}

///|
/// Convert a normalized DOM half-open range into a directed Markdown source
/// selection while the caller still owns the detached document snapshot.
fn markdown_document_utf16_selection_from_dom(
  snapshot : @markdown.MarkdownDocumentSnapshot,
  selection : @dom_boundary.TextSelection,
) -> @markdown.MarkdownDocumentUtf16Selection raise @markdown.MarkdownDocumentUtf16SelectionError {
  let (anchor, head) = match selection.direction() {
    @dom_boundary.Backward => (selection.end(), selection.start())
    @dom_boundary.Forward | @dom_boundary.NoDirection =>
      (selection.start(), selection.end())
  }
  @markdown.MarkdownDocumentUtf16Selection(snapshot, anchor~, head~)
}

///|
/// Convert a directed Markdown source selection to the normalized DOM range
/// plus the direction needed by `setSelectionRange`.
fn dom_selection_from_markdown_document_utf16(
  selection : @markdown.MarkdownDocumentUtf16Selection,
) -> @dom_boundary.TextSelection {
  let direction = if selection.is_collapsed() {
    @dom_boundary.NoDirection
  } else if selection.is_backward() {
    @dom_boundary.Backward
  } else {
    @dom_boundary.Forward
  }
  @dom_boundary.TextSelection(
    selection.range_start(),
    selection.range_end(),
    direction,
  )
}

///|
fn versioned_raw_selection_from_dom(
  model : DriverModel,
  selection : @dom_boundary.TextSelection,
) -> VersionedRawSelection raise @markdown.MarkdownDocumentUtf16SelectionError {
  {
    document_id: model.document_id,
    version: model.document_version,
    selection: markdown_document_utf16_selection_from_dom(
      model.document,
      selection,
    ),
  }
}

///|
fn raw_selection_effect_value(
  latest_model : DriverModel?,
  expected : VersionedRawSelection,
) -> @dom_boundary.TextSelection? {
  guard latest_model is Some(model) else { return None }
  guard raw_selection_mode_applicable(model) else { return None }
  guard model.document_id == expected.document_id else { return None }
  guard model.document_version == expected.version else { return None }
  guard model.raw_selection == Some(expected) else { return None }
  Some(dom_selection_from_markdown_document_utf16(expected.selection))
}

///|
fn raw_selection_mode_applicable(model : DriverModel) -> Bool {
  match model.state.mode() {
    @core.Raw => true
    @core.Preview => model.split_preview_open
    @core.Block => false
  }
}

///|
/// Commit one already-normalized Raw replacement. Validation happens before
/// the shared editor shell so stale or malformed requests cannot consume an
/// editor failure injection or create history.
fn commit_raw_selection_edit(
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  model : DriverModel,
  request : RawSelectionEditRequest,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, RawSelectionEditOutcome, @cmd.Cmd) raise {
  let bound = request.selection
  guard bound.document_id == model.document_id else {
    return (
      model,
      RawSelectionEditOutcome::Rejected(
        RawSelectionEditRejection::WrongDocument,
      ),
      @rabbita_runtime.none,
    )
  }
  guard raw_selection_mode_applicable(model) else {
    return (
      model,
      RawSelectionEditOutcome::Rejected(RawSelectionEditRejection::ModeStale),
      @rabbita_runtime.none,
    )
  }
  guard bound.version == model.document_version &&
    bound.version == editor.version() else {
    return (
      model,
      RawSelectionEditOutcome::Rejected(RawSelectionEditRejection::StaleVersion),
      @rabbita_runtime.none,
    )
  }
  let selection = @markdown.MarkdownDocumentUtf16Selection(
    model.document,
    anchor=bound.selection.anchor(),
    head=bound.selection.head(),
  ) catch {
    _ =>
      return (
        model,
        RawSelectionEditOutcome::Rejected(
          RawSelectionEditRejection::InvalidSelection,
        ),
        @rabbita_runtime.none,
      )
  }
  let range_start = selection.range_start()
  let (committed, result, accepted, changed, persistence_command) = commit_edit_request(
    editor,
    model,
    @markdown.MarkdownEditRequest::ReplaceText(
      start=range_start,
      delete_len=selection.range_end() - range_start,
      inserted=request.inserted,
    ),
    "raw-selection-edit",
    emit,
  )
  let committed = update_preview_document(
    attachment,
    committed,
    preview_requested(model),
    accepted~,
    changed~,
  )
  if !accepted && !(result is Some(@markdown.Unchanged(_))) {
    return (
      committed,
      RawSelectionEditOutcome::Rejected(
        RawSelectionEditRejection::EditorCommitFailed,
      ),
      persistence_command,
    )
  }
  let nominal_caret = range_start + request.inserted.length()
  let caret = @moji.next_grapheme_boundary(
    committed.document.source(),
    nominal_caret,
  )
  let next_selection = @markdown.MarkdownDocumentUtf16Selection(
    committed.document,
    anchor=caret,
    head=caret,
  )
  let versioned = VersionedRawSelection::VersionedRawSelection(
    document_id=committed.document_id,
    version=committed.document_version,
    selection=next_selection,
  )
  (
    { ..committed, raw_selection: Some(versioned) },
    if accepted {
      RawSelectionEditOutcome::Applied(versioned)
    } else {
      RawSelectionEditOutcome::Unchanged(versioned)
    },
    persistence_command,
  )
}
