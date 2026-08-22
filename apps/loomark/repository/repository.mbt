///| Pure local-archive policy and repository decisions.

///|
/// Resource policy for archives restored from the local repository.
pub struct LocalRestorePolicy {
  priv open_limits : @markdown.MarkdownArchiveOpenLimits
}

///|
/// Wrap caller-selected archive limits without borrowing peer/network policy.
pub fn LocalRestorePolicy::LocalRestorePolicy(
  open_limits : @markdown.MarkdownArchiveOpenLimits,
) -> LocalRestorePolicy {
  { open_limits, }
}

///|
/// Maximum representable local admission dimension.
///
/// The browser provider's own quota bounds records written by this device.
/// Local restore therefore avoids an unrelated network or test ceiling while
/// still passing an explicit policy to the shared admission API.
const TRUSTED_LOCAL_ADMISSION_MAXIMUM : Int = 2147483647

///|
/// Construct the explicit policy for a device-owned local archive.
pub fn LocalRestorePolicy::trusted() -> LocalRestorePolicy {
  let open_limits = @markdown.MarkdownArchiveOpenLimits(
    max_encoded_bytes=TRUSTED_LOCAL_ADMISSION_MAXIMUM,
    max_decoded_operations=TRUSTED_LOCAL_ADMISSION_MAXIMUM,
    max_pending_operations=TRUSTED_LOCAL_ADMISSION_MAXIMUM,
    max_parents_per_operation=TRUSTED_LOCAL_ADMISSION_MAXIMUM,
  ) catch {
    _ => abort("trusted local archive limits must be valid")
  }
  LocalRestorePolicy(open_limits)
}

///|
/// Typed archive-load failures for recovery and later shell mapping.
pub(all) enum LocalArchiveLoadFailure {
  UnsupportedNewerVersion(version~ : String)
  MalformedArchive(detail~ : String)
  CorruptArchive(detail~ : String)
  LimitExceeded(
    dimension~ : @markdown.MarkdownArchiveLimitDimension,
    maximum~ : Int,
    actual~ : Int
  )
  IncompleteHistory
  InvalidValidationAgentId
  WriterCreationFailed(detail~ : String)
  HistoryAdmissionFailed(detail~ : String)
  HistoryExportFailed(detail~ : String)
} derive(Eq, Debug)

///|
/// Classification of the raw active-slot record.
pub(all) enum LocalArchiveLoad {
  Missing
  Valid(ReopenedLocalArchive)
  Rejected(LocalArchiveLoadFailure)
}

///|
/// Map the archive package's typed decode taxonomy without parsing messages.
fn map_decode_failure(
  error : @archive.LoomarkArchiveDecodeError,
) -> LocalArchiveLoadFailure {
  match error {
    @archive.LoomarkArchiveDecodeError::UnsupportedNewerVersion(version~) =>
      LocalArchiveLoadFailure::UnsupportedNewerVersion(version~)
    @archive.LoomarkArchiveDecodeError::MalformedEnvelope(detail~) =>
      LocalArchiveLoadFailure::MalformedArchive(detail~)
    @archive.LoomarkArchiveDecodeError::EmptyDocumentId =>
      LocalArchiveLoadFailure::MalformedArchive(detail="empty document id")
    @archive.LoomarkArchiveDecodeError::CorruptHistory(detail~) =>
      LocalArchiveLoadFailure::CorruptArchive(detail~)
    @archive.LoomarkArchiveDecodeError::PortableTextHistoryMismatch =>
      LocalArchiveLoadFailure::CorruptArchive(
        detail="portable text does not match canonical history",
      )
    @archive.LoomarkArchiveDecodeError::InvalidValidationAgentId =>
      LocalArchiveLoadFailure::InvalidValidationAgentId
    @archive.LoomarkArchiveDecodeError::WriterCreationFailed(detail~) =>
      LocalArchiveLoadFailure::WriterCreationFailed(detail~)
    @archive.LoomarkArchiveDecodeError::LimitExceeded(
      dimension~,
      maximum~,
      actual~
    ) => LocalArchiveLoadFailure::LimitExceeded(dimension~, maximum~, actual~)
    @archive.LoomarkArchiveDecodeError::HistoryAdmissionFailed(detail~) =>
      LocalArchiveLoadFailure::HistoryAdmissionFailed(detail~)
    @archive.LoomarkArchiveDecodeError::HistoryExportFailed(detail~) =>
      LocalArchiveLoadFailure::HistoryExportFailed(detail~)
    @archive.LoomarkArchiveDecodeError::IncompleteHistory =>
      LocalArchiveLoadFailure::IncompleteHistory
  }
}

///|
/// Turn one archive-boundary failure into a rejected local record.
fn reject_decode_failure(
  error : @archive.LoomarkArchiveDecodeError,
) -> LocalArchiveLoad {
  LocalArchiveLoad::Rejected(map_decode_failure(error))
}

///|
/// Decode and reopen one raw local record, keeping missing storage distinct.
pub fn classify_local_archive_record(
  raw_record : String?,
  agent_id~ : String,
  policy~ : LocalRestorePolicy,
) -> LocalArchiveLoad raise {
  match raw_record {
    None => LocalArchiveLoad::Missing
    Some(encoded) => {
      let decoded = @archive.LoomarkDocumentArchive::decode_json_string(encoded) catch {
        Failure::Failure(_) as failure => raise failure
        @archive.LoomarkArchiveDecodeError::UnsupportedNewerVersion(..) as error =>
          return reject_decode_failure(error)
        @archive.LoomarkArchiveDecodeError::MalformedEnvelope(..) as error =>
          return reject_decode_failure(error)
        @archive.LoomarkArchiveDecodeError::EmptyDocumentId as error =>
          return reject_decode_failure(error)
        @archive.LoomarkArchiveDecodeError::CorruptHistory(..) as error =>
          return reject_decode_failure(error)
        error => raise error
      }
      let reopened = reopen_decoded_local_archive(decoded, agent_id~, policy~) catch {
        Failure::Failure(_) as failure => raise failure
        @archive.LoomarkArchiveDecodeError::UnsupportedNewerVersion(..) as error =>
          return reject_decode_failure(error)
        @archive.LoomarkArchiveDecodeError::MalformedEnvelope(..) as error =>
          return reject_decode_failure(error)
        @archive.LoomarkArchiveDecodeError::EmptyDocumentId as error =>
          return reject_decode_failure(error)
        @archive.LoomarkArchiveDecodeError::CorruptHistory(..) as error =>
          return reject_decode_failure(error)
        @archive.LoomarkArchiveDecodeError::PortableTextHistoryMismatch as error =>
          return reject_decode_failure(error)
        @archive.LoomarkArchiveDecodeError::InvalidValidationAgentId as error =>
          return reject_decode_failure(error)
        @archive.LoomarkArchiveDecodeError::WriterCreationFailed(..) as error =>
          return reject_decode_failure(error)
        @archive.LoomarkArchiveDecodeError::LimitExceeded(..) as error =>
          return reject_decode_failure(error)
        @archive.LoomarkArchiveDecodeError::HistoryAdmissionFailed(..) as error =>
          return reject_decode_failure(error)
        @archive.LoomarkArchiveDecodeError::HistoryExportFailed(..) as error =>
          return reject_decode_failure(error)
        @archive.LoomarkArchiveDecodeError::IncompleteHistory as error =>
          return reject_decode_failure(error)
        error => raise error
      }
      LocalArchiveLoad::Valid(reopened)
    }
  }
}

///|
/// Failure while preparing a complete replacement value.
pub(all) suberror LocalArchivePreparationError {
  HistoryUnavailable(detail~ : String)
}

///|
/// One immutable complete encoded replacement, ready for a storage shell.
pub struct PreparedLocalArchive {
  priv encoded : String
} derive(Eq)

///|
/// Prepare the sole complete envelope from a logical ID and editor state.
pub fn prepare_local_archive(
  document_id~ : @archive.LoomarkDocumentId,
  editor~ : @markdown.MarkdownEditor,
) -> PreparedLocalArchive raise {
  let archive = @archive.LoomarkDocumentArchive::capture(document_id~, editor~) catch {
    Failure::Failure(_) as failure => raise failure
    @archive.LoomarkArchiveCaptureError::HistoryUnavailable(detail~) =>
      raise LocalArchivePreparationError::HistoryUnavailable(detail~)
    error => raise error
  }
  { encoded: archive.to_json_string() }
}

///|
/// Prepare a replacement while forwarding diagnostic capture milestones.
pub fn prepare_local_archive_observing(
  document_id~ : @archive.LoomarkDocumentId,
  editor~ : @markdown.MarkdownEditor,
  observer : (@archive.LoomarkArchivePreparationPhase) -> Unit,
) -> PreparedLocalArchive raise {
  let archive = @archive.LoomarkDocumentArchive::capture_observing(
    document_id~,
    editor~,
    observer,
  ) catch {
    Failure::Failure(_) as failure => raise failure
    @archive.LoomarkArchiveCaptureError::HistoryUnavailable(detail~) =>
      raise LocalArchivePreparationError::HistoryUnavailable(detail~)
    error => raise error
  }
  { encoded: archive.to_json_string_observing(observer) }
}

///|
/// Return the deterministic encoded replacement payload.
pub fn PreparedLocalArchive::encoded(self : Self) -> String {
  self.encoded
}

///|
/// Whether a commit authorizes a complete archive replacement.
pub(all) enum LocalArchivePersistenceDecision {
  Replace
  Skip
} derive(Eq, Debug)

///|
/// History advancement, not source comparison, controls persistence.
pub fn history_trigger(
  receipt : @markdown.MarkdownCommitReceipt,
) -> LocalArchivePersistenceDecision {
  match receipt.history() {
    Some(_) => LocalArchivePersistenceDecision::Replace
    None => LocalArchivePersistenceDecision::Skip
  }
}

///|
/// The product-visible local durability state for one accepted document.
pub(all) enum LocalArchivePersistenceStatus {
  DurableLocal(@markdown.MarkdownDocumentVersion)
  Applied(
    current~ : @markdown.MarkdownDocumentVersion,
    durable~ : @markdown.MarkdownDocumentVersion?
  )
  StorageFailed(
    current~ : @markdown.MarkdownDocumentVersion,
    durable~ : @markdown.MarkdownDocumentVersion?,
    error~ : LocalArchiveStorageWriteFailure
  )
} derive(Eq, Debug)

///|
/// The provider-neutral outcome consumed by the persistence queue.
pub(all) enum LocalArchiveWriteOutcome {
  Stored
  Failed(LocalArchiveStorageWriteFailure)
} derive(Eq, Debug)

///|
/// The result of applying one correlated write acknowledgment.
pub(all) enum LocalArchiveQueueCompletion {
  Ignored
  Completed
  Promoted(LocalArchivePendingWrite)
} derive(Eq)

///|
/// One complete immutable archive replacement and its Session correlation.
pub struct LocalArchivePendingWrite {
  priv request_id : LocalArchiveRequestId
  priv document_id : @archive.LoomarkDocumentId
  priv document_version : @markdown.MarkdownDocumentVersion
  priv archive : PreparedLocalArchive
} derive(Eq)

///|
pub fn LocalArchivePendingWrite::request_id(
  self : Self,
) -> LocalArchiveRequestId {
  self.request_id
}

///|
pub fn LocalArchivePendingWrite::document_id(
  self : Self,
) -> @archive.LoomarkDocumentId {
  self.document_id
}

///|
pub fn LocalArchivePendingWrite::document_version(
  self : Self,
) -> @markdown.MarkdownDocumentVersion {
  self.document_version
}

///|
pub fn LocalArchivePendingWrite::encoded(self : Self) -> String {
  self.archive.encoded()
}

///|
/// Pure per-document single-flight persistence state.
pub struct LocalArchivePersistenceQueue {
  priv document_id : @archive.LoomarkDocumentId
  priv current : @markdown.MarkdownDocumentVersion
  priv durable : @markdown.MarkdownDocumentVersion?
  priv in_flight : LocalArchivePendingWrite?
  priv pending_latest : LocalArchivePendingWrite?
  priv next_request_value : Int
  priv failure : LocalArchiveStorageWriteFailure?
} derive(Eq)

///|
pub fn LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
  document_id~ : @archive.LoomarkDocumentId,
  current~ : @markdown.MarkdownDocumentVersion,
  durable~ : @markdown.MarkdownDocumentVersion?,
) -> LocalArchivePersistenceQueue {
  {
    document_id,
    current,
    durable,
    in_flight: None,
    pending_latest: None,
    next_request_value: 1,
    failure: None,
  }
}

///|
pub fn LocalArchivePersistenceQueue::status(
  self : Self,
) -> LocalArchivePersistenceStatus {
  match self.failure {
    Some(error) =>
      LocalArchivePersistenceStatus::StorageFailed(
        current=self.current,
        durable=self.durable,
        error~,
      )
    None =>
      match self.durable {
        Some(durable) if durable == self.current =>
          LocalArchivePersistenceStatus::DurableLocal(self.current)
        _ =>
          LocalArchivePersistenceStatus::Applied(
            current=self.current,
            durable=self.durable,
          )
      }
  }
}

///|
fn LocalArchivePersistenceQueue::allocate_pending(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  archive~ : PreparedLocalArchive,
) -> (LocalArchivePersistenceQueue, LocalArchivePendingWrite) {
  let pending = LocalArchivePendingWrite::{
    request_id: LocalArchiveRequestId::{ value: self.next_request_value },
    document_id: self.document_id,
    document_version,
    archive,
  }
  ({ ..self, next_request_value: self.next_request_value + 1 }, pending)
}

///|
/// Accept a complete archive, starting it or coalescing it as the latest.
pub fn LocalArchivePersistenceQueue::enqueue(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  archive~ : PreparedLocalArchive,
) -> (LocalArchivePersistenceQueue, LocalArchivePendingWrite?) {
  let (next, pending) = self.allocate_pending(document_version~, archive~)
  match next.in_flight {
    None =>
      (
        {
          ..next,
          current: document_version,
          in_flight: Some(pending),
          pending_latest: None,
          failure: None,
        },
        Some(pending),
      )
    Some(_) =>
      (
        {
          ..next,
          current: document_version,
          pending_latest: Some(pending),
          failure: None,
        },
        None,
      )
  }
}

///|
/// Retry only the current failed version; an active write makes it busy.
pub fn LocalArchivePersistenceQueue::retry(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  archive~ : PreparedLocalArchive,
) -> (LocalArchivePersistenceQueue, LocalArchivePendingWrite?) {
  guard self.failure is Some(_) && self.in_flight is None else {
    return (self, None)
  }
  guard self.current == document_version else { return (self, None) }
  self.enqueue(document_version~, archive~)
}

///|
/// Record a current-version failure and supersede older pending work.
pub fn LocalArchivePersistenceQueue::mark_failed(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  error~ : LocalArchiveStorageWriteFailure,
) -> LocalArchivePersistenceQueue {
  {
    ..self,
    current: document_version,
    pending_latest: None,
    failure: Some(error),
  }
}

///|
fn LocalArchivePendingWrite::matches(
  self : Self,
  other : LocalArchivePendingWrite,
) -> Bool {
  self.request_id == other.request_id &&
  self.document_id == other.document_id &&
  self.document_version == other.document_version
}

///|
/// Apply one acknowledgment and optionally promote the latest pending archive.
pub fn LocalArchivePersistenceQueue::complete(
  self : Self,
  pending : LocalArchivePendingWrite,
  outcome : LocalArchiveWriteOutcome,
) -> (LocalArchivePersistenceQueue, LocalArchiveQueueCompletion) {
  guard self.in_flight is Some(in_flight) else {
    return (self, LocalArchiveQueueCompletion::Ignored)
  }
  guard in_flight.matches(pending) else {
    return (self, LocalArchiveQueueCompletion::Ignored)
  }
  let current_write = pending.document_version()
  let is_current = self.current == current_write
  match self.pending_latest {
    Some(next_pending) => {
      let durable = match outcome {
        LocalArchiveWriteOutcome::Stored => Some(current_write)
        LocalArchiveWriteOutcome::Failed(_) => self.durable
      }
      let failure = if next_pending.document_version() == self.current {
        None
      } else {
        self.failure
      }
      (
        {
          ..self,
          durable,
          in_flight: Some(next_pending),
          pending_latest: None,
          failure,
        },
        LocalArchiveQueueCompletion::Promoted(next_pending),
      )
    }
    None => {
      let (durable, failure) = match outcome {
        LocalArchiveWriteOutcome::Stored =>
          (Some(current_write), if is_current { None } else { self.failure })
        LocalArchiveWriteOutcome::Failed(error) =>
          (self.durable, if is_current { Some(error) } else { self.failure })
      }
      (
        { ..self, durable, in_flight: None, failure },
        LocalArchiveQueueCompletion::Completed,
      )
    }
  }
}

///|
/// Monotonic identity assigned to one repository replacement request.
pub struct LocalArchiveRequestId {
  priv value : Int
} derive(Eq, Debug)

///|
/// Storage-read categories reserved for the imperative provider shell.
pub(all) enum LocalArchiveStorageReadFailure {
  Unavailable
  Failed
} derive(Eq, Debug)

///|
/// Storage-write categories reserved for the imperative provider shell.
pub(all) enum LocalArchiveStorageWriteFailure {
  Unavailable
  QuotaExceeded
  Failed
} derive(Eq, Debug)

///|
/// A reopened archive with a fresh writing instance and live semantic view.
pub struct ReopenedLocalArchive {
  priv document_id : @archive.LoomarkDocumentId
  priv editor : @markdown.MarkdownEditor
  priv attachment : @md_markdown.MarkdownSemanticAttachment
}

///|
/// Map one Markdown archive-open failure into the Loomark archive taxonomy.
fn map_markdown_archive_error(
  error : @markdown.MarkdownArchiveError,
) -> @archive.LoomarkArchiveDecodeError {
  match error {
    @markdown.MarkdownArchiveError::InvalidAgentId =>
      @archive.LoomarkArchiveDecodeError::InvalidValidationAgentId
    @markdown.MarkdownArchiveError::WriterCreationFailed(detail~) =>
      @archive.LoomarkArchiveDecodeError::WriterCreationFailed(detail~)
    @markdown.MarkdownArchiveError::LimitExceeded(dimension~, maximum~, actual~) =>
      @archive.LoomarkArchiveDecodeError::LimitExceeded(
        dimension~,
        maximum~,
        actual~,
      )
    @markdown.MarkdownArchiveError::HistoryAdmissionFailed(detail~) =>
      @archive.LoomarkArchiveDecodeError::HistoryAdmissionFailed(detail~)
    @markdown.MarkdownArchiveError::IncompleteHistory =>
      @archive.LoomarkArchiveDecodeError::IncompleteHistory
    @markdown.MarkdownArchiveError::ExportFailed(detail~) =>
      @archive.LoomarkArchiveDecodeError::HistoryExportFailed(detail~)
  }
}

///|
/// Reopen and validate a complete archive through one semantic Markdown façade.
pub fn reopen_local_archive(
  archive : @archive.LoomarkDocumentArchive,
  agent_id~ : String,
  policy~ : LocalRestorePolicy,
) -> ReopenedLocalArchive raise {
  let reopened = reopen_local_history(
    archive.history(),
    document_id=archive.document_id(),
    agent_id~,
    policy~,
  )
  verify_reopened_portable_markdown(reopened, archive.portable_markdown())
}

///|
/// Reopen a structurally decoded archive and admit its history exactly once.
pub fn reopen_decoded_local_archive(
  archive : @archive.DecodedLoomarkDocumentArchive,
  agent_id~ : String,
  policy~ : LocalRestorePolicy,
) -> ReopenedLocalArchive raise {
  let reopened = reopen_local_history(
    archive.history(),
    document_id=archive.document_id(),
    agent_id~,
    policy~,
  )
  verify_reopened_portable_markdown(reopened, archive.portable_markdown())
}

///|
/// Dispose a rejected attachment before surfacing the text/history mismatch.
fn verify_reopened_portable_markdown(
  reopened : ReopenedLocalArchive,
  expected : String,
) -> ReopenedLocalArchive raise {
  if reopened.editor.portable_markdown() != expected {
    reopened.attachment.dispose()
    raise @archive.LoomarkArchiveDecodeError::PortableTextHistoryMismatch
  }
  reopened
}

///|
/// Reopen parser-independent complete history captured from a terminal editor.
/// Unlike archive admission, this does not compare a parser-derived portable
/// text summary; the fresh editor becomes the authority after history replay.
pub fn reopen_local_history(
  history : @markdown.MarkdownDocumentHistory,
  document_id~ : @archive.LoomarkDocumentId,
  agent_id~ : String,
  policy~ : LocalRestorePolicy,
) -> ReopenedLocalArchive raise {
  let (editor, attachment) = @markdown.MarkdownEditor::open_with_semantic_attachment(
    agent_id~,
    history~,
    open_limits=policy.open_limits,
  ) catch {
    Failure::Failure(_) as failure => raise failure
    @markdown.MarkdownArchiveError::InvalidAgentId as error =>
      raise map_markdown_archive_error(error)
    @markdown.MarkdownArchiveError::WriterCreationFailed(..) as error =>
      raise map_markdown_archive_error(error)
    @markdown.MarkdownArchiveError::LimitExceeded(..) as error =>
      raise map_markdown_archive_error(error)
    @markdown.MarkdownArchiveError::HistoryAdmissionFailed(..) as error =>
      raise map_markdown_archive_error(error)
    @markdown.MarkdownArchiveError::ExportFailed(..) as error =>
      raise map_markdown_archive_error(error)
    @markdown.MarkdownArchiveError::IncompleteHistory as error =>
      raise map_markdown_archive_error(error)
    error => raise error
  }
  { document_id, editor, attachment }
}

///|
/// Preserve the logical document identity across reopen.
pub fn ReopenedLocalArchive::document_id(
  self : Self,
) -> @archive.LoomarkDocumentId {
  self.document_id
}

///|
/// Access the reopened editor writing under the supplied fresh identity.
pub fn ReopenedLocalArchive::editor(self : Self) -> @markdown.MarkdownEditor {
  self.editor
}

///|
/// Access the semantic attachment over that reopened editor.
pub fn ReopenedLocalArchive::attachment(
  self : Self,
) -> @md_markdown.MarkdownSemanticAttachment {
  self.attachment
}
