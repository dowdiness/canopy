///|
fn Documents::reduce(
  self : Self,
  event : DocumentsEvent,
) -> (Self, Array[DocumentsDecision]) {
  match event {
    DocumentsNew(document_id) => {
      guard find_record(self.records, document_id) is None else {
        return (self, [])
      }
      let document = @source_repository.Document::create(document_id, "") catch {
        _ => abort("invalid generated document id")
      }
      let record = {
        document,
        origin: EphemeralNew,
        edit: Idle,
        save: Saved,
        lead_source: Unlisted,
        delete: Available,
      }
      ({ ..self, records: prepend_record(self.records, record), }, [])
    }
    DocumentsImported(document_id, text) =>
      import_document(self, document_id, text)
    DocumentsTextChanged(document_id, text) =>
      apply_text(self, document_id, text)
    DocumentsCompositionStarted(document_id) =>
      (
        {
          ..self,
          records: replace_record(self.records, document_id, r => {
            if delete_is_active(r.delete) {
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
    DocumentsCompositionEnded(document_id) => {
      guard find_record(self.records, document_id) is Some(record) else {
        return (self, [])
      }
      guard !delete_is_active(record.delete) else { return (self, []) }
      let (record, decisions) = match record.edit {
        ComposingReady => accept_pending(record)
        ComposingIdle =>
          finish_composition(document_id, { ..record, edit: Idle, })
        ComposingWaiting(revision) =>
          finish_composition(document_id, { ..record, edit: Waiting(revision), })
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
    DocumentsFeedbackReceived(feedback) =>
      match feedback {
        MaximumElapsed(id, checkpoint) => eligible_maximum(self, id, checkpoint)
        SaveCompleted(operation, result) => complete(self, operation, result)
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
            match r.delete {
              Failed(_, _) => { ..r, delete: Available, }
              _ => r
            }
          }),
        },
        [],
      )
    DocumentsRetrySave(id) => {
      guard find_record(self.records, id) is Some(record) else {
        return (self, [])
      }
      match record.save {
        Failed(_) if !is_composing(record.edit) &&
          !delete_is_active(record.delete) => {
          let (next, decisions) = begin_save(record)
          (
            { ..self, records: replace_record(self.records, id, _ => next), },
            decisions,
          )
        }
        _ => (self, [])
      }
    }
    DocumentsVisibilityFlush(id) => {
      guard find_record(self.records, id) is Some(record) else {
        return (self, [])
      }
      guard !delete_is_active(record.delete) else { return (self, []) }
      match record.save {
        Waiting(_) | Saving(_, Some(_)) => {
          let (record, decisions) = mark_eligible(record)
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
fn Documents::activation_target(
  self : Self,
  document_id : String,
) -> ActivationTarget? {
  find_record(self.records, document_id).map(record => {
    document: record.document,
    resume_hint: self.saved.editing_document_hint(document_id),
  })
}

///|
fn Documents::is_composing(self : Self, id : String) -> Bool {
  find_record(self.records, id).map(r => is_composing(r.edit)).unwrap_or(false)
}

///|
fn Documents::fallback_document(self : Self, excluding : String) -> String? {
  self.records
  .filter(r => {
    r.document.id() != excluding &&
    !delete_is_active(r.delete) &&
    r.origin != EphemeralNew
  })
  .get(0)
  .map(r => r.document.id())
}

///|
fn Documents::snapshot(self : Self) -> @source_repository.SavedDocuments {
  self.saved
}

///|
fn Documents::current_documents(
  self : Self,
) -> Array[@source_repository.Document] {
  self.records.map(r => r.document)
}

///|
fn Documents::text(self : Self, id : String) -> String? {
  find_record(self.records, id).map(r => r.document.text())
}

///|
fn Documents::save_status(self : Self, id : String) -> DocumentsSaveStatus? {
  find_record(self.records, id).map(r => r.save)
}

///|
fn Documents::delete_status(self : Self, id : String) -> DocumentsDeletePhase? {
  find_record(self.records, id).map(r => r.delete)
}
