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
    Source(_, _) | StartingSync(_, _) => Key::source(self.document.id())
    Replica(account, _) => Key::replica(account, self.document.id())
    Forking(_) => Key::source(self.document.id())
  }
}

///|
fn Record::delete_phase(self : Self) -> DocumentsDeletePhase {
  match self.persistence {
    Source(_, SourceDeletePhase::Available) => DocumentsDeletePhase::Available
    Source(_, SourceDeletePhase::Waiting(operation)) => Waiting(operation)
    Source(_, SourceDeletePhase::Deleting(operation)) => Deleting(operation)
    Source(_, SourceDeletePhase::Failed(operation, failure)) =>
      Failed(operation, failure)
    Replica(_, ReplicaAvailable) => DocumentsDeletePhase::Available
    Replica(_, ReplicaPending) => ReplicaPending
    Replica(_, ReplicaFailed(failure)) => ReplicaFailed(failure)
    StartingSync(_, _) | Forking(_) => Unavailable
  }
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
  records.view().search_by(record => record.key() == key).map(i => records[i])
}

///|
fn prepend_record(records : Array[Record], record : Record) -> Array[Record] {
  [record] + records
}

///|
fn is_composing(edit : EditState) -> Bool {
  match edit {
    ComposingIdle | ComposingWaiting(_) | ComposingReady => true
    Idle | Waiting(_) => false
  }
}

///|
fn replace_autosave(
  documents : State,
  document_id : Key,
  replica : AutosaveWindow,
) -> State {
  {
    ..documents,
    records: replace_record(documents.records, document_id, r => {
      let save = match r.save {
        DocumentsSaveStatus::Waiting(_) => DocumentsSaveStatus::Waiting(replica)
        DocumentsSaveStatus::Saving(operation, _) =>
          DocumentsSaveStatus::Saving(operation, Some(replica))
        Saved | Failed(_) => r.save
      }
      { ..r, save, }
    }),
  }
}

///|
fn begin_save(
  saved : @source_repository.SavedDocuments,
  record : Record,
) -> (Record, Array[Action]) {
  match record.persistence {
    Source(_, _) => {
      let operation = { key: record.key(), document: record.document, }
      (
        { ..record, save: Saving(operation, None), },
        [Action::PersistSource(operation)],
      )
    }
    StartingSync(_, _) | Forking(_) => (record, [])
    Replica(account, ReplicaAvailable | ReplicaFailed(_)) =>
      match saved.replica(account, record.document.id()) {
        Some(durable) =>
          (
            // The committed Replica can be older than an active persistence
            // lane. Submit every eligible value; Replication compares it with
            // the causal head and coalesces it when no write is needed.
            {
              ..record,
              persistence: Replica(account, ReplicaAvailable),
              save: Saved,
            },
            [Action::SaveReplica({ durable, document: record.document, })],
          )
        None => ({ ..record, save: Failed(InvalidSource), }, [])
      }
    Replica(_, ReplicaPending) => (record, [])
  }
}

///|
pub fn State::State(saved : @source_repository.SavedDocuments) -> State {
  let sources = saved
    .all()
    .to_owned()
    .map(document => {
      persistence: Source(Existing, SourceDeletePhase::Available),
      document,
      version: 0,
      edit: Idle,
      save: Saved,
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
    persistence: Replica(replica.account(), ReplicaAvailable),
    document,
    version: 0,
    edit: Idle,
    save: Saved,
    lead_source: Available(document.text()),
  }
}

///|
pub fn State::project_account(
  self : Self,
  account : @source_repository.AccountId,
) -> Self {
  { ..self, visible_account: Some(account), }
}

///|
pub fn State::open_replica(
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
    Some(record) if record.persistence is Replica(account, ReplicaAvailable) &&
      account == replica.account() &&
      record.document == document &&
      record.save is DocumentsSaveStatus::Saved &&
      record.edit is EditState::Idle => self
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
pub fn State::hide_accounts(self : Self) -> Self {
  { ..self, visible_account: None, }
}

///|
fn State::record_is_visible(self : Self, record : Record) -> Bool {
  match record.persistence {
    Source(_, _) | StartingSync(_, _) | Forking(_) => true
    Replica(account, _) => self.visible_account == Some(account)
  }
}

///|
fn allocate_autosave(documents : State) -> (State, AutosaveWindow) {
  let id = documents.last_autosave_id + 1
  (
    { ..documents, last_autosave_id: id, },
    {
      maximum_id: id,
      maximum_armed: false,
      eligibility: AutosaveEligibility::Deferred,
    },
  )
}

///|
fn revise_autosave(replica : AutosaveWindow) -> AutosaveWindow {
  { ..replica, eligibility: AutosaveEligibility::Deferred, }
}

///|
fn allocate_working_copy_version(documents : State) -> (State, Int) {
  let version = documents.last_working_copy_version + 1
  ({ ..documents, last_working_copy_version: version, }, version)
}

///|
fn autosave_effect(
  replica : AutosaveWindow,
  rearm : Bool,
) -> (AutosaveWindow, Array[Action]) {
  if replica.eligibility == AutosaveEligibility::Eligible ||
    (!rearm && replica.maximum_armed) {
    (replica, [])
  } else {
    ({ ..replica, maximum_armed: true, }, [ArmMaximum(replica.maximum_id)])
  }
}
