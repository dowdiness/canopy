///|
pub fn Model::document(
  self : Self,
  document_id : Key,
) -> @source_repository.Document? {
  match find_record(self.records, document_id) {
    Some(record) => Some(record.document)
    None => None
  }
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
        Source(_, _) | StartingSync(_, _) =>
          self.saved.editing_document_hint(record.document.id())
        Replica(_, _) | Forking(_) => None
      }
    None => None
  }
}

///|
pub fn Model::is_composing(self : Self, id : Key) -> Bool {
  find_record(self.records, id).map(r => is_composing(r.edit)).unwrap_or(false)
}

///|
pub fn Model::sync_start(
  self : Self,
  id : Key,
  account : @source_repository.AccountId,
) -> SyncStart {
  match find_record(self.records, id) {
    Some(record) if record.persistence is StartingSync(owner, _) &&
      owner == account => Starting
    Some(record) if record.persistence
      is Source(Existing, SourceLifecycle::Available) &&
      record.save is Saved &&
      record.edit is Idle &&
      self.saved.find(record.document.id()) == Some(record.document) &&
      self.saved.replica(account, record.document.id()) is None =>
      Ready({ key: id, account, document: record.document, })
    Some(_) | None => Unavailable
  }
}

///|
/// Project the working copy and newest observed remote head as one state. A
/// remote action exists only when its body still matches that head exactly.
pub fn Model::remote_state(
  self : Self,
  replica : @source_repository.DocumentReplica,
  catalog_head : @source_repository.RemoteHead?,
) -> RemoteState {
  let key = Key::replica(replica.account(), replica.document_id())
  guard find_record(self.records, key) is Some(record) &&
    replica.live() is Some(live) else {
    return RemoteState::Unavailable
  }
  let knowledge = replica.remote_knowledge(catalog_head)
  let relation = live.relation(record.document.text(), knowledge)
  let action = if record.persistence is Replica(account, ReplicaAvailable) &&
    account == replica.account() &&
    self.visible_account == Some(account) &&
    replica.document() == Some(record.document) &&
    record.save is DocumentsSaveStatus::Saved &&
    record.edit is EditState::Idle &&
    self.saved.replica(account, replica.document_id()) == Some(replica) &&
    replica.remote_update() is Some(update) &&
    knowledge.head() == Some(update.head()) {
    Some({ key, version: record.version, update, })
  } else {
    None
  }
  match (relation, action) {
    (@source_repository.Relation::RemoteAhead, Some(action)) =>
      RemoteState::UpdateAvailable(action)
    (@source_repository.Relation::DeletedRemotely, Some(action)) =>
      RemoteState::DeletionAvailable(action)
    (Current, _) => RemoteState::Current
    (LocalAhead, _) => RemoteState::LocalAhead
    (RemoteAhead, _) => RemoteState::RemoteAhead
    (Concurrent, _) => RemoteState::Concurrent
    (Diverged, _) => RemoteState::Diverged
    (DeletedRemotely, _) => RemoteState::DeletedRemotely
    (Unavailable, _) => RemoteState::Unavailable
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
    RemoteState::UpdateAvailable(current) | DeletionAvailable(current) =>
      current
    Current
    | LocalAhead
    | RemoteAhead
    | Concurrent
    | Diverged
    | DeletedRemotely
    | Unavailable => raise ExpiredAction
  }
  guard current == action else { raise ExpiredAction }
  let write = action.update.accept()
  let accepted = write.replica()
  let (self, version) = allocate_working_copy_version(self)
  match action.update.remote() {
    @source_repository.RemoteDocument::Present(_, _) => {
      guard accepted.document() is Some(document) else { raise ExpiredAction }
      let records = replace_record(self.records, action.key, record => {
        ..record,
        document,
        version,
        edit: EditState::Idle,
        save: DocumentsSaveStatus::Saved,
        lead_source: LeadSource::Available(document.text()),
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
  .filter(r => {
    r.key() != excluding &&
    self.record_is_visible(r) &&
    !delete_is_active(r.delete_phase()) &&
    !(r.persistence is DocumentPersistence::Source(EphemeralNew, _))
  })
  .get(0)
  .map(r => r.key())
}

///|
pub fn Model::snapshot(self : Self) -> @source_repository.SavedDocuments {
  self.saved
}

///|
pub fn Model::text(self : Self, id : Key) -> String? {
  self.document(id).map(document => document.text())
}

///|
pub fn Model::is_ephemeral_new(self : Self, id : Key) -> Bool {
  match find_record(self.records, id) {
    Some(record) => record.persistence is Source(EphemeralNew, _)
    None => false
  }
}

///|
pub fn Model::save_status(self : Self, id : Key) -> SaveStatus? {
  find_record(self.records, id).map(r => {
    match r.persistence {
      Replica(account, _) =>
        match r.save {
          DocumentsSaveStatus::Waiting(_) | DocumentsSaveStatus::Saving(_, _) =>
            SaveStatus::Unsaved
          Failed(failure) => SaveStatus::SaveFailed(failure)
          Saved =>
            match self.saved.replica(account, r.document.id()) {
              Some(replica) if replica.document() == Some(r.document) =>
                SaveStatus::Clean
              Some(_) | None => SaveStatus::Unsaved
            }
        }
      Source(_, _) | StartingSync(_, _) =>
        match r.save {
          DocumentsSaveStatus::Saved => SaveStatus::Clean
          DocumentsSaveStatus::Failed(failure) =>
            SaveStatus::SaveFailed(failure)
          DocumentsSaveStatus::Waiting(_) | DocumentsSaveStatus::Saving(_, _) =>
            SaveStatus::Unsaved
        }
      Forking(_) => SaveStatus::Unsaved
    }
  })
}

///|
/// Return the Replica persistence lane that currently owns this working copy.
/// A recovery Source keeps its original owner until the atomic fork commits.
pub fn Model::replica_owner(
  self : Self,
  key : Key,
) -> (@source_repository.AccountId, @source_repository.DocumentId)? {
  match find_record(self.records, key) {
    Some(record) =>
      match record.persistence {
        Replica(account, _) => Some((account, record.document.id()))
        Forking(ownership) => Some((ownership.account, ownership.original))
        Source(_, _) | StartingSync(_, _) => None
      }
    None => None
  }
}

///|
#warnings("-unused_value")
fn Model::save_phase(self : Self, id : Key) -> DocumentsSaveStatus? {
  find_record(self.records, id).map(r => r.save)
}

///|
pub fn Model::delete_status(self : Self, id : Key) -> DeleteStatus? {
  find_record(self.records, id).map(r => {
    match r.delete_phase() {
      DocumentsDeletePhase::Unavailable => DeleteStatus::NotDeletable
      DocumentsDeletePhase::Available => DeleteStatus::Deletable
      DocumentsDeletePhase::Waiting(_) | DocumentsDeletePhase::Deleting(_) =>
        DeleteStatus::DeletePending
      DocumentsDeletePhase::Failed(_, failure) =>
        DeleteStatus::DeleteFailed(failure)
      DocumentsDeletePhase::ReplicaPending => DeleteStatus::DeletePending
      DocumentsDeletePhase::ReplicaFailed(failure) =>
        DeleteStatus::DeletePersistenceFailed(failure)
    }
  })
}

///|
#warnings("-unused_value")
fn Model::delete_phase_status(self : Self, id : Key) -> DocumentsDeletePhase? {
  find_record(self.records, id).map(r => r.delete_phase())
}

///|
pub fn Model::recent(
  self : Self,
) -> Array[(Key, String, SaveStatus, DeleteStatus)] {
  self.records.filter_map(record => {
    guard self.record_is_visible(record) else { return None }
    guard record.lead_source is LeadSource::Available(source) else {
      return None
    }
    Some(
      (
        record.key(),
        source,
        self.save_status(record.key()).unwrap(),
        self.delete_status(record.key()).unwrap(),
      ),
    )
  })
}

///|
/// Identities owned locally, including durable deleting/tombstoned Replicas
/// that intentionally have no Recent documents row.
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
      Waiting(revision) if !delete_is_active(record.delete_phase()) =>
        Some((record.key(), revision))
      Idle
      | Waiting(_)
      | ComposingIdle
      | ComposingWaiting(_)
      | ComposingReady => None
    }
  })
}
