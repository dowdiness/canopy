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
  Valid(@archive.LoomarkDocumentArchive)
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
/// Decode one raw local record, keeping missing storage distinct from failure.
pub fn classify_local_archive_record(
  raw_record : String?,
  validation_agent_id~ : String,
  policy~ : LocalRestorePolicy,
) -> LocalArchiveLoad raise {
  match raw_record {
    None => LocalArchiveLoad::Missing
    Some(encoded) => {
      let archive = @archive.LoomarkDocumentArchive::from_json_string(
        encoded,
        validation_agent_id~,
        open_limits=policy.open_limits,
      ) catch {
        Failure::Failure(_) as failure => raise failure
        @archive.LoomarkArchiveDecodeError::UnsupportedNewerVersion(..) as error =>
          return LocalArchiveLoad::Rejected(map_decode_failure(error))
        @archive.LoomarkArchiveDecodeError::MalformedEnvelope(..) as error =>
          return LocalArchiveLoad::Rejected(map_decode_failure(error))
        @archive.LoomarkArchiveDecodeError::EmptyDocumentId as error =>
          return LocalArchiveLoad::Rejected(map_decode_failure(error))
        @archive.LoomarkArchiveDecodeError::CorruptHistory(..) as error =>
          return LocalArchiveLoad::Rejected(map_decode_failure(error))
        @archive.LoomarkArchiveDecodeError::PortableTextHistoryMismatch as error =>
          return LocalArchiveLoad::Rejected(map_decode_failure(error))
        @archive.LoomarkArchiveDecodeError::InvalidValidationAgentId as error =>
          return LocalArchiveLoad::Rejected(map_decode_failure(error))
        @archive.LoomarkArchiveDecodeError::WriterCreationFailed(..) as error =>
          return LocalArchiveLoad::Rejected(map_decode_failure(error))
        @archive.LoomarkArchiveDecodeError::LimitExceeded(..) as error =>
          return LocalArchiveLoad::Rejected(map_decode_failure(error))
        @archive.LoomarkArchiveDecodeError::HistoryAdmissionFailed(..) as error =>
          return LocalArchiveLoad::Rejected(map_decode_failure(error))
        @archive.LoomarkArchiveDecodeError::HistoryExportFailed(..) as error =>
          return LocalArchiveLoad::Rejected(map_decode_failure(error))
        @archive.LoomarkArchiveDecodeError::IncompleteHistory as error =>
          return LocalArchiveLoad::Rejected(map_decode_failure(error))
        error => raise error
      }
      LocalArchiveLoad::Valid(archive)
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
}

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
/// Monotonic identity assigned to one repository replacement request.
pub struct LocalArchiveRequestId {
  priv value : Int
} derive(Eq, Debug)

///|
/// Deterministic acknowledgment/warning state for repository operations.
pub struct LocalArchiveRequestTracker {
  priv next_value : Int
  priv latest : LocalArchiveRequestId?
  priv warning : Bool
} derive(Eq)

///|
/// Start an empty acknowledgment tracker.
pub fn LocalArchiveRequestTracker::new() -> LocalArchiveRequestTracker {
  { next_value: 1, latest: None, warning: false }
}

///|
/// Allocate the next request without changing warning state.
pub fn LocalArchiveRequestTracker::request(
  self : Self,
) -> (LocalArchiveRequestTracker, LocalArchiveRequestId) {
  let request_id = LocalArchiveRequestId::{ value: self.next_value }
  (
    {
      next_value: self.next_value + 1,
      latest: Some(request_id),
      warning: self.warning,
    },
    request_id,
  )
}

///|
/// Apply success only when it acknowledges the latest request.
pub fn LocalArchiveRequestTracker::complete_success(
  self : Self,
  request_id : LocalArchiveRequestId,
) -> LocalArchiveRequestTracker {
  match self.latest {
    Some(latest) if latest == request_id =>
      { ..self, latest: None, warning: false }
    _ => self
  }
}

///|
/// Apply failure only when it belongs to the latest request.
pub fn LocalArchiveRequestTracker::complete_failure(
  self : Self,
  request_id : LocalArchiveRequestId,
) -> LocalArchiveRequestTracker {
  match self.latest {
    Some(latest) if latest == request_id =>
      { ..self, latest: None, warning: true }
    _ => self
  }
}

///|
/// Whether the latest acknowledged operation currently warns.
pub fn LocalArchiveRequestTracker::has_warning(self : Self) -> Bool {
  self.warning
}

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
/// Reopen a validated archive through the semantic Markdown façade.
pub fn reopen_local_archive(
  archive : @archive.LoomarkDocumentArchive,
  agent_id~ : String,
  policy~ : LocalRestorePolicy,
) -> ReopenedLocalArchive raise {
  let (editor, attachment) = @markdown.MarkdownEditor::open_with_semantic_attachment(
    agent_id~,
    history=archive.history(),
    open_limits=policy.open_limits,
  )
  { document_id: archive.document_id(), editor, attachment }
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
  )
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
