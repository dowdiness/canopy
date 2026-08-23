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
fn recovery_code(category : RecoveryCategory) -> String {
  match category {
    RecoveryCategory::StorageUnavailable => "storage-unavailable"
    RecoveryCategory::StorageReadFailed => "storage-read-failed"
    RecoveryCategory::EditorInitializationFailed =>
      "editor-initialization-failed"
    RecoveryCategory::UnsupportedArchive => "unsupported-archive"
    RecoveryCategory::CorruptArchive => "corrupt-archive"
    RecoveryCategory::ArchiveOverLimit => "archive-over-limit"
    RecoveryCategory::IncompleteArchive => "incomplete-archive"
  }
}

///|
fn bootstrap_rejected(
  session_ref : @ref.Ref[EditorSession],
  model : DriverModel,
  category : RecoveryCategory,
) -> (DriverModel, @cmd.Cmd) {
  session_ref.val.attachment.dispose()
  (
    {
      ..model,
      archive_persistence_enabled: false,
      bootstrap_pending: false,
      fatal: true,
      error: None,
      error_code: Some(recovery_code(category)),
      error_operation: Some("standalone-bootstrap"),
      rejection: None,
    },
    @cmd.none,
  )
}

///|
fn adopt_bootstrap_session(
  session_ref : @ref.Ref[EditorSession],
  model : DriverModel,
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  document_id : @archive.LoomarkDocumentId,
  replica_id : String,
  archive_queue : @repository.LocalArchivePersistenceQueue,
  command : @cmd.Cmd,
) -> (DriverModel, @cmd.Cmd) {
  let document = editor.snapshot() catch {
    _ => {
      attachment.dispose()
      return bootstrap_rejected(
        session_ref,
        model,
        RecoveryCategory::EditorInitializationFailed,
      )
    }
  }
  session_ref.val.attachment.dispose()
  session_ref.val = { editor, attachment }
  (
    {
      ..model,
      state: @core.ApplicationState::ApplicationState(@core.Raw),
      runtime_state: EditorRuntimeState::Healthy,
      document,
      document_version: editor.version(),
      document_id,
      raw_selection: None,
      archive_persistence_enabled: true,
      bootstrap_pending: false,
      semantic_document: None,
      preview_artifact: None,
      semantic_read_count: 0,
      split_preview_open: false,
      active_block_key: None,
      replica_id,
      source_revision: 0,
      text_input_generation: 0,
      fatal: false,
      error: None,
      error_code: None,
      error_operation: None,
      error_count: 0,
      committed_change_count: 0,
      reconstruction_attempt_count: 0,
      selection: None,
      measurement: None,
      event_detail: None,
      rejection: None,
      archive_queue,
    },
    command,
  )
}

///|
/// Enter source-only standalone editing without constructing CRDT state.
fn start_local_text(
  model : DriverModel,
  document_id : @archive.LoomarkDocumentId,
  source : String,
  replica_id : String,
  persist : Bool,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
  let queue = @repository.LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
    document_id~,
    queue_epoch=replica_id,
    current=model.document_version,
    durable=if persist { None } else { Some(model.document_version) },
  )
  let (archive_queue, command) = if persist {
    let prepared = @repository.prepare_local_text_source_prototype(
      document_id~,
      source~,
    )
    let (queue, pending) = queue.enqueue(
      document_version=model.document_version,
      archive=prepared,
    )
    (queue, local_archive_write_command(pending, emit))
  } else {
    (queue, @cmd.none)
  }
  (
    {
      ..model,
      runtime_state: EditorRuntimeState::LocalText(source),
      document_id,
      archive_persistence_enabled: true,
      bootstrap_pending: false,
      replica_id,
      archive_queue,
    },
    command,
  )
}

///|
fn create_local_text_document(
  session_ref : @ref.Ref[EditorSession],
  model : DriverModel,
  source : String,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
  let replica_id = @archive_storage.fresh_id("loomark-standalone-writer-")
  let document_id = @archive.LoomarkDocumentId::from_string(
    @archive_storage.fresh_id("loomark-document-"),
  ) catch {
    _ =>
      return bootstrap_rejected(
        session_ref,
        model,
        RecoveryCategory::EditorInitializationFailed,
      )
  }
  start_local_text(model, document_id, source, replica_id, true, emit)
}

///|
/// Create a fresh local document after an empty archive slot is observed.
fn create_bootstrap_document(
  session_ref : @ref.Ref[EditorSession],
  model : DriverModel,
  source : String,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
  if local_text_prototype_enabled {
    return create_local_text_document(session_ref, model, source, emit)
  }
  let replica_id = @archive_storage.fresh_id("loomark-standalone-writer-")
  let document_id = @archive.LoomarkDocumentId::from_string(
    @archive_storage.fresh_id("loomark-document-"),
  ) catch {
    _ =>
      return bootstrap_rejected(
        session_ref,
        model,
        RecoveryCategory::EditorInitializationFailed,
      )
  }
  let (editor, attachment) = @markdown.MarkdownEditor::with_semantic_attachment(
    agent_id=replica_id,
    source~,
  ) catch {
    _ =>
      return bootstrap_rejected(
        session_ref,
        model,
        RecoveryCategory::EditorInitializationFailed,
      )
  }
  let archive_queue = @repository.LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
    document_id~,
    queue_epoch=replica_id,
    current=editor.version(),
    durable=None,
  )
  let prepared = @repository.prepare_local_archive(document_id~, editor~) catch {
    _ =>
      return adopt_bootstrap_session(
        session_ref,
        model,
        editor,
        attachment,
        document_id,
        replica_id,
        archive_queue.mark_failed(
          document_version=editor.version(),
          error=@repository.LocalArchivePersistenceFailure::PreparationFailed,
        ),
        @cmd.none,
      )
  }
  let (archive_queue, pending) = archive_queue.enqueue(
    document_version=editor.version(),
    archive=prepared,
  )
  let command = local_archive_write_command(pending, emit)
  adopt_bootstrap_session(
    session_ref, model, editor, attachment, document_id, replica_id, archive_queue,
    command,
  )
}

///|
/// Finish the initial storage Cmd inside the existing Rabbita update loop.
fn update_standalone_bootstrap(
  session_ref : @ref.Ref[EditorSession],
  model : DriverModel,
  loaded : @archive_storage.LocalArchiveStorageRead,
  source : String,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
  guard !model.archive_persistence_enabled else { return (model, @cmd.none) }
  match loaded {
    @archive_storage.LocalArchiveStorageRead::Missing =>
      create_bootstrap_document(session_ref, model, source, emit)
    @archive_storage.LocalArchiveStorageRead::Failed(
      @repository.LocalArchiveStorageReadFailure::Unavailable
    ) =>
      bootstrap_rejected(
        session_ref,
        model,
        RecoveryCategory::StorageUnavailable,
      )
    @archive_storage.LocalArchiveStorageRead::Failed(
      @repository.LocalArchiveStorageReadFailure::Failed
    ) =>
      bootstrap_rejected(
        session_ref,
        model,
        RecoveryCategory::StorageReadFailed,
      )
    @archive_storage.LocalArchiveStorageRead::Loaded(encoded) => {
      let replica_id = @archive_storage.fresh_id("loomark-standalone-writer-")
      if local_text_prototype_enabled {
        return match @repository.decode_local_text_prototype_record(encoded) {
          Some((document_id, local_source)) =>
            start_local_text(
              model, document_id, local_source, replica_id, false, emit,
            )
          None =>
            bootstrap_rejected(
              session_ref,
              model,
              RecoveryCategory::CorruptArchive,
            )
        }
      }
      let policy = @repository.LocalRestorePolicy::trusted()
      let classified = @repository.classify_local_archive_record(
        Some(encoded),
        agent_id=replica_id,
        policy~,
      ) catch {
        _ =>
          return bootstrap_rejected(
            session_ref,
            model,
            RecoveryCategory::CorruptArchive,
          )
      }
      match classified {
        @repository.LocalArchiveLoad::Valid(reopened) =>
          adopt_bootstrap_session(
            session_ref,
            model,
            reopened.editor(),
            reopened.attachment(),
            reopened.document_id(),
            replica_id,
            @repository.LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
              document_id=reopened.document_id(),
              queue_epoch=replica_id,
              current=reopened.editor().version(),
              durable=Some(reopened.editor().version()),
            ),
            @cmd.none,
          )
        @repository.LocalArchiveLoad::Rejected(failure) =>
          bootstrap_rejected(session_ref, model, recovery_category(failure))
        @repository.LocalArchiveLoad::Missing =>
          create_bootstrap_document(session_ref, model, source, emit)
      }
    }
  }
}
