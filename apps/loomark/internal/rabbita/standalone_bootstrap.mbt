///|
/// Map repository admission failures to stable recovery categories.
fn recovery_category(
  failure : @repository.LocalArchiveLoadFailure,
) -> RecoveryCategory {
  match failure {
    @repository.LocalArchiveLoadFailure::UnsupportedNewerVersion(_) =>
      RecoveryCategory::UnsupportedArchive
    @repository.LocalArchiveLoadFailure::LimitExceeded(..) =>
      RecoveryCategory::ArchiveOverLimit
    @repository.LocalArchiveLoadFailure::IncompleteHistory =>
      RecoveryCategory::IncompleteArchive
    @repository.LocalArchiveLoadFailure::InvalidValidationAgentId
    | @repository.LocalArchiveLoadFailure::WriterCreationFailed(..) =>
      RecoveryCategory::EditorInitializationFailed
    @repository.LocalArchiveLoadFailure::MalformedArchive(..)
    | @repository.LocalArchiveLoadFailure::CorruptArchive(..)
    | @repository.LocalArchiveLoadFailure::HistoryAdmissionFailed(..)
    | @repository.LocalArchiveLoadFailure::HistoryExportFailed(..) =>
      RecoveryCategory::CorruptArchive
  }
}

///|
/// Mount one editor after the browser archive decision has completed.
fn mount_standalone_editor(
  host_id : String,
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  document_id : @archive.LoomarkDocumentId,
  replica_id : String,
  baseline : (@repository.LocalArchiveRequestId, String)?,
  archive_tracker : @repository.LocalArchiveRequestTracker,
  local_storage_warning : Bool,
) -> Unit {
  let initial = {
    ..initial_model(
      host_id,
      editor,
      document_id,
      replica_id,
      archive_persistence_enabled=true,
    ),
    archive_tracker,
    local_storage_warning,
  }
  detached_model.val = None
  detached_focus_token.val = ""
  publish(initial)
  let app = standalone_application(editor, attachment, initial, baseline)
  app.mount(host_id)
}

///|
/// Construct a new local document and schedule its complete baseline archive.
fn mount_new_standalone_document(host_id : String, source : String) -> Unit {
  let replica_id = @archive_storage.fresh_id("loomark-standalone-writer-")
  let document_id = try! @archive.LoomarkDocumentId::from_string(
    @archive_storage.fresh_id("loomark-document-"),
  )
  let (editor, attachment) = @markdown.MarkdownEditor::with_semantic_attachment(
    agent_id=replica_id,
    source~,
  ) catch {
    _ => {
      recovery_application(RecoveryCategory::EditorInitializationFailed).mount(
        host_id,
      )
      return
    }
  }
  let tracker = @repository.LocalArchiveRequestTracker::new()
  let prepared = @repository.prepare_local_archive(document_id~, editor~) catch {
    _ => {
      mount_standalone_editor(
        host_id,
        editor,
        attachment,
        document_id,
        replica_id,
        None,
        tracker,
        true,
      )
      return
    }
  }
  let (tracker, request_id) = tracker.request()
  mount_standalone_editor(
    host_id,
    editor,
    attachment,
    document_id,
    replica_id,
    Some((request_id, prepared.encoded())),
    tracker,
    false,
  )
}

///|
/// Continue a validated local document with a fresh writing instance.
fn mount_reopened_standalone_document(
  host_id : String,
  archive : @archive.LoomarkDocumentArchive,
) -> Unit {
  let policy = @repository.LocalRestorePolicy::trusted()
  let replica_id = @archive_storage.fresh_id("loomark-standalone-writer-")
  let reopened = @repository.reopen_local_archive(
    archive,
    agent_id=replica_id,
    policy~,
  ) catch {
    _ => {
      recovery_application(RecoveryCategory::CorruptArchive).mount(host_id)
      return
    }
  }
  mount_standalone_editor(
    host_id,
    reopened.editor(),
    reopened.attachment(),
    reopened.document_id(),
    replica_id,
    None,
    @repository.LocalArchiveRequestTracker::new(),
    false,
  )
}

///|
/// Complete the callback-shaped standalone bootstrap without exposing storage.
fn finish_standalone_bootstrap(
  host_id : String,
  source : String,
  loaded : @archive_storage.LocalArchiveStorageRead,
) -> Unit {
  match loaded {
    @archive_storage.LocalArchiveStorageRead::Missing =>
      mount_new_standalone_document(host_id, source)
    @archive_storage.LocalArchiveStorageRead::Failed(
      @repository.LocalArchiveStorageReadFailure::Unavailable
    ) =>
      recovery_application(RecoveryCategory::StorageUnavailable).mount(host_id)
    @archive_storage.LocalArchiveStorageRead::Failed(
      @repository.LocalArchiveStorageReadFailure::Failed
    ) =>
      recovery_application(RecoveryCategory::StorageReadFailed).mount(host_id)
    @archive_storage.LocalArchiveStorageRead::Loaded(encoded) => {
      let policy = @repository.LocalRestorePolicy::trusted()
      let validation_agent_id = @archive_storage.fresh_id(
        "loomark-standalone-validator-",
      )
      match
        @repository.classify_local_archive_record(
          Some(encoded),
          validation_agent_id~,
          policy~,
        ) {
        @repository.LocalArchiveLoad::Valid(archive) =>
          mount_reopened_standalone_document(host_id, archive)
        @repository.LocalArchiveLoad::Rejected(failure) =>
          recovery_application(recovery_category(failure)).mount(host_id)
        @repository.LocalArchiveLoad::Missing =>
          mount_new_standalone_document(host_id, source)
      }
    }
  }
}
