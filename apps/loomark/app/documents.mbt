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
      guard @source_repository.SourceRecord::new(document_id, "")
        is Some(source) else {
        return (self, [])
      }
      let record = {
        source,
        origin: New,
        composing: false,
        save: Saved,
        delete: Available,
      }
      ({ ..self, records: append_record(self.records, record) }, [])
    }
    DocumentsImported(document_id, text, observed) =>
      import_document(self, document_id, text, observed)
    DocumentsTextChanged(document_id, text, observed) =>
      apply_text(self, document_id, text, observed)
    DocumentsCompositionStarted(document_id) =>
      (
        {
          ..self,
          records: replace_record(self.records, document_id, r => {
            if delete_is_active(r.delete) {
              r
            } else {
              { ..r, composing: true }
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
      let record = { ..record, composing: false }
      match record.save {
        Waiting(checkpoint) if checkpoint.eligibility == Eligible => {
          let (next, decisions) = begin_save(record)
          (
            {
              ..self,
              records: replace_record(self.records, document_id, _ => next),
            },
            decisions,
          )
        }
        Waiting(checkpoint) =>
          (
            {
              ..self,
              records: replace_record(self.records, document_id, _ => record),
            },
            checkpoint_effect(document_id, checkpoint, true),
          )
        Saving(_, Some(checkpoint)) if checkpoint.eligibility == Deferred =>
          (
            {
              ..self,
              records: replace_record(self.records, document_id, _ => record),
            },
            checkpoint_effect(document_id, checkpoint, true),
          )
        _ =>
          (
            {
              ..self,
              records: replace_record(self.records, document_id, _ => record),
            },
            [],
          )
      }
    }
    DocumentsFeedbackReceived(feedback) =>
      match feedback {
        QuietElapsed(document_id, order) =>
          eligible_quiet(self, document_id, order)
        MaximumElapsed(document_id, id) =>
          eligible_maximum(self, document_id, id)
        SaveCompleted(operation, result) =>
          match find_record(self.records, operation.source.document_id()) {
            Some(record) if record.delete is Waiting(delete_operation) &&
              record.save is Saving(current, _) &&
              current == operation =>
              match result {
                Stored(source) if source == operation.source => {
                  guard self.snapshot.apply_acknowledged(
                      @source_repository.AcknowledgedChange::SourceStored(
                        source,
                      ),
                    )
                    is Some(snapshot) else {
                    return (self, [])
                  }
                  let save = match record.save {
                    Saving(_, Some(checkpoint)) =>
                      DocumentsSaveStatus::Waiting(checkpoint)
                    Saving(_, None) => DocumentsSaveStatus::Saved
                    _ => record.save
                  }
                  issue_delete(
                    {
                      ..self,
                      snapshot,
                      records: replace_record(
                        self.records,
                        operation.source.document_id(),
                        r => { ..r, origin: Existing, save },
                      ),
                    },
                    delete_operation,
                    save,
                  )
                }
                Failed(failure) =>
                  if record.origin == New {
                    (
                      {
                        ..self,
                        records: remove_record(
                          self.records,
                          operation.source.document_id(),
                        ),
                      },
                      [],
                    )
                  } else {
                    let save = match record.save {
                      Saving(_, Some(checkpoint)) =>
                        DocumentsSaveStatus::Waiting(checkpoint)
                      Saving(_, None) => DocumentsSaveStatus::Failed(failure)
                      _ => record.save
                    }
                    issue_delete(self, delete_operation, save)
                  }
                _ => (self, [])
              }
            _ => complete(self, operation, result)
          }
        DeleteCompleted(operation, result) =>
          finish_delete(self, operation, result)
        DeleteWatchdogElapsed(operation) => {
          guard find_record(self.records, operation.document_id) is Some(record) else {
            return (self, [])
          }
          guard record.delete is Deleting(current) && current == operation else {
            return (self, [])
          }
          (
            {
              ..self,
              records: replace_record(self.records, operation.document_id, r => {
                ..r,
                delete: Probing(operation),
              }),
            },
            [ProbeDelete(operation), ArmProbeWatchdog(operation)],
          )
        }
        DeleteProbeCompleted(operation, result) => {
          guard find_record(self.records, operation.document_id) is Some(record) else {
            return (self, [])
          }
          guard record.delete is Probing(current) && current == operation else {
            return (self, [])
          }
          match result {
            Missing =>
              finish_delete(
                self,
                operation,
                @source_repository.DeleteResult::Deleted(operation.document_id),
              )
            Present(_) | Unsupported | Failed(_) =>
              (
                {
                  ..self,
                  records: replace_record(self.records, operation.document_id, r => {
                    ..r,
                    delete: Unknown(operation),
                  }),
                },
                [],
              )
          }
        }
        DeleteProbeElapsed(operation) => {
          guard find_record(self.records, operation.document_id) is Some(record) else {
            return (self, [])
          }
          guard record.delete is Probing(current) && current == operation else {
            return (self, [])
          }
          (
            {
              ..self,
              records: replace_record(self.records, operation.document_id, r => {
                ..r,
                delete: Unknown(operation),
              }),
            },
            [],
          )
        }
      }
    DeleteConfirmed(document_id) => {
      guard find_record(self.records, document_id) is Some(record) else {
        return (self, [])
      }
      guard !delete_is_active(record.delete) else { return (self, []) }
      confirm_or_retry_delete(self, document_id)
    }
    DismissDeleteFailure(document_id) => {
      guard find_record(self.records, document_id) is Some(record) else {
        return (self, [])
      }
      guard record.delete is Failed(_, _) else { return (self, []) }
      (
        {
          ..self,
          records: replace_record(self.records, document_id, r => {
            ..r,
            delete: Available,
          }),
        },
        [],
      )
    }
    RetryDelete(document_id) => {
      guard find_record(self.records, document_id) is Some(record) else {
        return (self, [])
      }
      guard record.delete is Failed(_, _) else { return (self, []) }
      confirm_or_retry_delete(self, document_id)
    }
    DocumentsRetrySave(document_id) => {
      guard find_record(self.records, document_id) is Some(record) else {
        return (self, [])
      }
      match record.save {
        Failed(_) if !record.composing && !delete_is_active(record.delete) => {
          let (next, decisions) = begin_save(record)
          (
            {
              ..self,
              records: replace_record(self.records, document_id, _ => next),
            },
            decisions,
          )
        }
        _ => (self, [])
      }
    }
    DocumentsVisibilityFlush(document_id) => {
      guard find_record(self.records, document_id) is Some(record) else {
        return (self, [])
      }
      match record.save {
        Waiting(_) if !record.composing && !delete_is_active(record.delete) => {
          let (next, decisions) = begin_save(record)
          (
            {
              ..self,
              records: replace_record(self.records, document_id, _ => next),
            },
            decisions,
          )
        }
        _ => (self, [])
      }
    }
  }
}

///|
fn Documents::is_composing(self : Self, document_id : String) -> Bool {
  find_record(self.records, document_id).map(r => r.composing).unwrap_or(false)
}

///|
fn Documents::fallback_document(self : Self, excluding : String) -> String? {
  let candidates = self.records.filter(record => {
    let id = record.source.document_id()
    let promoted_new = record.origin == New &&
      (record.source.text() != "" || record.source.change_order().value() > 0L)
    id != excluding &&
    !delete_is_active(record.delete) &&
    (record.origin == Existing || promoted_new)
  })
  let ordered = candidates.copy()
  ordered.sort_by((left, right) => {
    let by_newest = right.source
      .change_order()
      .value()
      .compare(left.source.change_order().value())
    if by_newest != 0 {
      by_newest
    } else {
      left.source.document_id().lexical_compare(right.source.document_id())
    }
  })
  ordered.get(0).map(record => record.source.document_id())
}

///|
fn Documents::snapshot(self : Self) -> @source_repository.RepositorySnapshot {
  self.snapshot
}

///|
fn Documents::current_sources(
  self : Self,
) -> Array[@source_repository.SourceRecord] {
  self.records.map(record => record.source)
}

///|
fn Documents::text(self : Self, document_id : String) -> String? {
  find_record(self.records, document_id).map(r => r.source.text())
}

///|
fn Documents::save_status(
  self : Self,
  document_id : String,
) -> DocumentsSaveStatus? {
  find_record(self.records, document_id).map(r => r.save)
}

///|
/// Deletion state for application wiring and status presentation.
fn Documents::delete_status(
  self : Self,
  document_id : String,
) -> DocumentsDeletePhase? {
  find_record(self.records, document_id).map(r => r.delete)
}
