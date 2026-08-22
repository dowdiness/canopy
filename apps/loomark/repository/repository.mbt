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
/// Storage-read categories reserved for the imperative provider shell.
pub(all) enum LocalArchiveStorageReadFailure {
  Unavailable
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
