///|
fn delete_is_active(phase : DocumentsDeletePhase) -> Bool {
  match phase {
    Available | Failed(_, _) => false
    Waiting(_) | Deleting(_) | Probing(_) | Unknown(_) => true
  }
}

///|
fn remove_record(
  records : Array[DocumentRecord],
  document_id : String,
) -> Array[DocumentRecord] {
  records.filter(record => record.source.document_id() != document_id)
}

///|
fn issue_delete(
  documents : Documents,
  operation : DeleteOperation,
  retained_save : DocumentsSaveStatus,
) -> (Documents, Array[DocumentsDecision]) {
  let records = replace_record(documents.records, operation.document_id, record => {
    ..record,
    save: retained_save,
    delete: Deleting(operation),
  })
  (
    { ..documents, records, },
    [DeleteSource(operation), ArmDeleteWatchdog(operation)],
  )
}

///|
fn begin_delete(
  documents : Documents,
  document_id : String,
  retained_save : DocumentsSaveStatus,
) -> (Documents, Array[DocumentsDecision]) {
  let request_id = documents.last_delete_request + 1
  issue_delete(
    { ..documents, last_delete_request: request_id },
    { document_id, request_id },
    retained_save,
  )
}

///|
/// Start a confirmed or retried deletion, fencing an active save first.
fn confirm_or_retry_delete(
  documents : Documents,
  document_id : String,
) -> (Documents, Array[DocumentsDecision]) {
  guard find_record(documents.records, document_id) is Some(record) else {
    return (documents, [])
  }
  let request_id = documents.last_delete_request + 1
  let operation = { document_id, request_id }
  let save_is_active = match record.save {
    Saving(_, _) => true
    _ => false
  }
  if record.origin == New && !save_is_active {
    (
      {
        ..documents,
        last_delete_request: request_id,
        records: remove_record(documents.records, document_id),
      },
      [],
    )
  } else if record.save is Saving(_, _) {
    (
      {
        ..documents,
        last_delete_request: request_id,
        records: replace_record(documents.records, document_id, r => {
          ..r,
          delete: Waiting(operation),
        }),
      },
      [],
    )
  } else {
    begin_delete(documents, document_id, record.save)
  }
}

///|
fn finish_delete(
  documents : Documents,
  operation : DeleteOperation,
  result : @source_repository.DeleteResult,
) -> (Documents, Array[DocumentsDecision]) {
  guard find_record(documents.records, operation.document_id) is Some(record) else {
    return (documents, [])
  }
  guard (match record.delete {
    Deleting(current)
    | Probing(current)
    | Unknown(current)
    | Failed(current, _) => current == operation
    Available | Waiting(_) => false
  }) else {
    return (documents, [])
  }
  match result {
    @source_repository.DeleteResult::Deleted(document_id) => {
      guard document_id == operation.document_id else { return (documents, []) }
      let snapshot = match documents.snapshot.source(document_id) {
        Some(_) =>
          match
            documents.snapshot.apply_acknowledged(
              @source_repository.AcknowledgedChange::SourceDeleted(document_id),
            ) {
            Some(snapshot) => snapshot
            None => return (documents, [])
          }
        None => documents.snapshot
      }
      (
        {
          ..documents,
          snapshot,
          records: remove_record(documents.records, document_id),
        },
        [],
      )
    }
    @source_repository.DeleteResult::Failed(failure) => {
      let restored = { ..record, delete: Failed(operation, failure) }
      let (restored, decisions) = match record.save {
        Waiting(checkpoint) if checkpoint.eligibility == Eligible &&
          !record.composing => begin_save(restored)
        Waiting(checkpoint) if checkpoint.eligibility == Deferred =>
          (restored, checkpoint_effect(operation.document_id, checkpoint, true))
        _ => (restored, [])
      }
      (
        {
          ..documents,
          records: replace_record(documents.records, operation.document_id, fn(
            _,
          ) {
            restored
          }),
        },
        decisions,
      )
    }
  }
}
