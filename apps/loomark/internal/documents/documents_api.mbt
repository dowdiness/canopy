///|
fn transition(model : Model, effects : ReadOnlyArray[Action]) -> Transition {
  { model, effects, }
}

///|
fn applied_record(
  model : Model,
  key : Key,
  record : Record,
  effects : ReadOnlyArray[Action],
) -> Update {
  Applied(
    transition(
      { ..model, records: replace_record(model.records, key, _ => record), },
      effects,
    ),
  )
}

///|
pub fn Model::edit(
  self : Self,
  key : Key,
  text : String,
) -> Edit raise EditError {
  guard find_record(self.records, key) is Some(record) else {
    raise DocumentMissing(key)
  }
  guard record.delete_status() != DeletePending else {
    raise PendingDeletion(key)
  }
  if record.document.text() == text {
    return SameText
  }
  let (model, effects) = apply_text(self, record, text)
  Changed(transition(model, effects))
}

///|
pub fn Model::update(self : Self, message : Msg) -> Update raise UpdateError {
  match message {
    New(document_id) | Imported(document_id, _) => {
      let key = Key::source(document_id)
      if find_record(self.records, key) is Some(_) {
        raise DocumentAlreadyExists(key)
      }
      let (origin, text, lead_source) = match message {
        Imported(_, text) =>
          (LocalDocumentOrigin::ImportedNew, text, LeadSource::Available(text))
        _ => (LocalDocumentOrigin::EphemeralNew, "", LeadSource::Unlisted)
      }
      let document = @source_repository.Document::create(document_id, text)
      let record : Record = {
        persistence: Source(origin, Writable(Idle, None)),
        document,
        version: 0,
        edit: Idle,
        lead_source,
      }
      let (model, record, effects) = if origin is ImportedNew {
        request_save(self, record)
      } else {
        (self, record, [])
      }
      Applied(
        transition(
          { ..model, records: prepend_record(model.records, record), },
          effects,
        ),
      )
    }
    CompositionStarted(key) => {
      guard find_record(self.records, key) is Some(record) &&
        record.delete_status() != DeletePending else {
        return Superseded
      }
      let edit : Editing = match record.edit {
        Waiting(revision) => ComposingWaiting(revision)
        Idle => ComposingIdle
        ComposingIdle | ComposingWaiting(_) | ComposingReady => return Unchanged
      }
      applied_record(self, key, { ..record, edit, }, [])
    }
    CompositionEnded(key) => {
      guard find_record(self.records, key) is Some(record) &&
        record.delete_status() != DeletePending else {
        return Superseded
      }
      let (record, effects) = match record.edit {
        ComposingReady => accept_pending(self.saved, record)
        ComposingIdle =>
          finish_composition(self.saved, { ..record, edit: Idle, })
        ComposingWaiting(revision) =>
          finish_composition(self.saved, { ..record, edit: Waiting(revision), })
        Idle | Waiting(_) => return Unchanged
      }
      applied_record(self, key, record, effects)
    }
    RetrySave(key) => {
      guard find_record(self.records, key) is Some(record) else {
        raise DocumentMissing(key)
      }
      guard record.delete_status() != DeletePending else {
        raise PendingDeletion(key)
      }
      guard record.save_failure() is Some(_) else { return Unchanged }
      guard !is_composing(record.edit) else { raise CompositionInProgress(key) }
      let (model, record, effects) = request_save(self, record)
      applied_record(model, key, record, effects)
    }
    VisibilityFlush(key) => {
      guard find_record(self.records, key) is Some(record) &&
        record.delete_status() != DeletePending else {
        return Superseded
      }
      guard record.pending_window() is Some(window) else { return Unchanged }
      let (flushed, effects) = mark_eligible(self.saved, record, window)
      if flushed == record && effects.is_empty() {
        return Unchanged
      }
      applied_record(self, key, flushed, effects)
    }
    VisibilityFlushAll => {
      let effects : Array[Action] = []
      let mut changed = false
      let records = self.records.map(record => {
        let (flushed, added) = flush_visibility(self.saved, record)
        changed = changed || flushed != record
        for effect in added {
          effects.push(effect)
        }
        flushed
      })
      if !changed && effects.is_empty() {
        return Unchanged
      }
      Applied(
        transition({ ..self, records, }, ReadOnlyArray::from_array(effects)),
      )
    }
    ApplyPendingEdit(key, revision) => {
      guard find_record(self.records, key) is Some(record) &&
        record.delete_status() != DeletePending else {
        return Superseded
      }
      let (record, effects) = match record.edit {
        Waiting(current) if current == revision =>
          accept_pending(self.saved, record)
        ComposingWaiting(current) if current == revision =>
          ({ ..record, edit: ComposingReady, }, [])
        _ => return Superseded
      }
      applied_record(self, key, record, effects)
    }
    DismissDeleteFailure(key) => {
      guard find_record(self.records, key) is Some(record) else {
        raise DocumentMissing(key)
      }
      guard record.persistence is Source(origin, Writable(save, Some(_))) else {
        return Unchanged
      }
      applied_record(
        self,
        key,
        { ..record, persistence: Source(origin, Writable(save, None)), },
        [],
      )
    }
    MaximumElapsed(maximum) => {
      guard self.records
        .exact_view()
        .search_by(record => {
          record
          .pending_window()
          .map(window => window.maximum_id == maximum)
          .unwrap_or(false)
        })
        is Some(index) else {
        return Superseded
      }
      let record = self.records[index]
      guard record.delete_status() != DeletePending &&
        record.pending_window() is Some(window) &&
        window.eligibility == Deferred else {
        return Superseded
      }
      let (record, effects) = mark_eligible(self.saved, record, window)
      applied_record(self, record.key(), record, effects)
    }
    Saved(operation, document) => save_succeeded(self, operation, document)
    SaveFailed(operation, failure) => save_failed(self, operation, failure)
    Deleted(operation, document_id) =>
      delete_succeeded(self, operation, document_id)
    DeleteFailed(operation, failure) => delete_failed(self, operation, failure)
    ReplicaAdvanced(write) => advance_replica(self, write)
    ReplicaSettled(write, mounted) => settle_replica(self, write, mounted)
    ReplicaDeletionFailed(write, failure) =>
      fail_replica_deletion(self, write, failure)
    Promoted(write) => complete_sync_start(self, write, None)
    PromotionFailed(write, failure) =>
      complete_sync_start(self, write, Some(failure))
  }
}
