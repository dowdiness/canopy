///|
pub fn State::reduce(self : Self, event : Msg) -> (Self, Array[Action]) {
  match event {
    New(document_id) => {
      let key = Key::source(document_id)
      guard find_record(self.records, key) is None else { return (self, []) }
      let document = @source_repository.Document::create(document_id, "")
      let record = {
        persistence: Source(EphemeralNew, SourceDeletePhase::Available),
        document,
        version: 0,
        edit: Idle,
        save: Saved,
        lead_source: Unlisted,
      }
      ({ ..self, records: prepend_record(self.records, record), }, [])
    }
    Imported(document_id, text) => import_document(self, document_id, text)
    TextChanged(document_id, text) => apply_text(self, document_id, text)
    CompositionStarted(document_id) =>
      (
        {
          ..self,
          records: replace_record(self.records, document_id, r => {
            if delete_is_active(r.delete_phase()) {
              r
            } else {
              {
                ..r,
                edit: match r.edit {
                  Waiting(revision) => ComposingWaiting(revision)
                  Idle => ComposingIdle
                  ComposingIdle | ComposingWaiting(_) | ComposingReady => r.edit
                },
              }
            }
          }),
        },
        [],
      )
    CompositionEnded(document_id) => {
      guard find_record(self.records, document_id) is Some(record) else {
        return (self, [])
      }
      guard !delete_is_active(record.delete_phase()) else { return (self, []) }
      let (record, decisions) = match record.edit {
        ComposingReady => accept_pending(self.saved, record)
        ComposingIdle =>
          finish_composition(self.saved, { ..record, edit: Idle, })
        ComposingWaiting(revision) =>
          finish_composition(self.saved, { ..record, edit: Waiting(revision), })
        Idle | Waiting(_) => return (self, [])
      }
      (
        {
          ..self,
          records: replace_record(self.records, document_id, _ => record),
        },
        decisions,
      )
    }
    ApplyPendingEdit(document_id, revision) =>
      apply_pending_edit(self, document_id, revision)
    FeedbackReceived(feedback) =>
      match feedback {
        MaximumElapsed(maximum) => eligible_maximum(self, maximum)
        SaveCompleted(operation, result) => complete(self, operation, result)
        ReplicaAdvanced(write) => advance_replica(self, write)
        ReplicaSettled(write, mounted) => settle_replica(self, write, mounted)
        ReplicaDeletionFailed(write, failure) =>
          fail_replica_deletion(self, write, failure)
        PromotionCompleted(write, result) =>
          complete_sync_start(self, write.replica(), result)
        DeleteCompleted(operation, result) =>
          finish_delete(self, operation, result)
      }
    DeleteConfirmed(id) => confirm_or_retry_delete(self, id)
    RetryDelete(id) => confirm_or_retry_delete(self, id)
    DismissDeleteFailure(id) =>
      (
        {
          ..self,
          records: replace_record(self.records, id, r => {
            match r.persistence {
              Source(origin, SourceDeletePhase::Failed(_, _)) =>
                {
                  ..r,
                  persistence: Source(origin, SourceDeletePhase::Available),
                }
              Source(
                _,
                SourceDeletePhase::Available
                | SourceDeletePhase::Waiting(_)
                | SourceDeletePhase::Deleting(_)
              )
              | StartingSync(_, _)
              | Replica(_, _)
              | Forking(_) => r
            }
          }),
        },
        [],
      )
    RetrySave(id) => {
      guard find_record(self.records, id) is Some(record) else {
        return (self, [])
      }
      match record.save {
        Failed(_) if !is_composing(record.edit) &&
          !delete_is_active(record.delete_phase()) => {
          let (next, effects) = begin_save(self.saved, record)
          (
            { ..self, records: replace_record(self.records, id, _ => next), },
            effects,
          )
        }
        _ => (self, [])
      }
    }
    VisibilityFlush(id) => {
      guard find_record(self.records, id) is Some(record) else {
        return (self, [])
      }
      guard !delete_is_active(record.delete_phase()) else { return (self, []) }
      match record.save {
        Waiting(_) | Saving(_, Some(_)) => {
          let (record, decisions) = mark_eligible(self.saved, record)
          (
            { ..self, records: replace_record(self.records, id, _ => record), },
            decisions,
          )
        }
        Saved | Saving(_, None) | Failed(_) => (self, [])
      }
    }
  }
}

///|
pub fn State::document(
  self : Self,
  document_id : Key,
) -> @source_repository.Document? {
  match find_record(self.records, document_id) {
    Some(record) => Some(record.document)
    None => None
  }
}

///|
pub fn OpenedDocument::documents(self : Self) -> State {
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
pub fn State::resume_hint(
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
pub fn State::is_composing(self : Self, id : Key) -> Bool {
  find_record(self.records, id).map(r => is_composing(r.edit)).unwrap_or(false)
}

///|
pub fn State::sync_start(
  self : Self,
  id : Key,
  account : @source_repository.AccountId,
) -> SyncStart {
  match find_record(self.records, id) {
    Some(record) if record.persistence is StartingSync(owner, _) &&
      owner == account => Starting
    Some(record) if record.persistence
      is Source(Existing, SourceDeletePhase::Available) &&
      record.save is Saved &&
      record.edit is Idle &&
      self.saved.find(record.document.id()) == Some(record.document) &&
      self.saved.replica(account, record.document.id()) is None =>
      Ready({ key: id, account, document: record.document, })
    Some(_) | None => Unavailable
  }
}

///|
/// Project a remote revision only while the matching working copy is clean and
/// idle. Persistence and account admission remain owned by the caller.
pub fn State::remote_change(
  self : Self,
  replica : @source_repository.DocumentReplica,
) -> RemoteChange? {
  let key = Key::replica(replica.account(), replica.document_id())
  guard find_record(self.records, key) is Some(record) &&
    record.persistence is Replica(account, ReplicaAvailable) &&
    account == replica.account() &&
    self.visible_account == Some(account) &&
    replica.document() == Some(record.document) &&
    record.save is DocumentsSaveStatus::Saved &&
    record.edit is EditState::Idle &&
    self.saved.replica(account, replica.document_id()) == Some(replica) &&
    replica.remote_update() is Some(update) else {
    return None
  }
  let action = { key, version: record.version, update, }
  match update.remote() {
    @source_repository.RemoteDocument::Present(_, _) =>
      Some(RemoteChange::UpdateAvailable(action))
    Deleted(_) => Some(RemoteChange::DeletedRemotely(action))
    Missing => None
  }
}

///|
pub fn State::accept_remote(
  self : Self,
  replica : @source_repository.DocumentReplica,
  action : AcceptRemote,
) -> RemoteAcceptance raise ActionError {
  guard self.remote_change(replica) is Some(change) else { raise ExpiredAction }
  let current = match change {
    RemoteChange::UpdateAvailable(current) | DeletedRemotely(current) => current
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
pub fn State::fallback_document(self : Self, excluding : Key) -> Key? {
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
pub fn State::snapshot(self : Self) -> @source_repository.SavedDocuments {
  self.saved
}

///|
pub fn State::text(self : Self, id : Key) -> String? {
  self.document(id).map(document => document.text())
}

///|
pub fn State::save_status(self : Self, id : Key) -> SaveStatus? {
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
pub fn State::replica_owner(
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
fn State::save_phase(self : Self, id : Key) -> DocumentsSaveStatus? {
  find_record(self.records, id).map(r => r.save)
}

///|
pub fn State::delete_status(self : Self, id : Key) -> DeleteStatus? {
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
fn State::delete_phase_status(self : Self, id : Key) -> DocumentsDeletePhase? {
  find_record(self.records, id).map(r => r.delete_phase())
}

///|
pub fn State::recent(
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
pub fn State::known_keys(self : Self) -> Array[Key] {
  self.records.map(record => record.key()) +
  self.saved
  .replicas()
  .map(replica => Key::replica(replica.account(), replica.document_id()))
}

///|
pub fn State::pending_edits(self : Self) -> Array[(Key, Int)] {
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
