///|
fn remove_record(records : Array[Record], key : Key) -> Array[Record] {
  records.filter(record => record.key() != key)
}

///|
fn issue_delete(
  record : Record,
  origin : LocalDocumentOrigin,
  operation : DeleteOperation,
  restoration : Autosave,
) -> (Record, ReadOnlyArray[Action]) {
  (
    { ..record, persistence: Source(origin, Deleting(operation, restoration)), },
    [DeleteSource(operation)],
  )
}

///|
pub fn Model::delete(self : Self, key : Key) -> Delete raise DeleteError {
  guard find_record(self.records, key) is Some(record) else {
    raise DocumentMissing(key)
  }
  match record.persistence {
    StartingSync(_, _, _) | Forking(_, _) =>
      raise OwnershipTransferInProgress(key)
    Source(_, WaitingToDelete(_, _, _) | Deleting(_, _))
    | Replica(_, ReplicaPending, _) => AlreadyPending
    Source(origin, Writable(save, _)) => {
      let operation : DeleteOperation = {
        key,
        document_id: record.document.id(),
        request_id: self.last_delete_request + 1,
      }
      let model = { ..self, last_delete_request: operation.request_id, }
      let restoration : Autosave = match save {
        Saving(active, pending) => {
          let record = {
            ..record,
            persistence: Source(
              origin,
              WaitingToDelete(active, operation, pending),
            ),
          }
          return Accepted(
            transition(
              {
                ..model,
                records: replace_record(model.records, key, _ => record),
              },
              [],
            ),
          )
        }
        Idle => Idle
        Waiting(window) => Waiting(window)
        Failed(failure) => Failed(failure)
      }
      if model.saved.find(record.document.id()) is None {
        return Accepted(
          transition({ ..model, records: remove_record(model.records, key), }, []),
        )
      }
      let (record, effects) = issue_delete(
        record, origin, operation, restoration,
      )
      Accepted(
        transition(
          { ..model, records: replace_record(model.records, key, _ => record), },
          effects,
        ),
      )
    }
    Replica(account, deletion, autosave) => {
      guard self.saved.replica(account, record.document.id()) is Some(durable) else {
        raise ReplicaMissing(key)
      }
      let effects : ReadOnlyArray[Action] = match deletion {
        ReplicaFailed(_) => [RetryReplica(account, record.document.id())]
        ReplicaAvailable =>
          [DeleteReplica({ durable, document: record.document, })]
        ReplicaPending => []
      }
      let record = {
        ..record,
        persistence: Replica(account, ReplicaPending, autosave),
      }
      Accepted(
        transition(
          { ..self, records: replace_record(self.records, key, _ => record), },
          effects,
        ),
      )
    }
  }
}

///|
fn delete_succeeded(
  model : Model,
  operation : DeleteOperation,
  document_id : @source_repository.DocumentId,
) -> Update raise UpdateError {
  guard find_record(model.records, operation.key) is Some(record) &&
    record.persistence is Source(_, Deleting(active, _)) &&
    active == operation else {
    return Superseded
  }
  guard document_id == operation.document_id else {
    raise DocumentMismatch(operation.key)
  }
  guard model.saved.apply(
      @source_repository.RepositoryChange::Deleted(document_id),
    )
    is Some(saved) else {
    raise InvalidAcknowledgment(operation.key)
  }
  Applied(
    transition(
      { ..model, saved, records: remove_record(model.records, operation.key), },
      [],
    ),
  )
}

///|
fn delete_failed(
  model : Model,
  operation : DeleteOperation,
  failure : @source_repository.DeleteFailure,
) -> Update {
  guard find_record(model.records, operation.key) is Some(record) &&
    record.persistence is Source(origin, Deleting(active, restoration)) &&
    active == operation else {
    return Superseded
  }
  let record = {
    ..record,
    persistence: Source(
      origin,
      Writable(
        SourceSave::from_autosave(restoration),
        Some({ operation, cause: failure, }),
      ),
    ),
  }
  let (record, effects) = match restoration {
    Waiting(window) if window.eligibility == Eligible &&
      !is_composing(record.edit) => begin_save(model.saved, record)
    Waiting(window) => {
      let (window, effects) = autosave_effect(window, true)
      (record.schedule(Some(window)), effects)
    }
    Idle | Failed(_) => (record, [])
  }
  Applied(
    transition(
      {
        ..model,
        records: replace_record(model.records, operation.key, _ => record),
      },
      effects,
    ),
  )
}
