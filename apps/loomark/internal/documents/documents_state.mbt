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
/// A key reads as its lifecycle key: its storage kind and the length-prefixed
/// parts that identify it, so no other key reads the same and its text can
/// name it where only text fits, such as an element ID or a URL.
pub impl Show for Key with fn output(self, logger) {
  match self {
    Source(document_id) => {
      let value = document_id.value()
      logger.write_string("source/\{value.length()}/\{value}")
    }
    Replica(account, document_id) => {
      let account = account.value()
      let document = document_id.value()
      logger.write_string(
        "replica/\{account.length()}/\{account}/\{document.length()}/\{document}",
      )
    }
  }
}

///|
pub extend Key with Show::{output, to_string}

///|
/// The key whose text, as `Show` writes it, is `text`; `None` when no key
/// reads that way.
pub fn Key::parse(text : String) -> Key? {
  if text.has_prefix("source/") {
    guard length_prefixed(text.exact_view(start=7).to_owned())
      is Some((document, "")) else {
      return None
    }
    parsed_document_id(document).map(Key::source)
  } else if text.has_prefix("replica/") {
    guard length_prefixed(text.exact_view(start=8).to_owned())
      is Some((account, rest)) &&
      rest.has_prefix("/") &&
      length_prefixed(rest.exact_view(start=1).to_owned())
      is Some((document, "")) else {
      return None
    }
    let account = @source_repository.AccountId::parse(account) catch {
      _ => return None
    }
    parsed_document_id(document).map(id => Key::replica(account, id))
  } else {
    None
  }
}

///|
/// A part written as its length, a slash, and itself, with the text after it.
fn length_prefixed(text : String) -> (String, String)? {
  guard text.find("/") is Some(slash) &&
    slash > 0 &&
    slash <= 9 &&
    text.exact_view(end=slash).iter().all(c => c is ('0'..<='9')) else {
    return None
  }
  let length = text
    .exact_view(end=slash)
    .iter()
    .fold(init=0, (length, c) => length * 10 + (c.to_int() - '0'.to_int()))
  let start = slash + 1
  guard start + length <= text.length() else { return None }
  Some(
    (
      text.exact_view(start~, end=start + length).to_owned(),
      text.exact_view(start=start + length).to_owned(),
    ),
  )
}

///|
fn parsed_document_id(value : String) -> @source_repository.DocumentId? {
  Some(@source_repository.DocumentId::parse(value)) catch {
    _ => None
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
/// Record order carries no meaning; the Document index orders by Change time.
fn add_record(records : Array[Record], record : Record) -> Array[Record] {
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
      | Deleting(_, _),
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
fn allocate_working_copy_version(documents : Model) -> (Model, Int32) {
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
