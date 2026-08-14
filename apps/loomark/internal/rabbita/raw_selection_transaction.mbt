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
/// The immutable beforeinput snapshot paired with a later native input.
priv struct RawBeforeInputCandidate {
  selection : VersionedRawSelection
  input_type : String
  is_composing : Bool
}

///|
fn RawBeforeInputCandidate::RawBeforeInputCandidate(
  selection~ : VersionedRawSelection,
  input_type~ : String,
  is_composing~ : Bool,
) -> RawBeforeInputCandidate {
  { selection, input_type, is_composing }
}

///|
/// The latest native textarea value and caret for one captured input batch.
priv struct RawNativeInputCandidate {
  before_input : RawBeforeInputCandidate
  source : String
  post_input_selection : @dom_boundary.TextSelection
  raw_mode_authorized : Bool
}

///|
fn RawNativeInputCandidate::RawNativeInputCandidate(
  before_input~ : RawBeforeInputCandidate,
  source~ : String,
  post_input_selection~ : @dom_boundary.TextSelection,
) -> RawNativeInputCandidate {
  { before_input, source, post_input_selection, raw_mode_authorized: false }
}

///|
fn RawNativeInputCandidate::authorized(
  before_input~ : RawBeforeInputCandidate,
  source~ : String,
  post_input_selection~ : @dom_boundary.TextSelection,
) -> RawNativeInputCandidate {
  let candidate = RawNativeInputCandidate::RawNativeInputCandidate(
    before_input~,
    source~,
    post_input_selection~,
  )
  { ..candidate, raw_mode_authorized: true }
}

///|
/// Native input observed while an earlier Raw transaction is still in flight.
priv struct DeferredRawInput {
  base_source : String
  input_type : String
  before_input_selection : @dom_boundary.TextSelection
  source : String
  post_input_selection : @dom_boundary.TextSelection
  input_count : Int
}

///|
/// The pre-input frontier needed to complete one deferred native input.
priv struct DeferredRawInputCapture {
  base_source : String
  input_type : String
  selection : @dom_boundary.TextSelection
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
priv suberror RawDomSelectionConversionError {
  DomOffsetOutOfBounds(offset~ : Int, value_length~ : Int)
  InvalidMarkdownSelection(@markdown.MarkdownDocumentUtf16SelectionError)
}

///|
fn raw_dom_selection_conversion_error_detail(
  error : RawDomSelectionConversionError,
) -> String {
  match error {
    RawDomSelectionConversionError::DomOffsetOutOfBounds(offset~, value_length~) =>
      "Raw DOM selection offset " +
      offset.to_string() +
      " is outside normalized UTF-16 length " +
      value_length.to_string()
    RawDomSelectionConversionError::InvalidMarkdownSelection(error) =>
      match error {
        @markdown.MarkdownDocumentUtf16SelectionError::OutOfBounds(..) =>
          "selection endpoint is out of bounds"
        @markdown.MarkdownDocumentUtf16SelectionError::MidGraphemeBoundary(..) =>
          "selection endpoint is not a grapheme boundary"
      }
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
/// Exact value exposed by an HTML textarea after assigning canonical source.
fn raw_textarea_value(source : String) -> String {
  source.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
}

///|
/// Number of canonical UTF-16 units represented by one textarea value unit.
/// HTML textareas normalize CRLF and lone CR line endings to one LF.
fn raw_textarea_source_step(source : String, source_offset : Int) -> Int {
  if source[source_offset] == '\r' &&
    source_offset + 1 < source.length() &&
    source[source_offset + 1] == '\n' {
    2
  } else {
    1
  }
}

///|
/// Map a normalized textarea UTF-16 boundary back to canonical source.
/// The two cursors are necessary because one DOM LF may own two source units.
fn raw_source_offset_from_dom(source : String, dom_offset : Int) -> Int? {
  guard dom_offset >= 0 else { return None }
  let mut source_cursor = 0
  let mut dom_cursor = 0
  while source_cursor < source.length() {
    if dom_cursor == dom_offset {
      return Some(source_cursor)
    }
    source_cursor = source_cursor +
      raw_textarea_source_step(source, source_cursor)
    dom_cursor = dom_cursor + 1
  }
  if dom_cursor == dom_offset {
    Some(source_cursor)
  } else {
    None
  }
}

///|
/// Map a canonical source UTF-16 boundary into the normalized textarea value.
fn raw_dom_offset_from_source(source : String, source_offset : Int) -> Int? {
  guard source_offset >= 0 && source_offset <= source.length() else {
    return None
  }
  let mut source_cursor = 0
  let mut dom_cursor = 0
  while source_cursor < source_offset {
    source_cursor = source_cursor +
      raw_textarea_source_step(source, source_cursor)
    dom_cursor = dom_cursor + 1
  }
  if source_cursor == source_offset {
    Some(dom_cursor)
  } else {
    None
  }
}

///|
/// Convert a normalized DOM half-open range into a directed Markdown source
/// selection while the caller still owns the detached document snapshot.
fn markdown_document_utf16_selection_from_dom(
  snapshot : @markdown.MarkdownDocumentSnapshot,
  selection : @dom_boundary.TextSelection,
) -> @markdown.MarkdownDocumentUtf16Selection raise RawDomSelectionConversionError {
  let source = snapshot.source()
  let value_length = raw_dom_offset_from_source(source, source.length()).unwrap_or(
    0,
  )
  let start = match raw_source_offset_from_dom(source, selection.start()) {
    Some(offset) => offset
    None =>
      raise RawDomSelectionConversionError::DomOffsetOutOfBounds(
        offset=selection.start(),
        value_length~,
      )
  }
  let end = match raw_source_offset_from_dom(source, selection.end()) {
    Some(offset) => offset
    None =>
      raise RawDomSelectionConversionError::DomOffsetOutOfBounds(
        offset=selection.end(),
        value_length~,
      )
  }
  let (anchor, head) = match selection.direction() {
    @dom_boundary.Backward => (end, start)
    @dom_boundary.Forward | @dom_boundary.NoDirection => (start, end)
  }
  @markdown.MarkdownDocumentUtf16Selection(snapshot, anchor~, head~) catch {
    error =>
      raise RawDomSelectionConversionError::InvalidMarkdownSelection(error)
  }
}

///|
/// Convert a directed Markdown source selection to the normalized DOM range
/// plus the direction needed by `setSelectionRange`.
fn dom_selection_from_markdown_document_utf16(
  source : String,
  selection : @markdown.MarkdownDocumentUtf16Selection,
) -> @dom_boundary.TextSelection? {
  guard raw_dom_offset_from_source(source, selection.range_start())
    is Some(start) else {
    return None
  }
  guard raw_dom_offset_from_source(source, selection.range_end()) is Some(end) else {
    return None
  }
  let direction = if selection.is_collapsed() {
    @dom_boundary.NoDirection
  } else if selection.is_backward() {
    @dom_boundary.Backward
  } else {
    @dom_boundary.Forward
  }
  Some(@dom_boundary.TextSelection(start, end, direction))
}

///|
fn normalize_raw_input_candidate(
  model : DriverModel,
  candidate : RawNativeInputCandidate,
) -> RawSelectionEditRequest? {
  let before = candidate.before_input
  guard !before.is_composing && !before.input_type.is_empty() else {
    return None
  }
  guard before.selection.document_id == model.document_id else { return None }
  guard before.selection.version == model.document_version else { return None }
  guard candidate.raw_mode_authorized || raw_selection_mode_applicable(model) else {
    return None
  }

  let selection = @markdown.MarkdownDocumentUtf16Selection(
    model.document,
    anchor=before.selection.selection.anchor(),
    head=before.selection.selection.head(),
  ) catch {
    _ => return None
  }
  let old_source = model.document.source()
  let old_value = raw_textarea_value(old_source)
  let latest_value = raw_textarea_value(candidate.source)
  guard candidate.post_input_selection.start() ==
    candidate.post_input_selection.end() else {
    return None
  }
  let post_offset = candidate.post_input_selection.start()
  guard post_offset >= 0 &&
    post_offset <= latest_value.length() &&
    @moji.is_grapheme_boundary(latest_value, post_offset) else {
    return None
  }
  guard dom_selection_from_markdown_document_utf16(old_source, selection)
    is Some(dom_selection) else {
    return None
  }
  let (change_start, old_end, inserted) = if !selection.is_collapsed() {
    let prefix = old_value.sub(end=dom_selection.start())
    let suffix = old_value.sub(start=dom_selection.end())
    guard latest_value.has_prefix(prefix) && latest_value.has_suffix(suffix) else {
      return None
    }
    let inserted_end = latest_value.length() - suffix.length()
    guard inserted_end >= dom_selection.start() else { return None }
    let inserted = latest_value
      .sub(start=dom_selection.start(), end=inserted_end)
      .to_owned()
    (dom_selection.start(), dom_selection.end(), inserted)
  } else {
    let caret = dom_selection.start()
    let prefix = old_value.sub(end=caret)
    let suffix = old_value.sub(start=caret)
    let inserted_end = latest_value.length() - suffix.length()
    if latest_value.has_prefix(prefix) &&
      latest_value.has_suffix(suffix) &&
      inserted_end > caret {
      let inserted = latest_value.sub(start=caret, end=inserted_end).to_owned()
      (caret, caret, inserted)
    } else {
      let change = @text_change.compute_text_change(old_value, latest_value)
      let old_end = change.start + change.delete_len
      guard change.start <= caret && caret <= old_end else { return None }
      (change.start, old_end, change.inserted)
    }
  }
  guard post_offset == change_start + inserted.length() else { return None }
  let request_selection = if !selection.is_collapsed() {
    selection
  } else {
    let start = match raw_source_offset_from_dom(old_source, change_start) {
      Some(offset) => offset
      None => return None
    }
    let end = match raw_source_offset_from_dom(old_source, old_end) {
      Some(offset) => offset
      None => return None
    }
    @markdown.MarkdownDocumentUtf16Selection(
      model.document,
      anchor=start,
      head=end,
    ) catch {
      _ => return None
    }
  }
  Some({
    selection: VersionedRawSelection::VersionedRawSelection(
      document_id=model.document_id,
      version=model.document_version,
      selection=request_selection,
    ),
    inserted,
  })
}

///|
/// Rebase a deferred native snapshot onto the model that accepted the
/// preceding in-flight transaction. The version guard remains intact because
/// this creates a new candidate at the current document frontier.
fn rebase_deferred_raw_input(
  model : DriverModel,
  deferred : DeferredRawInput,
) -> RawBeforeInputCandidate? {
  let selection = markdown_document_utf16_selection_from_dom(
    model.document,
    deferred.before_input_selection,
  ) catch {
    _ => return None
  }
  Some(
    RawBeforeInputCandidate::RawBeforeInputCandidate(
      selection=VersionedRawSelection::VersionedRawSelection(
        document_id=model.document_id,
        version=model.document_version,
        selection~,
      ),
      input_type=deferred.input_type,
      is_composing=false,
    ),
  )
}

///|
fn versioned_raw_selection_from_dom(
  model : DriverModel,
  selection : @dom_boundary.TextSelection,
) -> VersionedRawSelection raise RawDomSelectionConversionError {
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
  dom_selection_from_markdown_document_utf16(
    model.document.source(),
    expected.selection,
  )
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
  editor_started? : () -> Unit = () => (),
  editor_finished? : () -> Unit = () => (),
  preview_started? : () -> Unit = () => (),
  preview_finished? : () -> Unit = () => (),
  raw_mode_authorized? : Bool = false,
  projection_session? : @ref.Ref[ProjectionSession?],
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
  guard raw_mode_authorized || raw_selection_mode_applicable(model) else {
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
  editor_started()
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
    projection_session?,
  )
  editor_finished()
  preview_started()
  let committed = match projection_session {
    Some(session) =>
      update_preview_document_with_projection(
        attachment,
        session,
        committed,
        preview_requested(model),
        accepted~,
        changed~,
      )
    None =>
      update_preview_after_authority(
        attachment,
        committed,
        preview_requested(model),
        accepted~,
        changed~,
      )
  }
  preview_finished()
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
