///|
fn delete_is_active(phase : DocumentsDeletePhase) -> Bool {
  match phase {
    Unavailable | Available | Failed(_, _) | ReplicaFailed(_) => false
    Waiting(_) | Deleting(_) | ReplicaPending => true
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
) -> (Record, Action) {
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
fn confirm_source_delete(
  documents : State,
  id : Key,
  record : Record,
  origin : LocalDocumentOrigin,
  phase : SourceDeletePhase,
) -> (State, Array[Action]) {
  guard phase is SourceDeletePhase::Available ||
    phase is SourceDeletePhase::Failed(_, _) else {
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
fn confirm_replica_delete(
  documents : State,
  id : Key,
  record : Record,
  account : @source_repository.AccountId,
  phase : ReplicaDeletePhase,
) -> (State, Array[Action]) {
  match phase {
    ReplicaAvailable =>
      match documents.saved.replica(account, record.document.id()) {
        Some(durable) =>
          (
            {
              ..documents,
              records: replace_record(documents.records, id, current => {
                ..current,
                persistence: Replica(account, ReplicaPending),
              }),
            },
            [DeleteReplica({ durable, document: record.document, })],
          )
        None => (documents, [])
      }
    ReplicaFailed(_) =>
      (
        {
          ..documents,
          records: replace_record(documents.records, id, current => {
            ..current,
            persistence: Replica(account, ReplicaPending),
          }),
        },
        [RetryReplica(account, record.document.id())],
      )
    ReplicaPending => (documents, [])
  }
}

///|
fn confirm_or_retry_delete(
  documents : State,
  id : Key,
) -> (State, Array[Action]) {
  guard find_record(documents.records, id) is Some(record) else {
    return (documents, [])
  }
  match record.persistence {
    Source(origin, phase) =>
      confirm_source_delete(documents, id, record, origin, phase)
    Replica(account, phase) =>
      confirm_replica_delete(documents, id, record, account, phase)
    StartingSync(_, _) | Forking(_) => (documents, [])
  }
}

///|
fn finish_delete(
  documents : State,
  operation : DeleteOperation,
  result : @source_repository.DeleteResult,
) -> (State, Array[Action]) {
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
        Waiting(replica) if replica.eligibility == AutosaveEligibility::Eligible &&
          !is_composing(record.edit) => begin_save(documents.saved, restored)
        Waiting(replica) => {
          let (replica, decisions) = autosave_effect(replica, true)
          (
            { ..restored, save: DocumentsSaveStatus::Waiting(replica), },
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
