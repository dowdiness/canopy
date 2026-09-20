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
    Replica(account) => Key::replica(account, self.document.id())
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
    StartingSync(_, _) | Replica(_) => Unavailable
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
) -> (Record, Array[Effect]) {
  match record.persistence {
    Source(_, _) => {
      let operation = { key: record.key(), document: record.document, }
      (
        { ..record, save: Saving(operation, None), },
        [Effect::PersistSource(operation)],
      )
    }
    StartingSync(_, _) => (record, [])
    Replica(account) =>
      match saved.replica(account, record.document.id()) {
        Some(_) =>
          (
            // The committed Replica can be older than an active persistence
            // lane. Submit every eligible value; Replication compares it with
            // the causal head and coalesces it when no write is needed.
            { ..record, save: Saved, },
            [Effect::ReplicaEligible(account, record.document)],
          )
        None => ({ ..record, save: Failed(InvalidSource), }, [])
      }
  }
}

///|
pub fn State::State(saved : @source_repository.SavedDocuments) -> State {
  let records = saved
    .all()
    .to_owned()
    .map(document => {
      persistence: Source(Existing, SourceDeletePhase::Available),
      document,
      edit: Idle,
      save: Saved,
      lead_source: Available(document.text()),
    })
  {
    saved,
    records,
    visible_account: None,
    last_autosave_id: 0,
    last_pending_edit_revision: 0,
    last_delete_request: 0,
  }
}

///|
fn replica_record(replica : @source_repository.DocumentReplica) -> Record {
  let document = replica.document()
  {
    persistence: Replica(replica.account()),
    document,
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
  let records = self.saved
    .replicas_for(account)
    .fold(init=self.records, (records, replica) => {
      let key = Key::replica(account, replica.document().id())
      if find_record(records, key) is Some(_) {
        records
      } else {
        records + [replica_record(replica)]
      }
    })
  { ..self, records, visible_account: Some(account), }
}

///|
pub fn State::admit_replica(
  self : Self,
  replica : @source_repository.DocumentReplica,
) -> Self {
  let key = Key::replica(replica.account(), replica.document().id())
  guard find_record(self.records, key) is None else { return self }
  { ..self, records: self.records + [replica_record(replica)], }
}

///|
pub fn State::hide_accounts(self : Self) -> Self {
  { ..self, visible_account: None, }
}

///|
fn State::record_is_visible(self : Self, record : Record) -> Bool {
  match record.persistence {
    Source(_, _) | StartingSync(_, _) => true
    Replica(account) => self.visible_account == Some(account)
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
fn next_pending_edit(documents : State) -> (State, Int) {
  let revision = documents.last_pending_edit_revision + 1
  ({ ..documents, last_pending_edit_revision: revision, }, revision)
}

///|
fn autosave_effect(
  replica : AutosaveWindow,
  rearm : Bool,
) -> (AutosaveWindow, Array[Effect]) {
  if replica.eligibility == AutosaveEligibility::Eligible ||
    (!rearm && replica.maximum_armed) {
    (replica, [])
  } else {
    ({ ..replica, maximum_armed: true, }, [ArmMaximum(replica.maximum_id)])
  }
}
