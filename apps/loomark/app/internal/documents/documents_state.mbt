///|
pub fn Key::source(document_id : @source_repository.DocumentId) -> Key {
  Source(document_id)
}

///|
pub fn Key::checkpoint(
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
) -> Key {
  Checkpoint(account, document_id)
}

///|
fn Record::key(self : Self) -> Key {
  match self.persistence {
    Source(_, _) => Key::source(self.document.id())
    Checkpoint(account) => Key::checkpoint(account, self.document.id())
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
    Checkpoint(_) => Unavailable
  }
}

///|
pub fn Key::lifecycle_key(self : Self) -> String {
  match self {
    Source(document_id) => {
      let value = document_id.value()
      "source/" + value.length().to_string() + "/" + value
    }
    Checkpoint(account, document_id) => {
      let value = account.value()
      let document = document_id.value()
      "checkpoint/" +
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
fn replace_checkpoint(
  documents : State,
  document_id : Key,
  checkpoint : DocumentsCheckpoint,
) -> State {
  {
    ..documents,
    records: replace_record(documents.records, document_id, r => {
      let save = match r.save {
        DocumentsSaveStatus::Waiting(_) =>
          DocumentsSaveStatus::Waiting(checkpoint)
        DocumentsSaveStatus::Saving(operation, _) =>
          DocumentsSaveStatus::Saving(operation, Some(checkpoint))
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
  let key = record.key()
  let operation = { key, document: record.document, }
  match record.persistence {
    Source(_, _) =>
      (
        { ..record, save: Saving(operation, None), },
        [Effect::PersistSource(operation)],
      )
    Checkpoint(account) =>
      match saved.checkpoint(account, record.document.id()) {
        Some(checkpoint) =>
          match checkpoint.edit(record.document.text()) {
            Some(write) =>
              (
                { ..record, save: Saving(operation, None), },
                [Effect::PersistCheckpoint(write)],
              )
            None => ({ ..record, save: Saved, }, [])
          }
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
    last_checkpoint_id: 0,
    last_pending_edit_revision: 0,
    last_delete_request: 0,
  }
}

///|
fn checkpoint_record(checkpoint : @source_repository.SyncCheckpoint) -> Record {
  let document = checkpoint.document()
  {
    persistence: Checkpoint(checkpoint.account()),
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
    .checkpoints_for(account)
    .fold(init=self.records, (records, checkpoint) => {
      let key = Key::checkpoint(account, checkpoint.document().id())
      if find_record(records, key) is Some(_) {
        records
      } else {
        records + [checkpoint_record(checkpoint)]
      }
    })
  { ..self, records, visible_account: Some(account), }
}

///|
pub fn State::hide_accounts(self : Self) -> Self {
  { ..self, visible_account: None, }
}

///|
fn State::record_is_visible(self : Self, record : Record) -> Bool {
  match record.persistence {
    Source(_, _) => true
    Checkpoint(account) => self.visible_account == Some(account)
  }
}

///|
fn allocate_checkpoint(documents : State) -> (State, DocumentsCheckpoint) {
  let id = documents.last_checkpoint_id + 1
  (
    { ..documents, last_checkpoint_id: id, },
    {
      maximum_id: id,
      maximum_armed: false,
      eligibility: DocumentsCheckpointEligibility::Deferred,
    },
  )
}

///|
fn revise_checkpoint(checkpoint : DocumentsCheckpoint) -> DocumentsCheckpoint {
  { ..checkpoint, eligibility: DocumentsCheckpointEligibility::Deferred, }
}

///|
fn next_pending_edit(documents : State) -> (State, Int) {
  let revision = documents.last_pending_edit_revision + 1
  ({ ..documents, last_pending_edit_revision: revision, }, revision)
}

///|
fn checkpoint_effect(
  document_id : Key,
  checkpoint : DocumentsCheckpoint,
  rearm : Bool,
) -> (DocumentsCheckpoint, Array[Effect]) {
  if checkpoint.eligibility == DocumentsCheckpointEligibility::Eligible ||
    (!rearm && checkpoint.maximum_armed) {
    (checkpoint, [])
  } else {
    (
      { ..checkpoint, maximum_armed: true, },
      [ArmMaximum(document_id, checkpoint.maximum_id)],
    )
  }
}
