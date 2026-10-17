///|
pub fn Key::source(document_id : @source_repository.DocumentId) -> Key {
  Source(document_id)
}

///|
pub fn Key::replica(
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
) -> Key {
  Replica(account, document_id)
}

///|
fn Record::key(self : Self) -> Key {
  match self.persistence {
    Source(_, _) | StartingSync(_, _, _) | Forking(_, _) =>
      Key::source(self.document.id())
    Replica(account, _, _) => Key::replica(account, self.document.id())
  }
}

///|
fn Record::delete_status(self : Self) -> DeleteStatus {
  match self.persistence {
    Source(_, Writable(_, None)) | Replica(_, ReplicaAvailable, _) => Deletable
    Source(_, Writable(_, Some(failure))) => DeleteFailed(failure.cause)
    Source(_, WaitingToDelete(_, _, _) | Deleting(_, _))
    | Replica(_, ReplicaPending, _) => DeletePending
    Replica(_, ReplicaFailed(failure), _) => DeletePersistenceFailed(failure)
    StartingSync(_, _, _) | Forking(_, _) => NotDeletable
  }
}

///|
fn Record::pending_window(self : Self) -> AutosaveWindow? {
  match self.persistence {
    Source(_, Writable(Waiting(window), _))
    | Source(_, Deleting(_, Waiting(window)))
    | StartingSync(_, _, Waiting(window))
    | Replica(_, _, Waiting(window))
    | Forking(_, Waiting(window)) => Some(window)
    Source(_, Writable(Saving(_, pending), _) | WaitingToDelete(_, _, pending)) =>
      pending
    _ => None
  }
}

///|
fn Record::save_failure(self : Self) -> @source_repository.SaveFailure? {
  match self.persistence {
    Source(_, Writable(Failed(failure), _))
    | Source(_, Deleting(_, Failed(failure)))
    | StartingSync(_, _, Failed(failure))
    | Replica(_, _, Failed(failure))
    | Forking(_, Failed(failure)) => Some(failure)
    _ => None
  }
}

///|
fn Record::has_source_write(self : Self) -> Bool {
  match self.persistence {
    Source(_, Writable(Saving(_, _), _) | WaitingToDelete(_, _, _)) => true
    _ => false
  }
}

///|
fn SourceSave::from_autosave(autosave : Autosave) -> SourceSave {
  match autosave {
    Idle => Idle
    Waiting(window) => Waiting(window)
    Failed(failure) => Failed(failure)
  }
}

///|
/// Replace scheduled work without changing the operation that owns the lane.
fn Record::schedule(self : Self, window : AutosaveWindow?) -> Record {
  let autosave : Autosave = match window {
    Some(window) => Waiting(window)
    None => Idle
  }
  let persistence : DocumentPersistence = match self.persistence {
    Source(origin, Writable(Saving(operation, _), failure)) =>
      Source(origin, Writable(Saving(operation, window), failure))
    Source(origin, Writable(_, failure)) =>
      Source(origin, Writable(SourceSave::from_autosave(autosave), failure))
    Source(origin, WaitingToDelete(save, deletion, _)) =>
      Source(origin, WaitingToDelete(save, deletion, window))
    Source(origin, Deleting(deletion, _)) =>
      Source(origin, Deleting(deletion, autosave))
    StartingSync(account, document, _) =>
      StartingSync(account, document, autosave)
    Replica(account, deletion, _) => Replica(account, deletion, autosave)
    Forking(ownership, _) => Forking(ownership, autosave)
  }
  { ..self, persistence, }
}

///|
pub fn Key::lifecycle_key(self : Self) -> String {
  match self {
    Source(document_id) => {
      let value = document_id.value()
      "source/" + value.length().to_string() + "/" + value
    }
    Replica(account, document_id) => {
      let value = account.value()
      let document = document_id.value()
      "replica/" +
      value.length().to_string() +
      "/" +
      value +
      "/" +
      document.length().to_string() +
      "/" +
      document
    }
  }
}

///|
fn replace_record(
  records : Array[Record],
  key : Key,
  update : (Record) -> Record,
) -> Array[Record] {
  records.map(record => {
    if record.key() == key {
      update(record)
    } else {
      record
    }
  })
}

///|
fn find_record(records : Array[Record], key : Key) -> Record? {
  records
  .exact_view()
  .search_by(record => record.key() == key)
  .map(i => records[i])
}

///|
fn prepend_record(records : Array[Record], record : Record) -> Array[Record] {
  [record] + records
}

///|
fn is_composing(edit : Editing) -> Bool {
  match edit {
    ComposingIdle | ComposingWaiting(_) | ComposingReady => true
    Idle | Waiting(_) => false
  }
}

///|
fn begin_save(
  saved : @source_repository.SavedDocuments,
  record : Record,
) -> (Record, ReadOnlyArray[Action]) {
  match record.persistence {
    Source(origin, Writable(Waiting(window), failure)) => {
      let operation : SaveOperation = {
        key: record.key(),
        document: record.document,
        request_id: window.maximum_id,
      }
      (
        {
          ..record,
          persistence: Source(
            origin,
            Writable(Saving(operation, None), failure),
          ),
        },
        [PersistSource(operation)],
      )
    }
    Replica(account, ReplicaAvailable | ReplicaFailed(_), _) =>
      match saved.replica(account, record.document.id()) {
        Some(durable) =>
          (
            { ..record, persistence: Replica(account, ReplicaAvailable, Idle), },
            [SaveReplica({ durable, document: record.document, })],
          )
        None =>
          (
            {
              ..record,
              persistence: Replica(
                account,
                ReplicaAvailable,
                Failed(InvalidSource),
              ),
            },
            [],
          )
      }
    // Eligibility survives ownership transfer. Its completion starts the write.
    StartingSync(_, _, _) => (record, [])
    Forking(ownership, _) =>
      (record, [RetryReplica(ownership.account, ownership.original)])
    Source(
      _,
      Writable(Idle | Failed(_) | Saving(_, _), _)
      | WaitingToDelete(_, _, _)
      | Deleting(_, _)
    )
    | Replica(_, ReplicaPending, _) => (record, [])
  }
}

///|
/// Imports and retries consume a fresh window too: identical text must not
/// make an earlier Source write acknowledgment current again.
fn request_save(
  model : Model,
  record : Record,
) -> (Model, Record, ReadOnlyArray[Action]) {
  let (model, window) = allocate_autosave(model)
  let record = record.schedule(Some({ ..window, eligibility: Eligible, }))
  let (record, effects) = begin_save(model.saved, record)
  (model, record, effects)
}

///|
pub fn Model::Model(saved : @source_repository.SavedDocuments) -> Model {
  let sources = saved
    .all()
    .to_owned()
    .map(document => {
      persistence: Source(Existing, Writable(Idle, None)),
      document,
      version: 0,
      edit: Idle,
      lead_source: Available(document.text()),
    })
  let replicas = saved
    .replicas()
    .filter_map(replica => {
      replica.document().map(document => replica_record(replica, document))
    })
  {
    saved,
    records: sources + replicas,
    visible_account: None,
    last_autosave_id: 0,
    last_working_copy_version: 0,
    last_delete_request: 0,
  }
}

///|
fn replica_record(
  replica : @source_repository.DocumentReplica,
  document : @source_repository.Document,
) -> Record {
  {
    persistence: Replica(replica.account(), ReplicaAvailable, Idle),
    document,
    version: 0,
    edit: Idle,
    lead_source: Available(document.text()),
  }
}

///|
pub fn Model::project_account(
  self : Self,
  account : @source_repository.AccountId,
) -> Self {
  { ..self, visible_account: Some(account), }
}

///|
pub fn Model::open_replica(
  self : Self,
  replica : @source_repository.DocumentReplica,
) -> RemoteOpen {
  let key = Key::replica(replica.account(), replica.document_id())
  guard replica.document() is Some(document) &&
    self.saved.replica(replica.account(), replica.document_id()) ==
    Some(replica) else {
    return Superseded
  }
  let documents = match find_record(self.records, key) {
    Some(record) if record.persistence
      is Replica(account, ReplicaAvailable, Idle) &&
      account == replica.account() &&
      record.document == document &&
      record.edit is Idle => self
    Some(_) => return Superseded
    None => {
      let (documents, version) = allocate_working_copy_version(self)
      {
        ..documents,
        records: documents.records +
        [{ ..replica_record(replica, document), version, }],
      }
    }
  }
  Opened({ documents, key, document, })
}

///|
pub fn ReplicaEdit::durable(self : Self) -> @source_repository.DocumentReplica {
  self.durable
}

///|
pub fn ReplicaEdit::document(self : Self) -> @source_repository.Document {
  self.document
}

///|
pub fn Model::hide_accounts(self : Self) -> Self {
  { ..self, visible_account: None, }
}

///|
fn Model::record_is_visible(self : Self, record : Record) -> Bool {
  match record.persistence {
    Source(_, _) | StartingSync(_, _, _) | Forking(_, _) => true
    Replica(account, _, _) => self.visible_account == Some(account)
  }
}

///|
fn allocate_autosave(documents : Model) -> (Model, AutosaveWindow) {
  let id = documents.last_autosave_id + 1
  (
    { ..documents, last_autosave_id: id, },
    { maximum_id: id, maximum_armed: false, eligibility: Deferred, },
  )
}

///|
fn allocate_working_copy_version(documents : Model) -> (Model, Int) {
  let version = documents.last_working_copy_version + 1
  ({ ..documents, last_working_copy_version: version, }, version)
}

///|
fn autosave_effect(
  window : AutosaveWindow,
  rearm : Bool,
) -> (AutosaveWindow, ReadOnlyArray[Action]) {
  if window.eligibility == Eligible || (!rearm && window.maximum_armed) {
    (window, [])
  } else {
    ({ ..window, maximum_armed: true, }, [ArmMaximum(window.maximum_id)])
  }
}
