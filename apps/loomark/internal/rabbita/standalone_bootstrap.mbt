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
    let prepared = @repository.prepare_local_text(document_id~, source~)
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
/// Create a fresh source-only local document after an empty slot is observed.
fn create_bootstrap_document(
  session_ref : @ref.Ref[EditorSession],
  model : DriverModel,
  source : String,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
  create_local_text_document(session_ref, model, source, emit)
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
    @archive_storage.LocalArchiveStorageRead::LocalText(encoded) => {
      let replica_id = @archive_storage.fresh_id("loomark-standalone-writer-")
      match @repository.decode_local_text(encoded) {
        @repository.LocalTextDecode::Valid(document_id~, source=local_source) =>
          start_local_text(
            model, document_id, local_source, replica_id, false, emit,
          )
        _ =>
          bootstrap_rejected(
            session_ref,
            model,
            RecoveryCategory::CorruptArchive,
          )
      }
    }
    @archive_storage.LocalArchiveStorageRead::LegacyArchive(encoded) => {
      let replica_id = @archive_storage.fresh_id("loomark-standalone-writer-")
      match @repository.decode_v1_archive_text(encoded) {
        @repository.LocalTextDecode::Valid(document_id~, source=local_source) =>
          start_local_text(
            model, document_id, local_source, replica_id, false, emit,
          )
        @repository.LocalTextDecode::UnsupportedArchive(_) =>
          bootstrap_rejected(
            session_ref,
            model,
            RecoveryCategory::UnsupportedArchive,
          )
        @repository.LocalTextDecode::Invalid =>
          bootstrap_rejected(
            session_ref,
            model,
            RecoveryCategory::CorruptArchive,
          )
      }
    }
  }
}
