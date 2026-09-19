///|
fn delete_is_active(phase : DocumentsDeletePhase) -> Bool {
  match phase {
    Unavailable | Available | Failed(_, _) => false
    Waiting(_) | Deleting(_) => true
  }
}

///|
fn remove_record(records : Array[Record], key : Key) -> Array[Record] {
  records.filter(r => r.key() != key)
}

///|
fn issue_delete_record(
  record : Record,
  origin : LocalDocumentOrigin,
  operation : DeleteOperation,
  retained : DocumentsSaveStatus,
) -> (Record, Effect) {
  (
    {
      ..record,
      save: retained,
      persistence: Source(origin, SourceDeletePhase::Deleting(operation)),
    },
    DeleteSource(operation),
  )
}

///|
fn confirm_or_retry_delete(
  documents : State,
  id : Key,
) -> (State, Array[Effect]) {
  guard find_record(documents.records, id) is Some(record) else {
    return (documents, [])
  }
  guard record.persistence is Source(origin, phase) &&
    (
      phase is SourceDeletePhase::Available ||
      phase is SourceDeletePhase::Failed(_, _)
    ) else {
    return (documents, [])
  }
  let request_id = documents.last_delete_request + 1
  let key = record.key()
  let operation = { key, document_id: record.document.id(), request_id, }
  match record.save {
    Saving(_, _) =>
      (
        {
          ..documents,
          last_delete_request: request_id,
          records: replace_record(documents.records, id, r => {
            ..r,
            persistence: Source(origin, SourceDeletePhase::Waiting(operation)),
          }),
        },
        [],
      )
    _ if documents.saved.find(record.document.id()) is None =>
      (
        {
          ..documents,
          last_delete_request: request_id,
          records: remove_record(documents.records, id),
        },
        [],
      )
    _ => {
      let (record, decision) = issue_delete_record(
        record,
        origin,
        operation,
        record.save,
      )
      (
        {
          ..documents,
          last_delete_request: request_id,
          records: replace_record(documents.records, id, _ => record),
        },
        [decision],
      )
    }
  }
}

///|
fn finish_delete(
  documents : State,
  operation : DeleteOperation,
  result : @source_repository.DeleteResult,
) -> (State, Array[Effect]) {
  let key = operation.key
  guard find_record(documents.records, key) is Some(record) else {
    return (documents, [])
  }
  guard record.persistence
    is Source(origin, SourceDeletePhase::Deleting(active)) &&
    active == operation else {
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
        { ..documents, saved, records: remove_record(documents.records, key), },
        [],
      )
    }
    DeleteFailed(failure) => {
      let restored = {
        ..record,
        persistence: Source(
          origin,
          SourceDeletePhase::Failed(operation, failure),
        ),
      }
      let (restored, decisions) = match record.save {
        Waiting(checkpoint) if checkpoint.eligibility ==
          DocumentsCheckpointEligibility::Eligible &&
          !is_composing(record.edit) => begin_save(documents.saved, restored)
        Waiting(checkpoint) => {
          let (checkpoint, decisions) = checkpoint_effect(key, checkpoint, true)
          (
            { ..restored, save: DocumentsSaveStatus::Waiting(checkpoint), },
            decisions,
          )
        }
        _ => (restored, [])
      }
      (
        {
          ..documents,
          records: replace_record(documents.records, key, fn(_) {
            return restored
          }),
        },
        decisions,
      )
    }
  }
}
