///|
fn acknowledged_document(
  saved : @source_repository.SavedDocuments,
  key : Key,
) -> @source_repository.Document? {
  match key {
    Source(document_id) => saved.find(document_id)
    Replica(account, document_id) =>
      match saved.replica(account, document_id) {
        Some(replica) => replica.document()
        None => None
      }
  }
}

///|
pub fn Model::begin_fork(
  self : Self,
  write : @source_repository.ReplicaWrite,
) -> Model raise ActionError {
  guard write is @source_repository.ReplicaWrite::Fork(replica, recovery) else {
    raise ExpiredAction
  }
  let original = replica.document_id()
  let key = Key::replica(replica.account(), original)
  guard find_record(self.records, key) is Some(record) &&
    record.persistence is Replica(account, ReplicaAvailable, autosave) &&
    account == replica.account() else {
    raise ExpiredAction
  }
  let ownership : ForkOwnership = { account, original, recovery, }
  let transferred = {
    ..record,
    persistence: Forking(ownership, autosave),
    document: recovery.update(record.document.text()),
  }
  {
    ..self,
    records: prepend_record(remove_record(self.records, key), transferred),
  }
}

///|
fn apply_text(
  documents : Model,
  record : Record,
  text : String,
) -> (Model, ReadOnlyArray[Action]) {
  let key = record.key()
  let document = record.document.update(text)
  let lead_source = match record.lead_source {
    Unlisted => LeadSource::Available(text)
    source => source
  }
  // Replica writes compare against the persistence lane, not its older durable snapshot.
  let clean = record.persistence is Source(_, _) &&
    acknowledged_document(documents.saved, key)
    .map(saved => saved.text() == text)
    .unwrap_or(false)
  let (documents, window) = if clean && !record.has_source_write() {
    (documents, None)
  } else {
    match record.pending_window() {
      Some(window) => (documents, Some({ ..window, eligibility: Deferred, }))
      None => {
        let (next, window) = allocate_autosave(documents)
        (next, Some(window))
      }
    }
  }
  let (documents, revision) = allocate_working_copy_version(documents)
  let needs_lead = match lead_source {
    Available(source) => source != text
    Unlisted => true
  }
  let pending = needs_lead ||
    window.map(window => window.eligibility == Deferred).unwrap_or(false)
  let edit : Editing = if is_composing(record.edit) {
    if pending {
      ComposingWaiting(revision)
    } else {
      ComposingIdle
    }
  } else if pending {
    Waiting(revision)
  } else {
    Idle
  }
  let record = {
    ..record.schedule(window),
    document,
    version: revision,
    edit,
    lead_source,
  }
  let (record, effects) = match window {
    Some(window) if !is_composing(edit) => {
      let (window, effects) = autosave_effect(window, false)
      (record.schedule(Some(window)), effects)
    }
    _ => (record, [])
  }
  (
    {
      ..documents,
      records: prepend_record(remove_record(documents.records, key), record),
    },
    effects,
  )
}

///|
fn mark_eligible(
  saved : @source_repository.SavedDocuments,
  record : Record,
  window : AutosaveWindow,
) -> (Record, ReadOnlyArray[Action]) {
  let record = record.schedule(Some({ ..window, eligibility: Eligible, }))
  if is_composing(record.edit) || record.has_source_write() {
    (record, [])
  } else {
    begin_save(saved, record)
  }
}

///|
fn accept_pending(
  saved : @source_repository.SavedDocuments,
  record : Record,
) -> (Record, ReadOnlyArray[Action]) {
  let record = {
    ..record,
    edit: Editing::Idle,
    lead_source: Available(record.document.text()),
  }
  match record.pending_window() {
    Some(window) => mark_eligible(saved, record, window)
    None => (record, [])
  }
}

///|
fn finish_composition(
  saved : @source_repository.SavedDocuments,
  record : Record,
) -> (Record, ReadOnlyArray[Action]) {
  // Record the end of composition without restarting work owned by deletion.
  // A failed deletion will restore the pending autosave and its subscription.
  if record.delete_status() == DeletePending {
    return (record, [])
  }
  match record.pending_window() {
    Some(window) if window.eligibility == Eligible && !record.has_source_write() =>
      begin_save(saved, record)
    Some(window) => {
      let (window, effects) = autosave_effect(window, true)
      (record.schedule(Some(window)), effects)
    }
    None => (record, [])
  }
}

///|
fn flush_visibility(
  saved : @source_repository.SavedDocuments,
  record : Record,
) -> (Record, ReadOnlyArray[Action]) {
  if record.delete_status() == DeletePending {
    return (record, [])
  }
  match record.pending_window() {
    Some(window) => mark_eligible(saved, record, window)
    None => (record, [])
  }
}

///|
priv enum SaveCompletion {
  Continue(Record, LocalDocumentOrigin, AutosaveWindow?, DeletionFailure?)
  Delete(Record, LocalDocumentOrigin, DeleteOperation, AutosaveWindow?)
}

///|
fn current_save(
  documents : Model,
  operation : SaveOperation,
) -> SaveCompletion? {
  guard find_record(documents.records, operation.key) is Some(record) else {
    return None
  }
  match record.persistence {
    Source(origin, Writable(Saving(active, pending), failure)) if active ==
      operation => Some(Continue(record, origin, pending, failure))
    Source(origin, WaitingToDelete(active, deletion, pending)) if active ==
      operation => Some(Delete(record, origin, deletion, pending))
    _ => None
  }
}

///|
fn resume_autosave(
  saved : @source_repository.SavedDocuments,
  record : Record,
) -> (Record, ReadOnlyArray[Action]) {
  match record.pending_window() {
    Some(window) if window.eligibility == Eligible && !is_composing(record.edit) =>
      begin_save(saved, record)
    _ => (record, [])
  }
}

///|
fn save_succeeded(
  documents : Model,
  operation : SaveOperation,
  document : @source_repository.Document,
) -> Update raise UpdateError {
  guard current_save(documents, operation) is Some(completion) else {
    return Superseded
  }
  guard document == operation.document else {
    raise DocumentMismatch(operation.key)
  }
  guard documents.saved.apply(
      @source_repository.RepositoryChange::Stored(document),
    )
    is Some(saved) else {
    raise InvalidAcknowledgment(operation.key)
  }
  let (record, effects) = match completion {
    Continue(record, _, pending, failure) => {
      let autosave : Autosave = if record.document == document {
        Idle
      } else {
        match pending {
          Some(window) => Waiting(window)
          None => Idle
        }
      }
      resume_autosave(saved, {
        ..record,
        persistence: Source(
          Existing,
          Writable(SourceSave::from_autosave(autosave), failure),
        ),
      })
    }
    Delete(record, _, deletion, pending) => {
      let restoration : Autosave = if record.document == document {
        Idle
      } else {
        match pending {
          Some(window) => Waiting(window)
          None => Idle
        }
      }
      issue_delete(record, Existing, deletion, restoration)
    }
  }
  Applied(
    transition(
      {
        ..documents,
        saved,
        records: replace_record(documents.records, operation.key, _ => record),
      },
      effects,
    ),
  )
}

///|
fn save_failed(
  documents : Model,
  operation : SaveOperation,
  failure : @source_repository.SaveFailure,
) -> Update {
  guard current_save(documents, operation) is Some(completion) else {
    return Superseded
  }
  let (record, effects) = match completion {
    Continue(record, origin, pending, deletion) => {
      let autosave : Autosave = if documents.saved.find(record.document.id()) ==
        Some(record.document) {
        Idle
      } else {
        match pending {
          Some(window) => Waiting(window)
          None => Failed(failure)
        }
      }
      resume_autosave(documents.saved, {
        ..record,
        persistence: Source(
          origin,
          Writable(SourceSave::from_autosave(autosave), deletion),
        ),
      })
    }
    Delete(record, origin, deletion, pending) => {
      if documents.saved.find(record.document.id()) is None {
        return Applied(
          transition(
            {
              ..documents,
              records: remove_record(documents.records, operation.key),
            },
            [],
          ),
        )
      }
      let restoration : Autosave = if documents.saved.find(record.document.id()) ==
        Some(record.document) {
        Idle
      } else {
        match pending {
          Some(window) => Waiting(window)
          None => Failed(failure)
        }
      }
      issue_delete(record, origin, deletion, restoration)
    }
  }
  Applied(
    transition(
      {
        ..documents,
        records: replace_record(documents.records, operation.key, _ => record),
      },
      effects,
    ),
  )
}

///|
fn refresh_replica_record(
  documents : Model,
  previous : @source_repository.DocumentReplica?,
  replica : @source_repository.DocumentReplica,
  mounted : Key?,
) -> Model {
  let key = Key::replica(replica.account(), replica.document_id())
  guard replica.document() is Some(document) else {
    return { ..documents, records: remove_record(documents.records, key), }
  }
  guard previous is Some(previous) else { return documents }
  match find_record(documents.records, key) {
    None if previous.document() is None => {
      let (documents, version) = allocate_working_copy_version(documents)
      {
        ..documents,
        records: prepend_record(documents.records, {
          ..replica_record(replica, document),
          version,
        }),
      }
    }
    Some(record) => {
      guard record.persistence is Replica(account, deletion, autosave) &&
        account == replica.account() else {
        return documents
      }
      let restore = previous.document() is None || deletion is ReplicaFailed(_)
      let refresh = mounted != Some(key) &&
        previous.document() == Some(record.document) &&
        autosave is Idle &&
        record.edit is Idle
      if !restore && !refresh {
        return documents
      }
      let (documents, version) = allocate_working_copy_version(documents)
      {
        ..documents,
        records: replace_record(documents.records, key, _ => {
          ..replica_record(replica, document),
          version,
        }),
      }
    }
    None => documents
  }
}

///|
fn fail_replica_deletion(
  documents : Model,
  write : @source_repository.ReplicaWrite,
  failure : @source_repository.ReplicaFailure,
) -> Update raise UpdateError {
  let replica = write.replica()
  let key = Key::replica(replica.account(), replica.document_id())
  guard find_record(documents.records, key) is Some(record) &&
    record.persistence is Replica(account, ReplicaPending, autosave) else {
    return Superseded
  }
  guard write is @source_repository.ReplicaWrite::Remove(_) ||
    replica.is_deleting() ||
    replica.is_deleted() else {
    raise InvalidAcknowledgment(key)
  }
  let record = {
    ..record,
    persistence: Replica(account, ReplicaFailed(failure), autosave),
  }
  Applied(
    transition(
      {
        ..documents,
        records: replace_record(documents.records, key, _ => record),
      },
      [],
    ),
  )
}

///|
fn advance_replica(
  documents : Model,
  write : @source_repository.ReplicaWrite,
) -> Update raise UpdateError {
  let replica = write.replica()
  let saved = documents.saved.apply_replica_write(write) catch {
    _ =>
      raise InvalidAcknowledgment(
        Key::replica(replica.account(), replica.document_id()),
      )
  }
  Applied(transition({ ..documents, saved, }, []))
}

///|
fn settle_replica(
  documents : Model,
  write : @source_repository.ReplicaWrite,
  mounted : Key?,
) -> Update raise UpdateError {
  let replica = write.replica()
  let previous = documents.saved.replica(
    replica.account(),
    replica.document_id(),
  )
  // A fork completion must still own its recovery working copy before it can
  // acknowledge either side of the atomic write.
  let recovery_record = match write {
    Fork(_, recovery) => {
      guard find_record(documents.records, Key::source(recovery.id()))
        is Some(record) &&
        record.persistence is Forking(ownership, autosave) &&
        ownership.account == replica.account() &&
        ownership.original == replica.document_id() &&
        ownership.recovery == recovery else {
        return Superseded
      }
      Some((record, recovery, autosave))
    }
    _ => None
  }
  let saved = documents.saved.apply_replica_write(write) catch {
    _ =>
      raise InvalidAcknowledgment(
        Key::replica(replica.account(), replica.document_id()),
      )
  }
  match write {
    Remove(_) =>
      Applied(
        transition(
          {
            ..documents,
            saved,
            records: remove_record(
              documents.records,
              Key::replica(replica.account(), replica.document_id()),
            ),
          },
          [],
        ),
      )
    _ =>
      match recovery_record {
        None =>
          Applied(
            transition(
              refresh_replica_record(
                { ..documents, saved, },
                previous,
                replica,
                mounted,
              ),
              [],
            ),
          )
        Some((record, recovery, autosave)) => {
          let autosave = if record.document == recovery {
            Autosave::Idle
          } else {
            autosave
          }
          let recovered = {
            ..record,
            persistence: Source(
              Existing,
              Writable(SourceSave::from_autosave(autosave), None),
            ),
          }
          let (recovered, effects) = resume_autosave(saved, recovered)
          let records = prepend_record(
            remove_record(documents.records, record.key()),
            recovered,
          )
          let documents = { ..documents, saved, records, }
          match replica.document() {
            Some(document) => {
              let (documents, version) = allocate_working_copy_version(
                documents,
              )
              Applied(
                transition(
                  {
                    ..documents,
                    records: prepend_record(documents.records, {
                      ..replica_record(replica, document),
                      version,
                    }),
                  },
                  effects,
                ),
              )
            }
            None => Applied(transition(documents, effects))
          }
        }
      }
  }
}

///|
pub fn Model::start_sync(
  documents : Model,
  action : StartSync,
) -> (Model, Array[Action]) raise ActionError {
  guard documents.sync_start(action.key, action.account) == Ready(action) else {
    raise ExpiredAction
  }
  (
    {
      ..documents,
      records: replace_record(documents.records, action.key, current => {
        ..current,
        persistence: StartingSync(action.account, action.document, Idle),
      }),
    },
    [
      StoreReplica(
        @source_repository.DocumentReplica(action.account, action.document).promote_source(),
      ),
    ],
  )
}

///|
fn complete_sync_start(
  documents : Model,
  write : @source_repository.ReplicaWrite,
  failure : @source_repository.ReplicaFailure?,
) -> Update raise UpdateError {
  let replica = write.replica()
  let key = Key::source(replica.document_id())
  guard find_record(documents.records, key) is Some(record) &&
    record.persistence is StartingSync(account, source, autosave) &&
    account == replica.account() else {
    return Superseded
  }
  guard write is @source_repository.ReplicaWrite::PromoteSource(_) &&
    replica.document() == Some(source) else {
    raise DocumentMismatch(key)
  }
  let (saved, persistence) = match failure {
    None => {
      guard documents.saved.apply_sync_start(replica) is Some(saved) else {
        raise InvalidAcknowledgment(key)
      }
      let autosave = if record.document == source {
        Autosave::Idle
      } else {
        autosave
      }
      (saved, DocumentPersistence::Replica(account, ReplicaAvailable, autosave))
    }
    Some(_) =>
      (
        documents.saved,
        DocumentPersistence::Source(
          Existing,
          Writable(SourceSave::from_autosave(autosave), None),
        ),
      )
  }
  let (record, effects) = resume_autosave(saved, { ..record, persistence, })
  Applied(
    transition(
      {
        ..documents,
        saved,
        records: prepend_record(remove_record(documents.records, key), record),
      },
      effects,
    ),
  )
}
