///|
pub fn State::reduce(self : Self, event : Msg) -> (Self, Array[Effect]) {
  match event {
    New(document_id) => {
      let key = Key::source(document_id)
      guard find_record(self.records, key) is None else { return (self, []) }
      let document = @source_repository.Document::create(document_id, "")
      let record = {
        persistence: Source(EphemeralNew, SourceDeletePhase::Available),
        document,
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
          finish_composition(self.saved, document_id, { ..record, edit: Idle, })
        ComposingWaiting(revision) =>
          finish_composition(self.saved, document_id, {
            ..record,
            edit: Waiting(revision),
          })
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
        MaximumElapsed(id, checkpoint) => eligible_maximum(self, id, checkpoint)
        SaveCompleted(operation, result) => complete(self, operation, result)
        CheckpointCompleted(result) => complete_checkpoint(self, result)
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
              | Checkpoint(_) => r
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
  find_record(self.records, document_id).map(record => record.document)
}

///|
pub fn State::resume_hint(
  self : Self,
  key : Key,
) -> @source_repository.EditingDocumentHint? {
  match find_record(self.records, key) {
    Some(record) =>
      match record.persistence {
        Source(_, _) => self.saved.editing_document_hint(record.document.id())
        Checkpoint(_) => None
      }
    None => None
  }
}

///|
pub fn State::is_composing(self : Self, id : Key) -> Bool {
  find_record(self.records, id).map(r => is_composing(r.edit)).unwrap_or(false)
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
  find_record(self.records, id).map(r => r.document.text())
}

///|
pub fn State::save_status(self : Self, id : Key) -> SaveStatus? {
  find_record(self.records, id).map(r => {
    match r.save {
      DocumentsSaveStatus::Saved => SaveStatus::Clean
      DocumentsSaveStatus::Failed(failure) => SaveStatus::SaveFailed(failure)
      DocumentsSaveStatus::Waiting(_) | DocumentsSaveStatus::Saving(_, _) =>
        SaveStatus::Unsaved
    }
  })
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
