///|
/// A categorized failure at the headless Markdown editor boundary.
pub(all) suberror MarkdownEditorError {
  InvalidAgentId
  InitializationFailed(detail~ : String)
  ProjectionUnavailable
  InvalidTextRange(start~ : Int, delete_len~ : Int, source_length~ : Int)
  EditFailed(detail~ : String)
  /// The causal edit landed; this is never authorization to retry it.
  Committed(
    evidence~ : MarkdownCommittedEvidence,
    issue~ : MarkdownPostCommitIssue
  )
}

///|
/// Sentinel-free evidence retained when receipt construction is interrupted
/// after the document version has advanced.
pub struct MarkdownCommittedEvidence {
  priv before : String
  priv after : String?
} derive(Eq, Debug)

///|
pub fn MarkdownCommittedEvidence::before(self : Self) -> String {
  self.before
}

///|
pub fn MarkdownCommittedEvidence::after(self : Self) -> String? {
  self.after
}

///|
/// Typed post-commit reasons that require recovery rather than edit retry.
pub(all) enum MarkdownPostCommitIssue {
  RuntimeFailure(detail~ : String)
  ProjectionUnavailable
  ProjectionFailed
  UnexpectedTransformCount(count~ : Int)
} derive(Eq, Debug)

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
/// Sentinel-free UTF-16 range in the owning document snapshot source.
pub fn MarkdownBlockSnapshot::source_range(self : Self) -> (Int, Int) {
  (self.source_start, self.source_end)
}

///|
/// Sentinel-free UTF-16 payload range in the owning snapshot source.
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
/// A resource dimension enforced while opening a Markdown archive.
pub(all) enum MarkdownArchiveLimitDimension {
  EncodedBytes
  DecodedOperations
  PendingOperations
  ParentsPerOperation
} derive(Eq, Debug)

///|
/// Invalid caller-selected archive open limits.
pub(all) suberror MarkdownArchiveOpenLimitsError {
  InvalidLimit(dimension~ : MarkdownArchiveLimitDimension, value~ : Int)
}

///|
/// Explicit resource limits for opening a Markdown archive.
///
/// All dimensions are required so archive restore cannot silently inherit the
/// limits chosen for untrusted peer traffic.
pub struct MarkdownArchiveOpenLimits {
  priv limits : @sync.Limits
}

///|
/// Construct archive open limits from the four EGW-enforced dimensions.
pub fn MarkdownArchiveOpenLimits::MarkdownArchiveOpenLimits(
  max_encoded_bytes~ : Int,
  max_decoded_operations~ : Int,
  max_pending_operations~ : Int,
  max_parents_per_operation~ : Int,
) -> MarkdownArchiveOpenLimits raise MarkdownArchiveOpenLimitsError {
  if max_encoded_bytes < 0 {
    raise MarkdownArchiveOpenLimitsError::InvalidLimit(
      dimension=MarkdownArchiveLimitDimension::EncodedBytes,
      value=max_encoded_bytes,
    )
  }
  if max_decoded_operations < 0 {
    raise MarkdownArchiveOpenLimitsError::InvalidLimit(
      dimension=MarkdownArchiveLimitDimension::DecodedOperations,
      value=max_decoded_operations,
    )
  }
  if max_pending_operations < 0 {
    raise MarkdownArchiveOpenLimitsError::InvalidLimit(
      dimension=MarkdownArchiveLimitDimension::PendingOperations,
      value=max_pending_operations,
    )
  }
  if max_parents_per_operation < 0 {
    raise MarkdownArchiveOpenLimitsError::InvalidLimit(
      dimension=MarkdownArchiveLimitDimension::ParentsPerOperation,
      value=max_parents_per_operation,
    )
  }
  let limits = try! @sync.Limits::Limits(
    max_encoded_bytes~,
    max_decoded_operations~,
    max_pending_operations~,
    max_parents_per_operation~,
  )
  { limits, }
}

///|
fn MarkdownArchiveLimitDimension::from_sync(
  dimension : @sync.LimitKind,
) -> MarkdownArchiveLimitDimension {
  match dimension {
    EncodedBytes => EncodedBytes
    DecodedOperations => DecodedOperations
    PendingOperations => PendingOperations
    ParentsPerOperation => ParentsPerOperation
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
  /// from `HistoryAdmissionFailed`, which means a history was taken in and the
  /// taking failed.
  WriterCreationFailed(detail~ : String)
  ExportFailed(detail~ : String)
  LimitExceeded(
    dimension~ : MarkdownArchiveLimitDimension,
    maximum~ : Int,
    actual~ : Int
  )
  HistoryAdmissionFailed(detail~ : String)
  IncompleteHistory
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
/// Why a document-level UTF-16 selection could not be constructed.
pub(all) suberror MarkdownDocumentUtf16SelectionError {
  OutOfBounds(anchor~ : Int, head~ : Int, source_length~ : Int)
  MidGraphemeBoundary(offset~ : Int)
} derive(Eq, Debug)

///|
/// Directed source selection in one detached Markdown document snapshot.
///
/// `anchor` and `head` are document-level UTF-16 code-unit offsets. Their
/// order preserves direction; range operations use their ordered bounds.
pub struct MarkdownDocumentUtf16Selection {
  priv anchor : Int
  priv head : Int
} derive(Eq, Debug)

///|
pub fn MarkdownDocumentUtf16Selection::anchor(self : Self) -> Int {
  self.anchor
}

///|
pub fn MarkdownDocumentUtf16Selection::head(self : Self) -> Int {
  self.head
}

///|
pub fn MarkdownDocumentUtf16Selection::range_start(self : Self) -> Int {
  let (start, _) = @cmp.minmax(self.anchor, self.head)
  start
}

///|
pub fn MarkdownDocumentUtf16Selection::range_end(self : Self) -> Int {
  let (_, end) = @cmp.minmax(self.anchor, self.head)
  end
}

///|
pub fn MarkdownDocumentUtf16Selection::is_backward(self : Self) -> Bool {
  self.anchor > self.head
}

///|
pub fn MarkdownDocumentUtf16Selection::is_collapsed(self : Self) -> Bool {
  self.anchor == self.head
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
/// Sentinel-free UTF-16 source shared by all snapshot ranges and receipts.
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
/// Construct a directed document-level UTF-16 selection validated against an
/// immutable Markdown snapshot.
pub fn MarkdownDocumentUtf16Selection::MarkdownDocumentUtf16Selection(
  snapshot : MarkdownDocumentSnapshot,
  anchor~ : Int,
  head~ : Int,
) -> MarkdownDocumentUtf16Selection raise MarkdownDocumentUtf16SelectionError {
  let source = snapshot.source()
  let source_length = source.length()
  guard anchor >= 0 &&
    anchor <= source_length &&
    head >= 0 &&
    head <= source_length else {
    raise MarkdownDocumentUtf16SelectionError::OutOfBounds(
      anchor~,
      head~,
      source_length~,
    )
  }
  let boundaries = @moji.grapheme_boundaries(source)
  guard boundaries.binary_search(anchor) is Ok(_) else {
    raise MarkdownDocumentUtf16SelectionError::MidGraphemeBoundary(
      offset=anchor,
    )
  }
  guard boundaries.binary_search(head) is Ok(_) else {
    raise MarkdownDocumentUtf16SelectionError::MidGraphemeBoundary(offset=head)
  }
  { anchor, head }
}

///|
/// One coherent snapshot and the opaque map used to project its cursor.
priv struct PortableDocumentSnapshot {
  snapshot : MarkdownDocumentSnapshot
  coordinates : @markdown_runtime.PortableCoordinateMap
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
/// Encode this causal frontier as the canonical portable text-version token.
pub fn MarkdownDocumentVersion::to_json_string(self : Self) -> String {
  self.value.to_json_string()
}

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
/// A malformed opaque history payload at the Markdown façade boundary.
pub(all) suberror MarkdownHistoryCodecError {
  Malformed(detail~ : String)
}

///|
/// Encode the opaque CRDT history without exposing its wire representation.
pub fn MarkdownDocumentHistory::to_json_string(self : Self) -> String {
  self.message.to_json_string()
}

///|
/// Decode an opaque CRDT history without exposing its wire representation.
pub fn MarkdownDocumentHistory::from_json_string(
  json : String,
) -> MarkdownDocumentHistory raise MarkdownHistoryCodecError {
  let message = @text.SyncMessage::from_json_string(json) catch {
    error => raise MarkdownHistoryCodecError::Malformed(detail=error.message())
  }
  { message, }
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
) -> MarkdownEditor raise {
  let editor = @md_companion.new_markdown_editor(agent_id) catch {
    Failure::Failure(_) as failure => raise failure
    @text.TextError::EmptyReplicaId => raise MarkdownEditorError::InvalidAgentId
    @text.TextError::InvalidPosition(..) =>
      raise MarkdownEditorError::InitializationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::InvalidText(..) =>
      raise MarkdownEditorError::InitializationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::InvalidRange(..) =>
      raise MarkdownEditorError::InitializationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::SyncFailed(_) =>
      raise MarkdownEditorError::InitializationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::VersionNotFound =>
      raise MarkdownEditorError::InitializationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::Internal(..) =>
      raise MarkdownEditorError::InitializationFailed(
        detail="text editor construction failed",
      )
    error => raise error
  }
  initialize_markdown_editor(editor, source)
}

///|
/// Create a Markdown façade and a semantic attachment over the same live
/// parser. The ordinary constructor remains attachment-free.
pub fn MarkdownEditor::with_semantic_attachment(
  agent_id~ : String,
  source~ : String,
) -> (MarkdownEditor, @md_markdown.MarkdownSemanticAttachment) raise {
  let (editor, attachment) = @md_companion.new_markdown_editor_with_semantic_attachment(
    agent_id,
  ) catch {
    Failure::Failure(_) as failure => raise failure
    @text.TextError::EmptyReplicaId => raise MarkdownEditorError::InvalidAgentId
    @text.TextError::InvalidPosition(..) =>
      raise MarkdownEditorError::InitializationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::InvalidText(..) =>
      raise MarkdownEditorError::InitializationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::InvalidRange(..) =>
      raise MarkdownEditorError::InitializationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::SyncFailed(_) =>
      raise MarkdownEditorError::InitializationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::VersionNotFound =>
      raise MarkdownEditorError::InitializationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::Internal(..) =>
      raise MarkdownEditorError::InitializationFailed(
        detail="text editor construction failed",
      )
    error => raise error
  }
  (initialize_markdown_editor(editor, source), attachment)
}

///|
/// Seed source and projection identically for every façade construction path.
fn initialize_markdown_editor(
  editor : @editor.SyncEditor[@md_markdown.Block],
  source : String,
) -> MarkdownEditor raise {
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
/// `open_limits` is explicit because restore and peer traffic are
/// different consumers of the same admission semantics. Opening never borrows
/// the receiver defaults used by peer admission.
pub fn MarkdownEditor::open(
  agent_id~ : String,
  history~ : MarkdownDocumentHistory,
  open_limits~ : MarkdownArchiveOpenLimits,
) -> MarkdownEditor raise {
  let editor = @md_companion.new_markdown_editor(agent_id) catch {
    Failure::Failure(_) as failure => raise failure
    @text.TextError::EmptyReplicaId =>
      raise MarkdownArchiveError::InvalidAgentId
    @text.TextError::InvalidPosition(..) =>
      raise MarkdownArchiveError::WriterCreationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::InvalidText(..) =>
      raise MarkdownArchiveError::WriterCreationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::InvalidRange(..) =>
      raise MarkdownArchiveError::WriterCreationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::SyncFailed(_) =>
      raise MarkdownArchiveError::WriterCreationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::VersionNotFound =>
      raise MarkdownArchiveError::WriterCreationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::Internal(..) =>
      raise MarkdownArchiveError::WriterCreationFailed(
        detail="text editor construction failed",
      )
    error => raise error
  }
  open_markdown_editor(editor, history, open_limits)
}

///|
/// Continue a document while retaining a semantic attachment over the
/// reopened parser.
pub fn MarkdownEditor::open_with_semantic_attachment(
  agent_id~ : String,
  history~ : MarkdownDocumentHistory,
  open_limits~ : MarkdownArchiveOpenLimits,
) -> (MarkdownEditor, @md_markdown.MarkdownSemanticAttachment) raise {
  let (editor, attachment) = @md_companion.new_markdown_editor_with_semantic_attachment(
    agent_id,
  ) catch {
    Failure::Failure(_) as failure => raise failure
    @text.TextError::EmptyReplicaId =>
      raise MarkdownArchiveError::InvalidAgentId
    @text.TextError::InvalidPosition(..) =>
      raise MarkdownArchiveError::WriterCreationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::InvalidText(..) =>
      raise MarkdownArchiveError::WriterCreationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::InvalidRange(..) =>
      raise MarkdownArchiveError::WriterCreationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::SyncFailed(_) =>
      raise MarkdownArchiveError::WriterCreationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::VersionNotFound =>
      raise MarkdownArchiveError::WriterCreationFailed(
        detail="text editor construction failed",
      )
    @text.TextError::Internal(..) =>
      raise MarkdownArchiveError::WriterCreationFailed(
        detail="text editor construction failed",
      )
    error => raise error
  }
  (open_markdown_editor(editor, history, open_limits), attachment)
}

///|
/// Admit a complete archive into a freshly constructed editor. Keeping this
/// boundary shared prevents ordinary and semantic reopen from drifting.
fn open_markdown_editor(
  editor : @editor.SyncEditor[@md_markdown.Block],
  history : MarkdownDocumentHistory,
  open_limits : MarkdownArchiveOpenLimits,
) -> MarkdownEditor raise {
  let report = editor.admit_with_limits(history.message, open_limits.limits) catch {
    Failure::Failure(_) as failure => raise failure
    @text.TextError::SyncFailed(
      @sync.Failure::LimitExceeded(kind~, limit~, actual~)
    ) =>
      raise MarkdownArchiveError::LimitExceeded(
        dimension=MarkdownArchiveLimitDimension::from_sync(kind),
        maximum=limit,
        actual~,
      )
    @text.TextError::EmptyReplicaId =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::InvalidPosition(..) =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::InvalidText(..) =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::InvalidRange(..) =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::SyncFailed(@sync.Failure::MissingDependency(..)) =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::SyncFailed(@sync.Failure::MalformedMessage(..)) =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::SyncFailed(@sync.Failure::InvalidContent(..)) =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::SyncFailed(@sync.Failure::ConflictingIdentity(..)) =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::VersionNotFound =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::Internal(..) =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    error => raise error
  }
  editor.refresh()
  if report.pending_operations() > 0 {
    raise MarkdownArchiveError::IncompleteHistory
  }
  { editor, }
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
) -> MarkdownAdmitReport raise {
  let report = self.editor.admit(history.message) catch {
    Failure::Failure(_) as failure => raise failure
    @text.TextError::EmptyReplicaId =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::InvalidPosition(..) =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::InvalidText(..) =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::InvalidRange(..) =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::SyncFailed(_) =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::VersionNotFound =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    @text.TextError::Internal(..) =>
      raise MarkdownArchiveError::HistoryAdmissionFailed(
        detail="history admission failed",
      )
    error => raise error
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
/// Read the last committed sentinel-free UTF-16 source and ranges.
pub fn MarkdownEditor::snapshot(
  self : Self,
) -> MarkdownDocumentSnapshot raise Failure {
  document_snapshot(self.editor)
}

///|
/// Return portable Markdown with façade-owned empty-block sentinels removed.
pub fn MarkdownEditor::portable_markdown(self : Self) -> String {
  markdown_full_export_observed()
  @md_companion.export_markdown_text(self.editor)
}

///|
/// Read the current version frontier without exposing editor state.
pub fn MarkdownEditor::version(self : Self) -> MarkdownDocumentVersion {
  { value: self.editor.get_version() }
}

///|
#cfg(target="js")
extern "js" fn markdown_archive_export_failure_injection() -> String =
  #|() => {
  #|  const injection = globalThis.__canopyMarkdownArchiveExportFailure;
  #|  if (injection == null) return "";
  #|  injection.count = (injection.count ?? 0) + 1;
  #|  return String(injection.detail ?? "injected archive export failure");
  #|}

///|
#cfg(not(target="js"))
fn markdown_archive_export_failure_injection() -> String {
  ""
}

///|
fn markdown_archive_export_failure() -> Unit raise Failure {
  match markdown_archive_export_failure_injection() {
    "" => ()
    detail => raise Failure::Failure(detail)
  }
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
    let message = match version {
      None => {
        markdown_full_export_observed()
        self.editor.export_all()
      }
      Some(cut) => self.editor.export_since(cut.value)
    }
    markdown_archive_export_failure()
    message
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
) -> Result[MarkdownCommitResult, MarkdownEditorError] raise {
  self.commit_recording_transforms(request).map(pair => pair.0)
}

///|
/// Facade-owned observation phases, including A1 evidence that does not belong
/// to the lower-level SyncEditor mutation scope.
pub enum MarkdownProjectionObservationPhase {
  AuthorityAccepted
  ProjectionMirrorSynchronized
  CausalEvidenceAvailable
} derive(Eq, Debug)

///|
/// Apply one request and report causal advancement without changing `commit`.
///
/// History export can fail independently after the local edit has committed,
/// so archive failures remain raised while edit failures keep the legacy
/// `Result` channel.
pub fn MarkdownEditor::commit_with_receipt(
  self : Self,
  request : MarkdownEditRequest,
) -> Result[MarkdownCommitReceipt, MarkdownEditorError] raise {
  self.commit_with_receipt_impl(request, None)
}

///|
/// Apply one request while observing its projection-relevant synchronous
/// phases. Observation is telemetry only and does not alter edit semantics.
pub fn MarkdownEditor::commit_with_receipt_observing(
  self : Self,
  request : MarkdownEditRequest,
  observer : (MarkdownProjectionObservationPhase) -> Unit,
) -> Result[MarkdownCommitReceipt, MarkdownEditorError] raise {
  self.commit_with_receipt_impl(request, Some(observer))
}

///|
fn MarkdownEditor::commit_with_receipt_impl(
  self : Self,
  request : MarkdownEditRequest,
  observer : ((MarkdownProjectionObservationPhase) -> Unit)?,
) -> Result[MarkdownCommitReceipt, MarkdownEditorError] raise {
  let authority_event_id = markdown_authority_trace_begin()
  let before_version = self.version()
  let observed = authority_event_id != 0 || observer is Some(_)
  let (committed, authority_accepted) = if !observed {
    (self.commit_recording_transforms(request), false)
  } else {
    self.editor.observe_projection_during(
      phase => {
        let facade_phase = match phase {
          @editor.ProjectionObservationPhase::AuthorityAccepted => {
            if authority_event_id != 0 {
              markdown_authority_trace_a0(
                authority_event_id,
                MARKDOWN_AUTHORITY_OUTCOME_ACCEPTED_TRANSITION,
              )
            }
            MarkdownProjectionObservationPhase::AuthorityAccepted
          }
          @editor.ProjectionObservationPhase::CommittedTransitionSettled => {
            if authority_event_id != 0 {
              markdown_authority_trace_a1(authority_event_id)
            }
            MarkdownProjectionObservationPhase::CausalEvidenceAvailable
          }
          @editor.ProjectionObservationPhase::ProjectionMirrorSynchronized =>
            MarkdownProjectionObservationPhase::ProjectionMirrorSynchronized
        }
        match observer {
          Some(emit) => emit(facade_phase)
          None => ()
        }
      },
      () => self.commit_recording_transforms(request),
    )
  }
  match committed {
    Err(error) => {
      if !authority_accepted && authority_event_id != 0 {
        markdown_authority_trace_a0(
          authority_event_id,
          MARKDOWN_AUTHORITY_OUTCOME_REJECTED,
        )
      }
      Err(error)
    }
    Ok((result, transforms)) => {
      let after_version = self.version()
      if after_version == before_version {
        if !authority_accepted && authority_event_id != 0 {
          markdown_authority_trace_a0(
            authority_event_id,
            MARKDOWN_AUTHORITY_OUTCOME_NO_ADVANCE,
          )
        }
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
] raise {
  match request {
    ReplaceSource(source) => {
      let before = capture_portable_coordinates(self.editor)
      if before.source() == source {
        Ok((MarkdownCommitResult::Unchanged(self.snapshot()), @vector.new()))
      } else {
        // The synchronization edit returns the same accepted splice used by
        // the CRDT; project that splice rather than diffing portable sources.
        let before_source = before.source()
        let version_before = self.editor.get_version()
        let applied : Result[
          (@text_change.TextChange, Bool),
          MarkdownEditorError,
        ] = Ok(self.editor.set_text_with_change(source)) catch {
          Failure::Failure(detail) =>
            if self.editor.get_version() != version_before {
              Err(
                committed_editor_error(
                  before_source,
                  None,
                  MarkdownPostCommitIssue::RuntimeFailure(detail~),
                ),
              )
            } else {
              raise Failure::Failure(detail)
            }
        }
        let (change, accepted) = match applied {
          Ok(applied) => applied
          Err(error) => return Err(error)
        }
        if accepted {
          self.editor.refresh() catch {
            Failure::Failure(detail) =>
              return Err(
                committed_editor_error(
                  before_source,
                  None,
                  MarkdownPostCommitIssue::RuntimeFailure(detail~),
                ),
              )
          }
          let after = match
            capture_committed_portable_coordinates(self.editor, before_source) {
            Ok(after) => after
            Err(error) => return Err(error)
          }
          let state = match
            committed_document_snapshot_from_coordinates(
              self.editor,
              before_source,
              after,
            ) {
            Ok(state) => state
            Err(error) => return Err(error)
          }
          let transform = match
            project_portable_transform(
              before,
              @core.SpanEdit::{
                start: change.start,
                delete_len: change.delete_len,
                inserted: change.inserted,
              },
              after,
            ) {
            Ok(transform) => transform
            Err(error) => return Err(error)
          }
          let result = if state.snapshot.source() == before_source {
            MarkdownCommitResult::Unchanged(state.snapshot)
          } else {
            MarkdownCommitResult::Applied(state.snapshot, None)
          }
          Ok((result, @vector.Vector::singleton(transform)))
        } else if self.editor.get_version() != version_before {
          Err(
            committed_editor_error(
              before_source,
              None,
              MarkdownPostCommitIssue::RuntimeFailure(
                detail="source replacement interrupted after commit",
              ),
            ),
          )
        } else {
          Err(
            MarkdownEditorError::EditFailed(
              detail="source replacement rejected",
            ),
          )
        }
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
      } else {
        let before = capture_portable_coordinates(self.editor)
        let before_source = before.source()
        let version_before = self.editor.get_version()
        let applied : Result[Bool, MarkdownEditorError] = Ok(
          self.editor.apply_text_edit_exact(start, delete_len, inserted, 0),
        ) catch {
          Failure::Failure(detail) =>
            if self.editor.get_version() != version_before {
              Err(
                committed_editor_error(
                  before_source,
                  None,
                  MarkdownPostCommitIssue::RuntimeFailure(detail~),
                ),
              )
            } else {
              raise Failure::Failure(detail)
            }
        }
        let accepted = match applied {
          Ok(accepted) => accepted
          Err(error) => return Err(error)
        }
        if accepted {
          self.editor.refresh() catch {
            Failure::Failure(detail) =>
              return Err(
                committed_editor_error(
                  before_source,
                  None,
                  MarkdownPostCommitIssue::RuntimeFailure(detail~),
                ),
              )
          }
          let after = match
            capture_committed_portable_coordinates(self.editor, before_source) {
            Ok(after) => after
            Err(error) => return Err(error)
          }
          let state = match
            committed_document_snapshot_from_coordinates(
              self.editor,
              before_source,
              after,
            ) {
            Ok(state) => state
            Err(error) => return Err(error)
          }
          let transform = match
            project_portable_transform(
              before,
              @core.SpanEdit::{ start, delete_len, inserted },
              after,
            ) {
            Ok(transform) => transform
            Err(error) => return Err(error)
          }
          let result = if state.snapshot.source() == before_source {
            MarkdownCommitResult::Unchanged(state.snapshot)
          } else {
            MarkdownCommitResult::Applied(state.snapshot, None)
          }
          Ok((result, @vector.Vector::singleton(transform)))
        } else if self.editor.get_version() != version_before {
          Err(
            committed_editor_error(
              before_source,
              None,
              MarkdownPostCommitIssue::RuntimeFailure(
                detail="text edit interrupted after commit",
              ),
            ),
          )
        } else {
          Err(MarkdownEditorError::EditFailed(detail="text edit rejected"))
        }
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
] raise {
  let deleted_block_index = match op {
    @md_edits.Delete(node_id~) =>
      self
      .snapshot()
      .blocks()
      .to_array()
      .search_by(block => block.node_id().value == node_id)
    _ => None
  }
  match @markdown_runtime.commit_portable_edit(self.editor, op, 0) {
    Err(@markdown_runtime.PortableCommitError::EditRejected(error~)) =>
      Err(structural_edit_error(error))
    Err(@markdown_runtime.PortableCommitError::NotCommitted(issue~)) =>
      portable_not_committed_error(issue)
    Ok(@markdown_runtime.PortableCommitOutcome::Committed(evidence~, issue~)) =>
      Err(markdown_committed_error(evidence, issue))
    Ok(@markdown_runtime.PortableCommitOutcome::Unchanged(_)) =>
      Ok((MarkdownCommitResult::Unchanged(self.snapshot()), @vector.new()))
    Ok(@markdown_runtime.PortableCommitOutcome::Applied(commit)) => {
      let state = match
        committed_document_snapshot(
          self.editor,
          commit.before(),
          commit.after(),
        ) {
        Ok(state) => state
        Err(error) => return Err(error)
      }
      let snapshot = state.snapshot
      if snapshot.source() != commit.after() {
        return Err(
          committed_editor_error(
            commit.before(),
            Some(commit.after()),
            MarkdownPostCommitIssue::ProjectionFailed,
          ),
        )
      }
      let result = if commit.before() == commit.after() {
        // History advanced, but a source-oriented result never authorizes a
        // caret move when the portable source did not change.
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
          None => {
            let cursor = match
              state.coordinates.project_offset(self.editor.get_cursor()) {
              Ok(cursor) => cursor
              Err(_) =>
                return Err(
                  committed_editor_error(
                    commit.before(),
                    Some(commit.after()),
                    MarkdownPostCommitIssue::ProjectionFailed,
                  ),
                )
            }
            selection_for_cursor(snapshot, cursor, allow_nearest=false)
          }
        }
        MarkdownCommitResult::Applied(snapshot, selection)
      }
      let transform = markdown_text_transform(commit.transform())
      Ok((result, @vector.Vector::singleton(transform)))
    }
  }
}

///|
fn markdown_committed_error(
  evidence : @markdown_runtime.PortableCommitEvidence,
  issue : @markdown_runtime.PortableCommitIssue,
) -> MarkdownEditorError {
  committed_editor_error(
    evidence.before(),
    evidence.after(),
    markdown_post_commit_issue(issue),
  )
}

///|
fn committed_editor_error(
  before : String,
  after : String?,
  issue : MarkdownPostCommitIssue,
) -> MarkdownEditorError {
  MarkdownEditorError::Committed(
    evidence=MarkdownCommittedEvidence::{ before, after },
    issue~,
  )
}

///|
fn markdown_post_commit_issue(
  issue : @markdown_runtime.PortableCommitIssue,
) -> MarkdownPostCommitIssue {
  match issue {
    @markdown_runtime.PortableCommitIssue::RuntimeFailure(detail~) =>
      MarkdownPostCommitIssue::RuntimeFailure(detail~)
    @markdown_runtime.PortableCommitIssue::ProjectionUnavailable =>
      MarkdownPostCommitIssue::ProjectionUnavailable
    @markdown_runtime.PortableCommitIssue::ProjectionFailed(..) =>
      MarkdownPostCommitIssue::ProjectionFailed
    @markdown_runtime.PortableCommitIssue::UnexpectedTransformCount(count~) =>
      MarkdownPostCommitIssue::UnexpectedTransformCount(count~)
  }
}

///|
/// Preserve pre-commit failure categories while keeping committed failures out
/// of the edit-rejection channel.
fn portable_not_committed_error(
  issue : @markdown_runtime.PortableCommitIssue,
) -> Result[
  (MarkdownCommitResult, @vector.Vector[MarkdownTextTransform]),
  MarkdownEditorError,
] raise Failure {
  match issue {
    @markdown_runtime.PortableCommitIssue::ProjectionUnavailable =>
      Err(MarkdownEditorError::ProjectionUnavailable)
    @markdown_runtime.PortableCommitIssue::RuntimeFailure(detail~) =>
      raise Failure::Failure(detail)
    @markdown_runtime.PortableCommitIssue::ProjectionFailed(..) =>
      Err(
        MarkdownEditorError::EditFailed(
          detail="portable Markdown projection failed",
        ),
      )
    @markdown_runtime.PortableCommitIssue::UnexpectedTransformCount(..) =>
      Err(
        MarkdownEditorError::EditFailed(
          detail="unexpected Markdown transform count",
        ),
      )
  }
}

///|
fn markdown_text_transform(edit : @core.SpanEdit) -> MarkdownTextTransform {
  MarkdownTextTransform::{
    change: @text_change.TextChange::{
      start: edit.start,
      delete_len: edit.delete_len,
      inserted: edit.inserted,
    },
  }
}

///|
fn project_portable_transform(
  before : @markdown_runtime.PortableCoordinateMap,
  edit : @core.SpanEdit,
  after : @markdown_runtime.PortableCoordinateMap,
) -> Result[MarkdownTextTransform, MarkdownEditorError] {
  match before.project_edit(edit, after) {
    Ok(projected) => Ok(markdown_text_transform(projected))
    Err(_) =>
      Err(
        committed_editor_error(
          before.source(),
          Some(after.source()),
          MarkdownPostCommitIssue::ProjectionFailed,
        ),
      )
  }
}

///|
/// Preserve the façade's projection category while rendering all language
/// lowering failures through its existing compatibility error.
fn structural_edit_error(error : @core.EditError) -> MarkdownEditorError {
  match error {
    @core.EditError::ProjectionUnavailable =>
      MarkdownEditorError::ProjectionUnavailable
    _ => MarkdownEditorError::EditFailed(detail=error.message())
  }
}

///|
/// Keep the public block façade narrower than the general Markdown edit API.
/// List items and container descendants remain available to lower-level edit
/// tests, but are not block-surface targets until their own UI contract exists.
fn MarkdownEditor::editable_block_target(
  self : Self,
  node_id : MarkdownNodeId,
) -> Bool raise Failure {
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
) -> String? raise Failure {
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
) -> MarkdownProjectionSnapshot raise Failure {
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
) -> MarkdownDocumentSnapshot raise Failure {
  document_snapshot_with_coordinates(editor).snapshot
}

///|
/// Build the detached snapshot and cursor map from the same parser epoch.
fn document_snapshot_with_coordinates(
  editor : @editor.SyncEditor[@md_markdown.Block],
) -> PortableDocumentSnapshot raise Failure {
  let coordinates = capture_portable_coordinates(editor)
  document_snapshot_from_coordinates(editor, coordinates)
}

///|
fn document_snapshot_from_coordinates(
  editor : @editor.SyncEditor[@md_markdown.Block],
  coordinates : @markdown_runtime.PortableCoordinateMap,
) -> PortableDocumentSnapshot raise Failure {
  let canonical = editor.get_text()
  let snapshot = MarkdownDocumentSnapshot::{
    source: coordinates.source(),
    projection: projection_snapshot(editor),
    blocks: editable_block_snapshots(editor, canonical, coordinates),
  }
  { snapshot, coordinates }
}

///|
fn committed_document_snapshot(
  editor : @editor.SyncEditor[@md_markdown.Block],
  before : String,
  after : String,
) -> Result[PortableDocumentSnapshot, MarkdownEditorError] {
  Ok(document_snapshot_with_coordinates(editor)) catch {
    Failure::Failure(detail) =>
      Err(
        committed_editor_error(
          before,
          Some(after),
          MarkdownPostCommitIssue::RuntimeFailure(detail~),
        ),
      )
  }
}

///|
fn committed_document_snapshot_from_coordinates(
  editor : @editor.SyncEditor[@md_markdown.Block],
  before : String,
  coordinates : @markdown_runtime.PortableCoordinateMap,
) -> Result[PortableDocumentSnapshot, MarkdownEditorError] {
  let after = coordinates.source()
  Ok(document_snapshot_from_coordinates(editor, coordinates)) catch {
    Failure::Failure(detail) =>
      Err(
        committed_editor_error(
          before,
          Some(after),
          MarkdownPostCommitIssue::RuntimeFailure(detail~),
        ),
      )
  }
}

///|
fn capture_portable_coordinates(
  editor : @editor.SyncEditor[@md_markdown.Block],
) -> @markdown_runtime.PortableCoordinateMap raise Failure {
  match @markdown_runtime.capture_portable_coordinates(editor) {
    Ok(coordinates) => coordinates
    Err(_) =>
      raise Failure::Failure("Markdown portable snapshot projection failed")
  }
}

///|
fn capture_committed_portable_coordinates(
  editor : @editor.SyncEditor[@md_markdown.Block],
  before : String,
) -> Result[@markdown_runtime.PortableCoordinateMap, MarkdownEditorError] {
  match @markdown_runtime.capture_portable_coordinates(editor) {
    Ok(coordinates) => Ok(coordinates)
    Err(issue) =>
      Err(
        committed_editor_error(before, None, markdown_post_commit_issue(issue)),
      )
  }
}

///|
fn editable_block_snapshots(
  editor : @editor.SyncEditor[@md_markdown.Block],
  source : String,
  coordinates : @markdown_runtime.PortableCoordinateMap,
) -> @vector.Vector[MarkdownBlockSnapshot] raise Failure {
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
                      coordinates,
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
                      coordinates,
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
              coordinates,
            )
          @md_markdown.Heading(level, _) =>
            append_editable_block_snapshot(
              blocks,
              node,
              MarkdownBlockKind::Heading(level~),
              source,
              source_map,
              coordinates,
            )
          @md_markdown.CodeBlock(info, _) =>
            append_editable_block_snapshot(
              blocks,
              node,
              MarkdownBlockKind::CodeBlock(info~),
              source,
              source_map,
              coordinates,
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
  coordinates : @markdown_runtime.PortableCoordinateMap,
) -> Unit raise Failure {
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
  let (source_start, source_end) = project_snapshot_range(
    coordinates,
    source_range.start,
    source_range.end,
  )
  let (text_start, text_end) = project_snapshot_range(
    coordinates,
    text_span.start,
    text_span.end,
  )
  let (marker_start, marker_end) = project_optional_snapshot_range(
    coordinates,
    marker_range.map(range => range.start),
    marker_range.map(range => range.end),
  )
  let (fence_open_start, fence_open_end) = project_optional_snapshot_range(
    coordinates,
    fence_open_range.map(range => range.start),
    fence_open_range.map(range => range.end),
  )
  let (fence_close_start, fence_close_end) = project_optional_snapshot_range(
    coordinates,
    fence_close_range.map(range => range.start),
    fence_close_range.map(range => range.end),
  )
  blocks.push({
    node_id: { value: node.id() },
    kind,
    text: source[text_span.start:text_span.end].to_owned(),
    source_start,
    source_end,
    text_start,
    text_end,
    marker_start,
    marker_end,
    fence_open_start,
    fence_open_end,
    fence_close_start,
    fence_close_end,
  })
}

///|
fn project_snapshot_range(
  coordinates : @markdown_runtime.PortableCoordinateMap,
  start : Int,
  end : Int,
) -> (Int, Int) raise Failure {
  match coordinates.project_range(start, end) {
    Ok(projected) => projected
    Err(_) =>
      raise Failure::Failure("Markdown snapshot range projection failed")
  }
}

///|
fn project_optional_snapshot_range(
  coordinates : @markdown_runtime.PortableCoordinateMap,
  start : Int?,
  end : Int?,
) -> (Int?, Int?) raise Failure {
  match (start, end) {
    (None, None) => (None, None)
    (Some(start), Some(end)) => {
      let (start, end) = project_snapshot_range(coordinates, start, end)
      (Some(start), Some(end))
    }
    _ => raise Failure::Failure("Markdown snapshot range roles disagreed")
  }
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
