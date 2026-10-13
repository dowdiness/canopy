///|
fn transition(model : Model, effects : Array[Action]) -> Transition {
  { model, effects: ReadOnlyArray::from_array(effects), }
}

///|
pub fn Model::edit(self : Self, key : Key, text : String) -> Edit raise EditError {
  guard find_record(self.records, key) is Some(record) else {
    raise EditError::DocumentMissing(key)
  }
  guard !delete_is_active(record.delete_phase()) else {
    raise EditError::PendingDeletion(key)
  }
  if record.document.text() == text {
    return SameText
  }
  let (model, effects) = apply_text(self, key, text)
  Changed(transition(model, effects))
}

///|
pub fn Model::delete(self : Self, key : Key) -> Delete raise DeleteError {
  guard find_record(self.records, key) is Some(record) else {
    raise DeleteError::DocumentMissing(key)
  }
  match record.persistence {
    StartingSync(_, _) | Forking(_) =>
      raise DeleteError::OwnershipTransferInProgress(key)
    Replica(account, _) if self.saved.replica(account, record.document.id()) is None =>
      raise DeleteError::ReplicaMissing(key)
    Source(_, SourceLifecycle::Waiting(_)
    | SourceLifecycle::Deleting(_)) | Replica(_, ReplicaPending) =>
      AlreadyPending
    Source(_, _) | Replica(_, _) => {
      let (model, effects) = confirm_or_retry_delete(self, key)
      Accepted(transition(model, effects))
    }
  }
}

///|
pub fn Model::update(self : Self, message : Msg) -> Update raise UpdateError {
  match message {
    New(document_id) => {
      let key = Key::source(document_id)
      if find_record(self.records, key) is Some(_) {
        raise UpdateError::DocumentAlreadyExists(key)
      }
      let (model, effects) = add_new_document(self, document_id)
      Applied(transition(model, effects))
    }
    Imported(document_id, text) => {
      let key = Key::source(document_id)
      if find_record(self.records, key) is Some(_) {
        raise UpdateError::DocumentAlreadyExists(key)
      }
      let (model, effects) = import_document(self, document_id, text)
      Applied(transition(model, effects))
    }
    CompositionStarted(key) => {
      let (model, effects) = composition_started(self, key)
      Applied(transition(model, effects))
    }
    CompositionEnded(key) => {
      let (model, effects) = composition_ended(self, key)
      Applied(transition(model, effects))
    }
    RetrySave(key) => {
      let (model, effects) = retry_save(self, key)
      Applied(transition(model, effects))
    }
    VisibilityFlush(key) => {
      let (model, effects) = flush_one(self, key)
      Applied(transition(model, effects))
    }
    VisibilityFlushAll => {
      let (model, effects) = flush_all(self)
      Applied(transition(model, effects))
    }
    ApplyPendingEdit(key, revision) => {
      guard find_record(self.records, key) is Some(record) else { return Superseded }
      guard record.edit is Waiting(current) && current == revision ||
        record.edit is ComposingWaiting(current) && current == revision else {
        return Superseded
      }
      let (model, effects) = apply_pending_edit(self, key, revision)
      Applied(transition(model, effects))
    }
    DismissDeleteFailure(key) => {
      let (model, effects) = dismiss_delete_failure(self, key)
      Applied(transition(model, effects))
    }
    MaximumElapsed(maximum) => {
      guard maximum_is_active(self, maximum) else { return Superseded }
      let (model, effects) = eligible_maximum(self, maximum)
      Applied(transition(model, effects))
    }
    Saved(operation, document) => {
      guard save_operation_is_active(self, operation) else { return Superseded }
      if document != operation.document {
        raise UpdateError::DocumentMismatch(operation.key)
      }
      guard self.saved.apply(@source_repository.RepositoryChange::Stored(document))
        is Some(_) else { raise UpdateError::InvalidAcknowledgment(operation.key) }
      let (model, effects) = complete(self, operation, Stored(document))
      Applied(transition(model, effects))
    }
    SaveFailed(operation, failure) => {
      guard save_operation_is_active(self, operation) else { return Superseded }
      let (model, effects) = complete(self, operation, @source_repository.SaveResult::SaveFailed(failure))
      Applied(transition(model, effects))
    }
    Deleted(operation, document_id) => {
      guard delete_operation_is_active(self, operation) else { return Superseded }
      if document_id != operation.document_id {
        raise UpdateError::DocumentMismatch(operation.key)
      }
      guard self.saved.apply(@source_repository.RepositoryChange::Deleted(document_id))
        is Some(_) else { raise UpdateError::InvalidAcknowledgment(operation.key) }
      let (model, effects) = finish_delete(self, operation, @source_repository.DeleteResult::Deleted(document_id))
      Applied(transition(model, effects))
    }
    DeleteFailed(operation, failure) => {
      guard delete_operation_is_active(self, operation) else { return Superseded }
      let (model, effects) = finish_delete(self, operation, @source_repository.DeleteResult::DeleteFailed(failure))
      Applied(transition(model, effects))
    }
    ReplicaAdvanced(write) => {
      let key = Key::replica(write.replica().account(), write.replica().document_id())
      let (model, effects) = advance_replica(self, write)
      Applied(transition(model, effects))
    }
    ReplicaSettled(write, mounted) => {
      let key = Key::replica(write.replica().account(), write.replica().document_id())
      let (model, effects) = settle_replica(self, write, mounted)
      Applied(transition(model, effects))
    }
    ReplicaDeletionFailed(write, failure) => {
      let replica = write.replica()
      let key = Key::replica(replica.account(), replica.document_id())
      guard find_record(self.records, key) is Some(record) &&
        record.persistence is Replica(account, ReplicaPending) &&
        account == replica.account() else { return Superseded }
      let (model, effects) = fail_replica_deletion(self, write, failure)
      Applied(transition(model, effects))
    }
    Promoted(write) => {
      guard promotion_is_active(self, write) else { return Superseded }
      let (model, effects) = complete_sync_start(self, write.replica(), Ok(()))
      Applied(transition(model, effects))
    }
    PromotionFailed(write, failure) => {
      guard promotion_is_active(self, write) else { return Superseded }
      let (model, effects) = complete_sync_start(self, write.replica(), Err(failure))
      Applied(transition(model, effects))
    }
  }
}

///|
fn add_new_document(model : Model, document_id : @source_repository.DocumentId) -> (Model, Array[Action]) {
  let key = Key::source(document_id)
  guard find_record(model.records, key) is None else { return (model, []) }
  let document = @source_repository.Document::create(document_id, "")
  let record = {
    persistence: Source(EphemeralNew, SourceLifecycle::Available),
    document,
    version: 0,
    edit: Idle,
    save: Saved,
    lead_source: Unlisted,
  }
  ({ ..model, records: prepend_record(model.records, record), }, [])
}

///|
fn composition_started(model : Model, key : Key) -> (Model, Array[Action]) {
  ( 
    {
      ..model,
      records: replace_record(model.records, key, r => {
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
}

///|
fn composition_ended(model : Model, key : Key) -> (Model, Array[Action]) {
  guard find_record(model.records, key) is Some(record) else { return (model, []) }
  guard !delete_is_active(record.delete_phase()) else { return (model, []) }
  let (record, effects) = match record.edit {
    ComposingReady => accept_pending(model.saved, record)
    ComposingIdle => finish_composition(model.saved, { ..record, edit: Idle, })
    ComposingWaiting(revision) => finish_composition(model.saved, { ..record, edit: Waiting(revision), })
    Idle | Waiting(_) => return (model, [])
  }
  ({ ..model, records: replace_record(model.records, key, _ => record), }, effects)
}

///|
fn retry_save(model : Model, key : Key) -> (Model, Array[Action]) {
  guard find_record(model.records, key) is Some(record) else { return (model, []) }
  match record.save {
    Failed(_) if !is_composing(record.edit) && !delete_is_active(record.delete_phase()) => {
      let (next, effects) = begin_save(model.saved, record)
      ({ ..model, records: replace_record(model.records, key, _ => next), }, effects)
    }
    _ => (model, [])
  }
}

///|
fn flush_one(model : Model, key : Key) -> (Model, Array[Action]) {
  guard find_record(model.records, key) is Some(record) else { return (model, []) }
  let (updated, effects) = flush_visibility(model.saved, record)
  ({ ..model, records: replace_record(model.records, key, _ => updated), }, effects)
}

///|
fn flush_all(model : Model) -> (Model, Array[Action]) {
  let effects : Array[Action] = []
  let records = model.records.map(record => {
    let (record, new_effects) = flush_visibility(model.saved, record)
    for effect in new_effects { effects.push(effect) }
    record
  })
  ({ ..model, records, }, effects)
}

///|
fn dismiss_delete_failure(model : Model, key : Key) -> (Model, Array[Action]) {
  (
    {
      ..model,
      records: replace_record(model.records, key, r => {
        match r.persistence {
          Source(origin, SourceLifecycle::Failed(_, _)) =>
            { ..r, persistence: Source(origin, SourceLifecycle::Available), }
          Source(_, SourceLifecycle::Available | SourceLifecycle::Waiting(_) | SourceLifecycle::Deleting(_))
          | StartingSync(_, _) | Replica(_, _) | Forking(_) => r
        }
      }),
    },
    [],
  )
}

///|
fn save_operation_is_active(model : Model, operation : SaveOperation) -> Bool {
  match find_record(model.records, operation.key) {
    Some(record) => record.save is Saving(active, _) && active == operation
    None => false
  }
}

///|
fn delete_operation_is_active(model : Model, operation : DeleteOperation) -> Bool {
  match find_record(model.records, operation.key) {
    Some(record) => record.persistence is Source(_, SourceLifecycle::Deleting(active)) && active == operation
    None => false
  }
}

///|
fn maximum_is_active(model : Model, maximum : Int) -> Bool {
  model.records
  .exact_view()
  .search_by(record => {
    match record.save {
      Waiting(window) | Saving(_, Some(window)) => window.maximum_id == maximum
      Saved | Saving(_, None) | Failed(_) => false
    }
  })
  .is_some()
}

///|
fn promotion_is_active(model : Model, write : @source_repository.ReplicaWrite) -> Bool {
  let replica = write.replica()
  match find_record(model.records, Key::source(replica.document_id())) {
    Some(record) => record.persistence is StartingSync(account, _) && account == replica.account()
    None => false
  }
}
