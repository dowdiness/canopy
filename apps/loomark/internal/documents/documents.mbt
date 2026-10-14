///|
pub fn Model::document(self : Self, key : Key) -> @source_repository.Document? {
  find_record(self.records, key).map(record => record.document)
}

///|
pub fn OpenedDocument::documents(self : Self) -> Model {
  self.documents
}

///|
pub fn OpenedDocument::key(self : Self) -> Key {
  self.key
}

///|
pub fn OpenedDocument::document(self : Self) -> @source_repository.Document {
  self.document
}

///|
pub fn Model::resume_hint(
  self : Self,
  key : Key,
) -> @source_repository.EditingDocumentHint? {
  match find_record(self.records, key) {
    Some(record) =>
      match record.persistence {
        Source(_, _) | StartingSync(_, _, _) =>
          self.saved.editing_document_hint(record.document.id())
        Replica(_, _, _) | Forking(_, _) => None
      }
    None => None
  }
}

///|
pub fn Model::is_composing(self : Self, key : Key) -> Bool {
  find_record(self.records, key)
  .map(record => is_composing(record.edit))
  .unwrap_or(false)
}

///|
pub fn Model::sync_start(
  self : Self,
  key : Key,
  account : @source_repository.AccountId,
) -> SyncStart {
  match find_record(self.records, key) {
    Some(record) if record.persistence is StartingSync(owner, _, _) &&
      owner == account => Starting
    Some(record) if record.persistence is Source(Existing, Writable(Idle, None)) &&
      record.edit is Idle &&
      self.saved.find(record.document.id()) == Some(record.document) &&
      self.saved.replica(account, record.document.id()) is None =>
      Ready({ key, account, document: record.document, })
    _ => Unavailable
  }
}

///|
/// A remote action exists only while the working copy and observed head still
/// match the durable Replica from which that action was projected.
pub fn Model::remote_state(
  self : Self,
  replica : @source_repository.DocumentReplica,
  catalog_head : @source_repository.RemoteHead?,
) -> RemoteState {
  let key = Key::replica(replica.account(), replica.document_id())
  guard find_record(self.records, key) is Some(record) &&
    replica.live() is Some(live) else {
    return Unavailable
  }
  let knowledge = replica.remote_knowledge(catalog_head)
  let relation = live.relation(record.document.text(), knowledge)
  let action = if record.persistence is Replica(account, ReplicaAvailable, Idle) &&
    account == replica.account() &&
    self.visible_account == Some(account) &&
    replica.document() == Some(record.document) &&
    record.edit is Idle &&
    self.saved.replica(account, replica.document_id()) == Some(replica) &&
    replica.remote_update() is Some(update) &&
    knowledge.head() == Some(update.head()) {
    Some({ key, version: record.version, update, })
  } else {
    None
  }
  match (relation, action) {
    (@source_repository.Relation::RemoteAhead, Some(action)) =>
      UpdateAvailable(action)
    (DeletedRemotely, Some(action)) => DeletionAvailable(action)
    (Current, _) => Current
    (LocalAhead, _) => LocalAhead
    (RemoteAhead, _) => RemoteAhead
    (Concurrent, _) => Concurrent
    (Diverged, _) => Diverged
    (DeletedRemotely, _) => DeletedRemotely
    (Unavailable, _) => Unavailable
  }
}

///|
pub fn Model::accept_remote(
  self : Self,
  replica : @source_repository.DocumentReplica,
  catalog_head : @source_repository.RemoteHead?,
  action : AcceptRemote,
) -> RemoteAcceptance raise ActionError {
  let current = match self.remote_state(replica, catalog_head) {
    UpdateAvailable(current) | DeletionAvailable(current) => current
    _ => raise ExpiredAction
  }
  guard current == action else { raise ExpiredAction }
  let write = action.update.accept()
  let accepted = write.replica()
  let (self, version) = allocate_working_copy_version(self)
  match action.update.remote() {
    @source_repository.RemoteDocument::Present(_, _) => {
      guard accepted.document() is Some(document) else { raise ExpiredAction }
      let records = replace_record(self.records, action.key, _ => {
        document,
        version,
        persistence: Replica(replica.account(), ReplicaAvailable, Idle),
        edit: Idle,
        lead_source: Available(document.text()),
      })
      Opened({ ..self, records, }, document, write)
    }
    Deleted(_) =>
      Removed(
        { ..self, records: remove_record(self.records, action.key), },
        write,
      )
    Missing => raise ExpiredAction
  }
}

///|
pub fn StartSync::account(self : Self) -> @source_repository.AccountId {
  self.account
}

///|
pub fn StartSync::document_id(self : Self) -> @source_repository.DocumentId {
  self.document.id()
}

///|
pub fn Model::fallback_document(self : Self, excluding : Key) -> Key? {
  self.records
  .exact_view()
  .search_by(record => {
    record.key() != excluding &&
    self.record_is_visible(record) &&
    record.delete_status() != DeletePending &&
    !(record.persistence is Source(EphemeralNew, _))
  })
  .map(index => self.records[index].key())
}

///|
pub fn Model::snapshot(self : Self) -> @source_repository.SavedDocuments {
  self.saved
}

///|
pub fn Model::text(self : Self, key : Key) -> String? {
  self.document(key).map(document => document.text())
}

///|
pub fn Model::is_ephemeral_new(self : Self, key : Key) -> Bool {
  find_record(self.records, key)
  .map(record => record.persistence is Source(EphemeralNew, _))
  .unwrap_or(false)
}

///|
fn Model::record_save_status(self : Self, record : Record) -> SaveStatus {
  if record.has_source_write() || record.pending_window() is Some(_) {
    return Unsaved
  }
  if record.save_failure() is Some(failure) {
    return SaveFailed(failure)
  }
  match record.persistence {
    Forking(_, _) => Unsaved
    Source(EphemeralNew, _) => Clean
    Source(_, _) | StartingSync(_, _, _) =>
      if self.saved.find(record.document.id()) == Some(record.document) {
        Clean
      } else {
        Unsaved
      }
    Replica(account, _, _) =>
      if self.saved
        .replica(account, record.document.id())
        .map(replica => replica.document() == Some(record.document))
        .unwrap_or(false) {
        Clean
      } else {
        Unsaved
      }
  }
}

///|
pub fn Model::save_status(self : Self, key : Key) -> SaveStatus? {
  find_record(self.records, key).map(record => self.record_save_status(record))
}

///|
pub fn Model::replica_owner(
  self : Self,
  key : Key,
) -> (@source_repository.AccountId, @source_repository.DocumentId)? {
  match find_record(self.records, key) {
    Some(record) =>
      match record.persistence {
        Replica(account, _, _) => Some((account, record.document.id()))
        Forking(ownership, _) => Some((ownership.account, ownership.original))
        Source(_, _) | StartingSync(_, _, _) => None
      }
    None => None
  }
}

///|
pub fn Model::delete_status(self : Self, key : Key) -> DeleteStatus? {
  find_record(self.records, key).map(record => record.delete_status())
}

///|
pub fn Model::recent(
  self : Self,
) -> Array[(Key, String, SaveStatus, DeleteStatus)] {
  self.records.filter_map(record => {
    guard self.record_is_visible(record) &&
      record.lead_source is Available(source) else {
      return None
    }
    Some(
      (
        record.key(),
        source,
        self.record_save_status(record),
        record.delete_status(),
      ),
    )
  })
}

///|
/// Includes durable deleting/tombstoned Replicas without a Recent documents row.
pub fn Model::known_keys(self : Self) -> Array[Key] {
  self.records.map(record => record.key()) +
  self.saved
  .replicas()
  .map(replica => Key::replica(replica.account(), replica.document_id()))
}

///|
pub fn Model::pending_edits(self : Self) -> Array[(Key, Int)] {
  self.records.filter_map(record => {
    match record.edit {
      Waiting(revision) if record.delete_status() != DeletePending =>
        Some((record.key(), revision))
      _ => None
    }
  })
}
