///|
fn delete_is_active(phase : DocumentsDeletePhase) -> Bool {
  match phase {
    Available | Failed(_, _) => false
    Waiting(_) | Deleting(_) | Observing(_) | Unknown(_) => true
  }
}

///|
fn remove_record(
  records : Array[DocumentRecord],
  id : String,
) -> Array[DocumentRecord] {
  records.filter(r => r.document.id() != id)
}

///|
fn issue_delete(
  documents : Documents,
  operation : DeleteOperation,
  retained : DocumentsSaveStatus,
) -> (Documents, Array[DocumentsDecision]) {
  (
    {
      ..documents,
      records: replace_record(documents.records, operation.document_id, r => {
        ..r,
        save: retained,
        delete: Deleting(operation),
      }),
    },
    [DeleteDocument(operation), ArmDeleteWatchdog(operation)],
  )
}

///|
fn begin_delete(
  documents : Documents,
  id : String,
  retained : DocumentsSaveStatus,
) -> (Documents, Array[DocumentsDecision]) {
  let request_id = documents.last_delete_request + 1
  issue_delete(
    { ..documents, last_delete_request: request_id },
    { document_id: id, request_id },
    retained,
  )
}

///|
fn confirm_or_retry_delete(
  documents : Documents,
  id : String,
) -> (Documents, Array[DocumentsDecision]) {
  guard find_record(documents.records, id) is Some(record) else {
    return (documents, [])
  }
  let request_id = documents.last_delete_request + 1
  let operation = { document_id: id, request_id }
  match record.save {
    Saving(_, _) =>
      (
        {
          ..documents,
          last_delete_request: request_id,
          records: replace_record(documents.records, id, r => {
            ..r,
            delete: Waiting(operation),
          }),
        },
        [],
      )
    _ if record.origin == EphemeralNew =>
      (
        {
          ..documents,
          last_delete_request: request_id,
          records: remove_record(documents.records, id),
        },
        [],
      )
    _ => begin_delete(documents, id, record.save)
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
    Deleting(x) | Observing(x) | Unknown(x) | Failed(x, _) => x == operation
    _ => false
  }) else {
    return (documents, [])
  }
  match result {
    Deleted(id) => {
      guard id == operation.document_id else { return (documents, []) }
      guard documents.saved.apply(
          @source_repository.RepositoryChange::Deleted(id),
        )
        is Some(saved) else {
        return (documents, [])
      }
      (
        { ..documents, saved, records: remove_record(documents.records, id) },
        [],
      )
    }
    DeleteFailed(failure) => {
      let restored = { ..record, delete: Failed(operation, failure) }
      let (restored, decisions) = match record.save {
        Waiting(checkpoint) if checkpoint.eligibility ==
          DocumentsCheckpointEligibility::Eligible &&
          !record.composing => begin_save(restored)
        Waiting(checkpoint) =>
          (restored, checkpoint_effect(operation.document_id, checkpoint, true))
        _ => (restored, [])
      }
      (
        {
          ..documents,
          records: replace_record(documents.records, operation.document_id, fn(
            _,
          ) {
            return restored
          }),
        },
        decisions,
      )
    }
  }
}
