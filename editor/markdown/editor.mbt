///|
/// A categorized failure at the headless Markdown editor boundary.
pub(all) suberror MarkdownEditorError {
  InvalidAgentId
  InitializationFailed(detail~ : String)
  ProjectionUnavailable
  InvalidTextRange(start~ : Int, delete_len~ : Int, source_length~ : Int)
  EditFailed(detail~ : String)
}

///|
/// Stable editable block kinds exposed by the Markdown façade.
pub(all) enum MarkdownBlockKind {
  Paragraph
  Heading(level~ : Int)
  UnorderedListItem
  OrderedListItem(start~ : Int, delimiter~ : String)
  CodeBlock(info~ : String)
} derive(Eq, Debug)

///|
/// Immutable, façade-owned snapshot of one supported top-level block.
pub struct MarkdownBlockSnapshot {
  priv node_id : MarkdownNodeId
  priv kind : MarkdownBlockKind
  priv text : String
  priv source_start : Int
  priv source_end : Int
  priv text_start : Int
  priv text_end : Int
  priv marker_start : Int?
  priv marker_end : Int?
  priv fence_open_start : Int?
  priv fence_open_end : Int?
  priv fence_close_start : Int?
  priv fence_close_end : Int?
} derive(Eq, Debug)

///|
pub fn MarkdownBlockSnapshot::node_id(self : Self) -> MarkdownNodeId {
  self.node_id
}

///|
pub fn MarkdownBlockSnapshot::key(self : Self) -> String {
  self.node_id.key()
}

///|
pub fn MarkdownBlockSnapshot::kind(self : Self) -> MarkdownBlockKind {
  self.kind
}

///|
pub fn MarkdownBlockSnapshot::text(self : Self) -> String {
  if @md_sentinel.is_empty_paragraph_text(self.text) {
    ""
  } else {
    self.text
  }
}

///|
/// Retain the parser placeholder only inside the Markdown façade.
fn MarkdownBlockSnapshot::canonical_text(self : Self) -> String {
  self.text
}

///|
pub fn MarkdownBlockSnapshot::source_range(self : Self) -> (Int, Int) {
  (self.source_start, self.source_end)
}

///|
pub fn MarkdownBlockSnapshot::text_range(self : Self) -> (Int, Int) {
  (self.text_start, self.text_end)
}

///|
pub fn MarkdownBlockSnapshot::marker_range(self : Self) -> (Int, Int)? {
  match (self.marker_start, self.marker_end) {
    (Some(start), Some(end)) => Some((start, end))
    _ => None
  }
}

///|
/// Exact opening-fence span for a fenced code block, including its info string.
pub fn MarkdownBlockSnapshot::fence_open_range(self : Self) -> (Int, Int)? {
  match (self.fence_open_start, self.fence_open_end) {
    (Some(start), Some(end)) => Some((start, end))
    _ => None
  }
}

///|
/// Exact closing-fence span for a fenced code block.
pub fn MarkdownBlockSnapshot::fence_close_range(self : Self) -> (Int, Int)? {
  match (self.fence_close_start, self.fence_close_end) {
    (Some(start), Some(end)) => Some((start, end))
    _ => None
  }
}

///|
/// A categorized failure at the archive boundary.
///
/// Kept separate from `MarkdownEditorError` because an archive is a different
/// authority from an editing session: a failure to reopen a document is not an
/// editing failure, and the two are acted on at different moments. Sharing one
/// taxonomy is how document recovery quietly becomes a session concern.
pub(all) suberror MarkdownArchiveError {
  InvalidAgentId
  /// No writing instance could be created, so nothing was attempted. Distinct
  /// from `AdmitFailed`, which means a history was taken in and the taking
  /// failed.
  WriterUnavailable(detail~ : String)
  ExportFailed(detail~ : String)
  AdmitFailed(detail~ : String)
  IncompleteArchive
}

///|
/// What an admission took, and what it is still holding.
///
/// Operations can arrive whose causal prerequisites have not. That is ordinary
/// between replicas and is not a failure, so it is reported rather than raised.
/// Whether it is acceptable is the caller's judgment: a peer exchange expects
/// it, and an archive that claims to be complete is contradicted by it.
pub(all) enum MarkdownAdmitReport {
  /// Nothing is held: every operation in the history is now in this document.
  ///
  /// This carries no count. How many operations were new rather than already
  /// present depends on what the sender chose to include, which says nothing
  /// about this document, and whether the document advanced is answered by its
  /// version — a signal that does not need a count to be read.
  Complete
  /// Some operations await prerequisites that did not arrive, and are held
  /// until they do.
  ///
  /// Both counts are carried because the partial and total cases call for
  /// different responses: `applied` is how many operations were new to this
  /// document, so zero means nothing landed at all, and that reading holds
  /// whatever else the message contained.
  Withheld(applied~ : Int, withheld~ : Int)
} derive(Eq, Debug)

///|
/// Opaque identity of a projected Markdown node.
pub struct MarkdownNodeId {
  priv value : @core.NodeId
} derive(Eq, Debug)

///|
pub fn MarkdownNodeId::key(self : Self) -> String {
  self.value.to_string()
}

///|
/// Immutable logical selection inside one editable block.
pub struct MarkdownBlockSelection {
  priv node_id : MarkdownNodeId
  priv offset : Int
} derive(Eq, Debug)

///|
pub fn MarkdownBlockSelection::node_id(self : Self) -> MarkdownNodeId {
  self.node_id
}

///|
/// UTF-16 code-unit offset relative to the selected block's text span.
pub fn MarkdownBlockSelection::offset(self : Self) -> Int {
  self.offset
}

///|
/// A caller-owned edit request lowered by the Markdown façade.
pub(all) enum MarkdownEditRequest {
  ReplaceSource(String)
  ReplaceText(start~ : Int, delete_len~ : Int, inserted~ : String)
  CommitEdit(node_id~ : MarkdownNodeId, new_text~ : String)
  CommitTextControlEdit(node_id~ : MarkdownNodeId, new_text~ : String)
  SplitBlock(node_id~ : MarkdownNodeId, offset~ : Int)
  ChangeHeadingLevel(node_id~ : MarkdownNodeId, level~ : Int)
  ToggleListItem(node_id~ : MarkdownNodeId)
  Delete(node_id~ : MarkdownNodeId)
  MergeWithPrevious(node_id~ : MarkdownNodeId)
} derive(Eq, Debug)

///|
/// Immutable, façade-owned projection summary.
pub struct MarkdownProjectionSnapshot {
  priv root_id : MarkdownNodeId?
  priv node_ids : @vector.Vector[MarkdownNodeId]
} derive(Eq, Debug)

///|
pub fn MarkdownProjectionSnapshot::root_id(self : Self) -> MarkdownNodeId? {
  self.root_id
}

///|
pub fn MarkdownProjectionSnapshot::node_ids(
  self : Self,
) -> @vector.Vector[MarkdownNodeId] {
  self.node_ids
}

///|
/// An immutable source snapshot detached from the editor implementation.
pub struct MarkdownDocumentSnapshot {
  priv source : String
  priv projection : MarkdownProjectionSnapshot
  priv blocks : @vector.Vector[MarkdownBlockSnapshot]
} derive(Eq, Debug)

///|
pub fn MarkdownDocumentSnapshot::source(self : Self) -> String {
  self.source
}

///|
pub fn MarkdownDocumentSnapshot::projection(
  self : Self,
) -> MarkdownProjectionSnapshot {
  self.projection
}

///|
pub fn MarkdownDocumentSnapshot::blocks(
  self : Self,
) -> @vector.Vector[MarkdownBlockSnapshot] {
  self.blocks
}

///|
/// The document's version frontier, as a façade-owned value.
///
/// This is the signal persistence triggers on: an operation that leaves the
/// source unchanged still moves it. Equality here means "has not advanced",
/// never "is the same document" — two different histories can share a
/// frontier, so continuation is decided by `MarkdownDocumentHistory` instead.
pub struct MarkdownDocumentVersion {
  priv value : @text.Version
} derive(Eq, Debug)

///|
/// One document's operation history, carried as a value the caller cannot
/// interpret.
///
/// The payload's own serialization is a closed CRDT contract that admits no
/// application metadata, so document identity and archive versioning cannot
/// be carried here — they belong to an outer envelope this façade does not
/// define. Keeping the payload opaque is what stops that envelope from being
/// skipped once one exists.
pub struct MarkdownDocumentHistory {
  priv message : @text.SyncMessage
}

///|
/// Equality is canonical-history equality: the honest check that one document
/// continues another. Comparing source and version instead would accept a
/// document that merely looks the same.
pub impl Eq for MarkdownDocumentHistory with fn equal(
  self : MarkdownDocumentHistory,
  other : MarkdownDocumentHistory,
) -> Bool {
  self.message.to_canonical_bytes() == other.message.to_canonical_bytes()
}

///|
/// Result of one atomic editor commit.
pub(all) enum MarkdownCommitResult {
  Applied(MarkdownDocumentSnapshot, MarkdownBlockSelection?)
  Unchanged(MarkdownDocumentSnapshot)
} derive(Eq, Debug)

///|
/// Origin of a committed Markdown change.
///
/// This ticket reports only edits produced by this writing instance. Keeping
/// origin explicit prevents a future remote admission from entering a local
/// persistence outbox by accident.
pub(all) enum MarkdownCommitOrigin {
  Local
} derive(Eq, Debug)

///|
/// One source transform for downstream presence coordinates.
///
/// `start` and `delete_len` are UTF-16 code-unit coordinates, and
/// `inserted.length()` is the inserted UTF-16 length. The first transform is
/// relative to the source immediately before the commit; each later transform
/// is relative to the source produced by every preceding transform. Applying
/// the ordered sequence yields the receipt's post-commit snapshot source.
pub struct MarkdownTextTransform {
  priv change : @text_change.TextChange
} derive(Eq, Debug)

///|
pub fn MarkdownTextTransform::start(self : Self) -> Int {
  self.change.start
}

///|
pub fn MarkdownTextTransform::delete_len(self : Self) -> Int {
  self.change.delete_len
}

///|
pub fn MarkdownTextTransform::inserted(self : Self) -> String {
  self.change.inserted
}

///|
/// Causal receipt for one successful local commit attempt.
///
/// The legacy result remains source-oriented for compatibility. Advancement is
/// reported independently through the before/after versions: when they differ,
/// `history` is exactly the opaque increment since `before_version`; when they
/// are equal, `history` is absent and `transforms` is empty.
pub struct MarkdownCommitReceipt {
  priv result : MarkdownCommitResult
  priv before_version : MarkdownDocumentVersion
  priv after_version : MarkdownDocumentVersion
  priv origin : MarkdownCommitOrigin
  priv history : MarkdownDocumentHistory?
  priv transforms : @vector.Vector[MarkdownTextTransform]
}

///|
pub fn MarkdownCommitReceipt::result(self : Self) -> MarkdownCommitResult {
  self.result
}

///|
pub fn MarkdownCommitReceipt::before_version(
  self : Self,
) -> MarkdownDocumentVersion {
  self.before_version
}

///|
pub fn MarkdownCommitReceipt::after_version(
  self : Self,
) -> MarkdownDocumentVersion {
  self.after_version
}

///|
pub fn MarkdownCommitReceipt::origin(self : Self) -> MarkdownCommitOrigin {
  self.origin
}

///|
/// Opaque history increment cut at `before_version`, present only when the
/// document version advanced.
pub fn MarkdownCommitReceipt::history(self : Self) -> MarkdownDocumentHistory? {
  self.history
}

///|
/// Ordered UTF-16 transforms for downstream presence updates.
pub fn MarkdownCommitReceipt::transforms(
  self : Self,
) -> @vector.Vector[MarkdownTextTransform] {
  self.transforms
}

///|
/// Opaque, headless Markdown editor façade.
pub struct MarkdownEditor {
  priv editor : @editor.SyncEditor[@md_markdown.Block]
}

///|
/// Create a new document from text.
///
/// This is the importing path, and it is the lossy one: the result has no past
/// and shares no future with whatever produced the source. Continuing a
/// document you already own is `open`.
///
/// The name does not yet say so. Renaming it to `import`, and letting the
/// document mint its own writer identity instead of accepting one, both reach
/// the single application call site and are deferred with it.
pub fn MarkdownEditor::MarkdownEditor(
  agent_id~ : String,
  source~ : String,
) -> MarkdownEditor raise MarkdownEditorError {
  let editor = @md_companion.new_markdown_editor(agent_id) catch {
    @text.TextError::EmptyReplicaId => raise MarkdownEditorError::InvalidAgentId
    error =>
      raise MarkdownEditorError::InitializationFailed(detail=error.message())
  }
  editor.set_text(source)
  editor.refresh()
  { editor, }
}

///|
/// Continue a document you already own, from its history.
///
/// This is admission into a document that holds nothing yet. It composes the
/// general operation rather than standing beside it, because opening and
/// merging differ only in what the receiver already holds — a surface that
/// exposed only this case would make merging inexpressible, and merging is the
/// only way to show a reopened document still shares a future.
///
/// Opening is where the completeness policy is stated. An archive presenting
/// itself as whole is contradicted by operations it cannot satisfy, so withheld
/// operations are refused here — while the same report is an expected outcome
/// for a peer exchange. Nothing separates the two but this judgment.
///
/// The writer identity is supplied rather than carried by the history: a
/// reopened document is a new writing instance, and reusing the exporter's
/// identity would make the two indistinguishable in what they go on to write.
///
/// Not yet stated here: the admission policy. This passes through the path
/// that admits remote traffic and inherits the resource limits written for it,
/// which the design requires it not to. See the evidence record.
pub fn MarkdownEditor::open(
  agent_id~ : String,
  history~ : MarkdownDocumentHistory,
) -> MarkdownEditor raise MarkdownArchiveError {
  let editor = @md_companion.new_markdown_editor(agent_id) catch {
    @text.TextError::EmptyReplicaId =>
      raise MarkdownArchiveError::InvalidAgentId
    error =>
      raise MarkdownArchiveError::WriterUnavailable(detail=error.message())
  }
  let document = { editor, }
  match document.admit(history) {
    MarkdownAdmitReport::Complete => document
    MarkdownAdmitReport::Withheld(..) =>
      raise MarkdownArchiveError::IncompleteArchive
  }
}

///|
/// Take a history into this document, whatever it already holds.
///
/// One operation covers restoring and merging; the receiver's prior contents
/// are the only difference. Withheld operations are reported rather than
/// raised, because a document waiting for prerequisites is in a state, not in
/// a failure, and a caller that cannot tell those apart cannot decide what to
/// do next.
pub fn MarkdownEditor::admit(
  self : Self,
  history : MarkdownDocumentHistory,
) -> MarkdownAdmitReport raise MarkdownArchiveError {
  let report = self.editor.admit(history.message) catch {
    error => raise MarkdownArchiveError::AdmitFailed(detail=error.message())
  }
  // Applicable operations are committed before the withheld ones are counted,
  // so the projection is rebuilt on both paths.
  self.editor.refresh()
  match report.pending_operations() {
    0 => MarkdownAdmitReport::Complete
    withheld =>
      MarkdownAdmitReport::Withheld(
        applied=report.applied_operations(),
        withheld~,
      )
  }
}

///|
/// Read the last committed canonical source without exposing editor state.
pub fn MarkdownEditor::snapshot(self : Self) -> MarkdownDocumentSnapshot {
  document_snapshot(self.editor)
}

///|
/// Read the current version frontier without exposing editor state.
pub fn MarkdownEditor::version(self : Self) -> MarkdownDocumentVersion {
  { value: self.editor.get_version() }
}

///|
/// Cut the history at a version and hand back everything after it.
///
/// The increment is the primitive and the whole history is the degenerate case
/// of cutting at nothing. Saving triggers on the document advancing, so an
/// export that could only produce everything would make the cost of saving
/// grow with the age of the document rather than the size of the change — and
/// the base-plus-increment shape that answers scale is the same shape that
/// answers routine saving, not a later addition.
///
/// What comes back is a value the caller keeps but cannot read.
pub fn MarkdownEditor::history_since(
  self : Self,
  version? : MarkdownDocumentVersion,
) -> MarkdownDocumentHistory raise MarkdownArchiveError {
  let message = try {
    match version {
      None => self.editor.export_all()
      Some(cut) => self.editor.export_since(cut.value)
    }
  } catch {
    // The export methods widen to the supertype, so the binder has no
    // `message()` here as it does at the admission and construction sites.
    error => raise MarkdownArchiveError::ExportFailed(detail="\{error}")
  }
  { message, }
}

///|
/// Apply one façade-owned request atomically.
///
/// This compatibility method intentionally returns only the existing
/// source-oriented result. Call `commit_with_receipt` when causal advancement
/// and presence transforms are needed.
pub fn MarkdownEditor::commit(
  self : Self,
  request : MarkdownEditRequest,
) -> Result[MarkdownCommitResult, MarkdownEditorError] {
  self.commit_recording_transforms(request).map(pair => pair.0)
}

///|
/// Apply one request and report causal advancement without changing `commit`.
///
/// History export can fail independently after the local edit has committed,
/// so archive failures remain raised while edit failures keep the legacy
/// `Result` channel.
pub fn MarkdownEditor::commit_with_receipt(
  self : Self,
  request : MarkdownEditRequest,
) -> Result[MarkdownCommitReceipt, MarkdownEditorError] raise MarkdownArchiveError {
  let before_version = self.version()
  match self.commit_recording_transforms(request) {
    Err(error) => Err(error)
    Ok((result, transforms)) => {
      let after_version = self.version()
      if after_version == before_version {
        Ok({
          result,
          before_version,
          after_version,
          origin: MarkdownCommitOrigin::Local,
          history: None,
          transforms: @vector.new(),
        })
      } else {
        Ok({
          result,
          before_version,
          after_version,
          origin: MarkdownCommitOrigin::Local,
          history: Some(self.history_since(version=before_version)),
          transforms,
        })
      }
    }
  }
}

///|
/// Keep the mutation shell shared by legacy commits and causal receipts.
fn MarkdownEditor::commit_recording_transforms(
  self : Self,
  request : MarkdownEditRequest,
) -> Result[
  (MarkdownCommitResult, @vector.Vector[MarkdownTextTransform]),
  MarkdownEditorError,
] {
  match request {
    ReplaceSource(source) => {
      let before = self.editor.get_text()
      if before == source {
        Ok((MarkdownCommitResult::Unchanged(self.snapshot()), @vector.new()))
      } else {
        // set_text uses this same shared splice contract. Computing it here is
        // the only path without caller- or lowering-supplied edit information.
        let change = @text_change.compute_text_change(before, source)
        self.editor.set_text(source)
        self.editor.refresh()
        Ok(
          (
            MarkdownCommitResult::Applied(self.snapshot(), None),
            @vector.Vector::singleton(MarkdownTextTransform::{ change, }),
          ),
        )
      }
    }
    ReplaceText(start~, delete_len~, inserted~) => {
      let source = self.editor.get_text()
      let source_length = source.length()
      if start < 0 ||
        delete_len < 0 ||
        start > source_length ||
        delete_len > source_length - start {
        Err(
          MarkdownEditorError::InvalidTextRange(
            start~,
            delete_len~,
            source_length~,
          ),
        )
      } else if self.editor.apply_text_edit_exact(
          start, delete_len, inserted, 0,
        ) {
        self.editor.refresh()
        let snapshot = self.snapshot()
        let result = if snapshot.source() == source {
          MarkdownCommitResult::Unchanged(snapshot)
        } else {
          MarkdownCommitResult::Applied(snapshot, None)
        }
        Ok(
          (
            result,
            @vector.Vector::singleton(MarkdownTextTransform::{
              change: @text_change.TextChange::{ start, delete_len, inserted },
            }),
          ),
        )
      } else {
        Err(MarkdownEditorError::EditFailed(detail="text edit rejected"))
      }
    }
    CommitEdit(node_id~, new_text~) =>
      match self.editable_block_text(node_id) {
        Some(_) =>
          self.commit_structural_recording_transforms(
            @md_edits.MarkdownEditOp::CommitEdit(
              node_id=node_id.value,
              new_text~,
            ),
          )
        None =>
          Err(
            MarkdownEditorError::EditFailed(
              detail="no editable span for Markdown block target",
            ),
          )
      }
    CommitTextControlEdit(node_id~, new_text~) =>
      match self.editable_block_text(node_id) {
        Some(canonical_text) => {
          let reconciled = if @md_sentinel.is_empty_paragraph_text(
              canonical_text,
            ) {
            new_text
          } else {
            reconcile_text_control_edit(canonical_text, new_text)
          }
          let new_text = if reconciled.is_empty() {
            @md_sentinel.EMPTY_PARAGRAPH_SENTINEL
          } else {
            reconciled
          }
          self.commit_structural_recording_transforms(
            @md_edits.MarkdownEditOp::CommitEdit(
              node_id=node_id.value,
              new_text~,
            ),
          )
        }
        None =>
          Err(
            MarkdownEditorError::EditFailed(
              detail="Markdown block target is not an editable top-level block",
            ),
          )
      }
    SplitBlock(node_id~, offset~) =>
      if self.editable_block_target(node_id) {
        self.commit_structural_recording_transforms(
          @md_edits.MarkdownEditOp::SplitBlock(node_id=node_id.value, offset~),
        )
      } else {
        Err(
          MarkdownEditorError::EditFailed(
            detail="Markdown block target is not an editable top-level block",
          ),
        )
      }
    ChangeHeadingLevel(node_id~, level~) =>
      self.commit_structural_recording_transforms(
        @md_edits.MarkdownEditOp::ChangeHeadingLevel(
          node_id=node_id.value,
          level~,
        ),
      )
    ToggleListItem(node_id~) =>
      self.commit_structural_recording_transforms(
        @md_edits.MarkdownEditOp::ToggleListItem(node_id=node_id.value),
      )
    Delete(node_id~) =>
      self.commit_structural_recording_transforms(
        @md_edits.MarkdownEditOp::Delete(node_id=node_id.value),
      )
    MergeWithPrevious(node_id~) =>
      if self.editable_block_target(node_id) {
        self.commit_structural_recording_transforms(
          @md_edits.MarkdownEditOp::MergeWithPrevious(node_id=node_id.value),
        )
      } else {
        Err(
          MarkdownEditorError::EditFailed(
            detail="Markdown block target is not an editable top-level block",
          ),
        )
      }
  }
}

///|
/// Lower one typed request once, apply the same spans, and retain their exact
/// order for the receipt without re-diffing the resulting source.
fn MarkdownEditor::commit_structural_recording_transforms(
  self : Self,
  op : @md_edits.MarkdownEditOp,
) -> Result[
  (MarkdownCommitResult, @vector.Vector[MarkdownTextTransform]),
  MarkdownEditorError,
] {
  let source = self.editor.get_text()
  guard self.editor.get_proj_node() is Some(proj) else {
    return Err(MarkdownEditorError::ProjectionUnavailable)
  }
  let deleted_block_index = match op {
    @md_edits.Delete(node_id~) =>
      self
      .snapshot()
      .blocks()
      .to_array()
      .search_by(block => block.node_id().value == node_id)
    _ => None
  }
  let computed = Ok(
    @md_edits.compute_markdown_edit(
      op,
      source,
      proj,
      self.editor.get_source_map(),
    ),
  ) catch {
    error => Err(error.message())
  }
  match computed {
    Err(detail) => Err(MarkdownEditorError::EditFailed(detail~))
    Ok(lowered) => {
      let (edits, focus_hint) = match lowered {
        Some(pair) => pair
        None => ([], @core.FocusHint::RestoreCursor)
      }
      self.editor.apply_span_edits(edits, focus_hint, 0)
      self.editor.refresh()
      let snapshot = self.snapshot()
      let result = if snapshot.source() == source {
        // A no-op never authorizes a new caret move for the caller.
        MarkdownCommitResult::Unchanged(snapshot)
      } else {
        let selection = match deleted_block_index {
          Some(index) => {
            let blocks = snapshot.blocks().to_array()
            let survivor = match blocks.get(index) {
              Some(block) => Some(block)
              None => blocks.get(index - 1)
            }
            survivor.map(block => MarkdownBlockSelection::{
              node_id: block.node_id(),
              offset: block.text().length(),
            })
          }
          None =>
            selection_for_cursor(
              snapshot,
              self.editor.get_cursor(),
              allow_nearest=false,
            )
        }
        MarkdownCommitResult::Applied(snapshot, selection)
      }
      Ok((result, sequential_text_transforms(edits)))
    }
  }
}

///|
/// Mirror SyncEditor's reverse-document-order application as a sequential,
/// immutable façade value. Local mutation only sorts a private copy used to
/// build the returned vector.
fn sequential_text_transforms(
  edits : Array[@core.SpanEdit],
) -> @vector.Vector[MarkdownTextTransform] {
  let ordered = edits.copy()
  ordered.sort_by((a, b) => b.start.compare(a.start))
  let transforms = ordered.map(edit => MarkdownTextTransform::{
    change: @text_change.TextChange::{
      start: edit.start,
      delete_len: edit.delete_len,
      inserted: edit.inserted,
    },
  })
  @vector.Vector(transforms[:])
}

///|
/// Keep the public block façade narrower than the general Markdown edit API.
/// List items and container descendants remain available to lower-level edit
/// tests, but are not block-surface targets until their own UI contract exists.
fn MarkdownEditor::editable_block_target(
  self : Self,
  node_id : MarkdownNodeId,
) -> Bool {
  for block in self.snapshot().blocks().to_array() {
    if block.node_id() == node_id {
      return match block.kind() {
        MarkdownBlockKind::Paragraph | MarkdownBlockKind::Heading(_) => true
        _ => false
      }
    }
  }
  false
}

///|
/// Read the current canonical payload for one supported top-level block.
fn MarkdownEditor::editable_block_text(
  self : Self,
  node_id : MarkdownNodeId,
) -> String? {
  for block in self.snapshot().blocks().to_array() {
    if block.node_id() == node_id {
      return Some(block.canonical_text())
    }
  }
  None
}

///|
/// Normalize only for comparison with a DOM textarea control value.
fn normalize_text_control_line_endings(text : String) -> String {
  text.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
}

///|
/// Map an LF-normalized UTF-16 offset back into canonical source coordinates.
fn canonical_offset_for_text_control(
  canonical_text : String,
  normalized_offset : Int,
) -> Int {
  let mut canonical_offset = 0
  let mut normalized_offset_seen = 0
  while canonical_offset < canonical_text.length() &&
        normalized_offset_seen < normalized_offset {
    if canonical_text.code_unit_at(canonical_offset).to_int() == 0x0D {
      canonical_offset += 1
      if canonical_offset < canonical_text.length() &&
        canonical_text.code_unit_at(canonical_offset).to_int() == 0x0A {
        canonical_offset += 1
      }
    } else {
      canonical_offset += 1
    }
    normalized_offset_seen += 1
  }
  canonical_offset
}

///|
/// Reconcile a DOM-normalized block value while preserving untouched endings.
fn reconcile_text_control_edit(
  canonical_text : String,
  control_text : String,
) -> String {
  let normalized_canonical = normalize_text_control_line_endings(canonical_text)
  let normalized_control = normalize_text_control_line_endings(control_text)
  let change = @text_change.compute_text_change(
    normalized_canonical, normalized_control,
  )
  let canonical_start = canonical_offset_for_text_control(
    canonical_text,
    change.start,
  )
  let canonical_end = canonical_offset_for_text_control(
    canonical_text,
    change.start + change.delete_len,
  )
  canonical_text[:canonical_start].to_owned() +
  change.inserted +
  canonical_text[canonical_end:].to_owned()
}

///|
/// Resolve the SyncEditor cursor against the detached post-commit snapshot.
fn selection_for_cursor(
  snapshot : MarkdownDocumentSnapshot,
  cursor : Int,
  allow_nearest~ : Bool,
) -> MarkdownBlockSelection? {
  let closest : (Int, MarkdownBlockSelection)? = snapshot
    .blocks()
    .fold(init=None, (closest, block) => {
      let (start, end) = block.text_range()
      let (distance, offset) = if cursor < start {
        (start - cursor, 0)
      } else if cursor > end {
        (cursor - end, end - start)
      } else {
        (0, cursor - start)
      }
      let candidate = MarkdownBlockSelection::{
        node_id: block.node_id(),
        offset,
      }
      if distance != 0 && !allow_nearest {
        closest
      } else {
        match closest {
          Some((closest_distance, _)) if closest_distance <= distance => closest
          _ => Some((distance, candidate))
        }
      }
    })
  closest.map(pair => {
    let (_, selection) = pair
    selection
  })
}

///|
/// Copy only stable node identities into the façade snapshot.
fn projection_snapshot(
  editor : @editor.SyncEditor[@md_markdown.Block],
) -> MarkdownProjectionSnapshot {
  match editor.get_proj_node() {
    None => { root_id: None, node_ids: @vector.new() }
    Some(root) => {
      let ids : Array[MarkdownNodeId] = []
      root.walk_preorder(node => ids.push({ value: node.id() }))
      { root_id: Some({ value: root.id() }), node_ids: @vector.Vector(ids[:]) }
    }
  }
}

///|
/// Build one detached document snapshot from the editor's typed projection
/// and SourceMap. Unsupported containers remain mapped but are omitted from
/// the editable block view, preserving the #1045 alignment policy.
fn document_snapshot(
  editor : @editor.SyncEditor[@md_markdown.Block],
) -> MarkdownDocumentSnapshot {
  let source = editor.get_text()
  {
    source,
    projection: projection_snapshot(editor),
    blocks: editable_block_snapshots(editor, source),
  }
}

///|
fn editable_block_snapshots(
  editor : @editor.SyncEditor[@md_markdown.Block],
  source : String,
) -> @vector.Vector[MarkdownBlockSnapshot] {
  match editor.get_proj_node() {
    None => @vector.new()
    Some(root) => {
      let source_map = editor.get_source_map()
      let blocks : Array[MarkdownBlockSnapshot] = []
      for node in root.children {
        match node.kind {
          @md_markdown.UnorderedList(_) | @md_markdown.OrderedList(_, _) =>
            if tight_top_level_list(source, node, source_map) {
              for item in node.children {
                match item.kind {
                  @md_markdown.UnorderedListItem(_) =>
                    append_editable_block_snapshot(
                      blocks,
                      item,
                      MarkdownBlockKind::UnorderedListItem,
                      source,
                      source_map,
                    )
                  @md_markdown.OrderedListItem(_, marker) => {
                    guard marker is Some(_) else { continue }
                    let marker = match marker {
                      Some(marker) => marker
                      None => continue
                    }
                    append_editable_block_snapshot(
                      blocks,
                      item,
                      MarkdownBlockKind::OrderedListItem(
                        start=marker.start(),
                        delimiter=ordered_marker_delimiter(marker),
                      ),
                      source,
                      source_map,
                    )
                  }
                  _ => ()
                }
              }
            }
          @md_markdown.Paragraph(_) =>
            append_editable_block_snapshot(
              blocks,
              node,
              MarkdownBlockKind::Paragraph,
              source,
              source_map,
            )
          @md_markdown.Heading(level, _) =>
            append_editable_block_snapshot(
              blocks,
              node,
              MarkdownBlockKind::Heading(level~),
              source,
              source_map,
            )
          @md_markdown.CodeBlock(info, _) =>
            append_editable_block_snapshot(
              blocks,
              node,
              MarkdownBlockKind::CodeBlock(info~),
              source,
              source_map,
            )
          _ => ()
        }
      }
      @vector.Vector(blocks[:])
    }
  }
}

///|
/// Append one block whose SourceMap roles satisfy the typed façade contract.
fn append_editable_block_snapshot(
  blocks : Array[MarkdownBlockSnapshot],
  node : @core.ProjNode[@md_markdown.Block],
  kind : MarkdownBlockKind,
  source : String,
  source_map : @core.SourceMap,
) -> Unit {
  guard source_map.get_range(node.id()) is Some(source_range) else { return }
  let text_span = match source_map.get_token_span(node.id(), "text") {
    Some(span) => span
    None =>
      match source_map.get_token_span(node.id(), "code") {
        Some(span) => span
        None => return
      }
  }
  let marker_range = source_map.get_token_span(node.id(), "marker")
  let fence_open_range = source_map.get_token_span(node.id(), "fence_open")
  let fence_close_range = source_map.get_token_span(node.id(), "fence_close")
  if kind is MarkdownBlockKind::CodeBlock(_) &&
    (fence_open_range is None || fence_close_range is None) {
    return
  }
  blocks.push({
    node_id: { value: node.id() },
    kind,
    text: source[text_span.start:text_span.end].to_owned(),
    source_start: source_range.start,
    source_end: source_range.end,
    text_start: text_span.start,
    text_end: text_span.end,
    marker_start: marker_range.map(r => r.start),
    marker_end: marker_range.map(r => r.end),
    fence_open_start: fence_open_range.map(r => r.start),
    fence_open_end: fence_open_range.map(r => r.end),
    fence_close_start: fence_close_range.map(r => r.start),
    fence_close_end: fence_close_range.map(r => r.end),
  })
}

///|
/// A list is editable only when every direct item is a simple, tight item.
fn tight_top_level_list(
  source : String,
  list : @core.ProjNode[@md_markdown.Block],
  source_map : @core.SourceMap,
) -> Bool {
  for item in list.children {
    if !(item.kind is @md_markdown.Block::UnorderedListItem(_) ||
      item.kind is @md_markdown.Block::OrderedListItem(_, _)) {
      return false
    }
    if item.children.length() != 0 ||
      source_map.get_token_span(item.id(), "text") is None ||
      source_map.get_token_span(item.id(), "marker") is None {
      return false
    }
    let text_span = match source_map.get_token_span(item.id(), "text") {
      Some(span) => span
      None => return false
    }
    let payload = source[text_span.start:text_span.end]
    if payload.contains("\n".view()) || payload.contains("\r".view()) {
      return false
    }
  }
  for i in 0..<(list.children.length() - 1) {
    let current = list.children[i]
    let next = list.children[i + 1]
    let current_range = match source_map.get_range(current.id()) {
      Some(range) => range
      None => return false
    }
    let next_range = match source_map.get_range(next.id()) {
      Some(range) => range
      None => return false
    }
    let gap = source[current_range.end:next_range.start].to_owned()
    let normalized = gap
      .replace_all(old="\r\n", new="\n")
      .replace_all(old="\r", new="\n")
    if normalized.contains("\n\n".view()) {
      return false
    }
  }
  true
}

///|
fn ordered_marker_delimiter(marker : @md_markdown.OrderedListMarker) -> String {
  match marker.delimiter() {
    @md_markdown.Period => "."
    @md_markdown.Paren => ")"
  }
}
