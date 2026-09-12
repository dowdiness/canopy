///|
fn import_document(
  documents : Documents,
  document_id : String,
  text : String,
) -> (Documents, Array[DocumentsDecision]) {
  guard find_record(documents.records, document_id) is None else {
    return (documents, [])
  }
  let document = @source_repository.Document::create(document_id, text) catch {
    _ => abort("invalid generated document id")
  }
  let record = {
    document,
    origin: ImportedNew,
    edit: Idle,
    save: Saved,
    lead_source: LeadSource::Available(text),
    delete: DocumentsDeletePhase::Available,
  }
  let (record, decisions) = begin_save(record)
  (
    { ..documents, records: prepend_record(documents.records, record), },
    decisions,
  )
}

///|
fn apply_text(
  documents : Documents,
  document_id : String,
  text : String,
) -> (Documents, Array[DocumentsDecision]) {
  guard find_record(documents.records, document_id) is Some(record) else {
    return (documents, [])
  }
  guard !delete_is_active(record.delete) && record.document.text() != text else {
    return (documents, [])
  }
  let document = record.document.update(text)
  let lead_source = match record.lead_source {
    LeadSource::Unlisted => LeadSource::Available(text)
    source => source
  }
  let acknowledged = documents.saved.find(document_id)
  let is_clean = acknowledged is Some(saved) && saved.text() == text
  let in_flight = record.save is Saving(_, _)
  let (documents, checkpoint) = if is_clean && !in_flight {
    (documents, None)
  } else {
    match record.save {
      Saving(_, Some(checkpoint)) | Waiting(checkpoint) =>
        (documents, Some(revise_checkpoint(checkpoint)))
      Saving(_, None) | Saved | Failed(_) => {
        let (next, checkpoint) = allocate_checkpoint(documents)
        (next, Some(checkpoint))
      }
    }
  }
  let (documents, revision) = next_pending_edit(documents)
  let needs_lead = match lead_source {
    LeadSource::Available(source) => source != text
    LeadSource::Unlisted => true
  }
  let edit = if needs_lead ||
    (match checkpoint {
      Some(checkpoint) =>
        checkpoint.eligibility == DocumentsCheckpointEligibility::Deferred
      None => false
    }) {
    match record.edit {
      ComposingIdle | ComposingWaiting(_) | ComposingReady =>
        ComposingWaiting(revision)
      _ => EditState::Waiting(revision)
    }
  } else {
    match record.edit {
      ComposingIdle | ComposingWaiting(_) | ComposingReady => ComposingIdle
      _ => EditState::Idle
    }
  }
  let save = match checkpoint {
    None => Saved
    Some(_) if is_clean && !in_flight => Saved
    Some(checkpoint) =>
      match record.save {
        Saving(operation, _) => Saving(operation, Some(checkpoint))
        _ => Waiting(checkpoint)
      }
  }
  let record = { ..record, document, lead_source, edit, save, }
  let documents = {
    ..documents,
    records: prepend_record(
      remove_record(documents.records, document_id),
      record,
    ),
  }
  match checkpoint {
    None => (documents, [])
    Some(_) if is_composing(edit) => (documents, [])
    Some(checkpoint) => {
      let (checkpoint, decisions) = checkpoint_effect(
        document_id, checkpoint, false,
      )
      (replace_checkpoint(documents, document_id, checkpoint), decisions)
    }
  }
}

///|
fn apply_pending_edit(
  documents : Documents,
  document_id : String,
  revision : Int,
) -> (Documents, Array[DocumentsDecision]) {
  guard find_record(documents.records, document_id) is Some(record) else {
    return (documents, [])
  }
  guard !delete_is_active(record.delete) else { return (documents, []) }
  match record.edit {
    Waiting(current) if current == revision => {
      let (record, decisions) = accept_pending(record)
      (
        {
          ..documents,
          records: replace_record(documents.records, document_id, _ => record),
        },
        decisions,
      )
    }
    ComposingWaiting(current) if current == revision =>
      (
        {
          ..documents,
          records: replace_record(documents.records, document_id, r => {
            ..r,
            edit: ComposingReady,
          }),
        },
        [],
      )
    ComposingReady => (documents, [])
    _ => (documents, [])
  }
}

///|
fn eligible_maximum(
  documents : Documents,
  document_id : String,
  maximum_id : Int,
) -> (Documents, Array[DocumentsDecision]) {
  guard find_record(documents.records, document_id) is Some(record) else {
    return (documents, [])
  }
  guard !delete_is_active(record.delete) else { return (documents, []) }
  match record.save {
    Waiting(checkpoint) if checkpoint.maximum_id == maximum_id => {
      let (record, decisions) = mark_eligible(record)
      (
        {
          ..documents,
          records: replace_record(documents.records, document_id, _ => record),
        },
        decisions,
      )
    }
    Saving(_, Some(checkpoint)) if checkpoint.maximum_id == maximum_id => {
      let (record, decisions) = mark_eligible(record)
      (
        {
          ..documents,
          records: replace_record(documents.records, document_id, _ => record),
        },
        decisions,
      )
    }
    _ => (documents, [])
  }
}

///|
fn mark_eligible(
  record : DocumentRecord,
) -> (DocumentRecord, Array[DocumentsDecision]) {
  match record.save {
    Waiting(checkpoint) if is_composing(record.edit) =>
      (
        {
          ..record,
          save: Waiting({
            ..checkpoint,
            eligibility: DocumentsCheckpointEligibility::Eligible,
          }),
        },
        [],
      )
    Waiting(checkpoint) =>
      begin_save({
        ..record,
        save: Waiting({
          ..checkpoint,
          eligibility: DocumentsCheckpointEligibility::Eligible,
        }),
      })
    Saving(operation, Some(checkpoint)) =>
      (
        {
          ..record,
          save: Saving(
            operation,
            Some({
              ..checkpoint,
              eligibility: DocumentsCheckpointEligibility::Eligible,
            }),
          ),
        },
        [],
      )
    Saved | Failed(_) | Saving(_, None) => (record, [])
  }
}

///|
fn accept_pending(
  record : DocumentRecord,
) -> (DocumentRecord, Array[DocumentsDecision]) {
  let record = {
    ..record,
    edit: Idle,
    lead_source: LeadSource::Available(record.document.text()),
  }
  mark_eligible(record)
}

///|
fn finish_composition(
  document_id : String,
  record : DocumentRecord,
) -> (DocumentRecord, Array[DocumentsDecision]) {
  match record.save {
    Waiting(checkpoint) if checkpoint.eligibility ==
      DocumentsCheckpointEligibility::Eligible => begin_save(record)
    Waiting(checkpoint) => {
      let (checkpoint, decisions) = checkpoint_effect(
        document_id, checkpoint, false,
      )
      ({ ..record, save: Waiting(checkpoint), }, decisions)
    }
    Saving(operation, Some(checkpoint)) if checkpoint.eligibility ==
      DocumentsCheckpointEligibility::Deferred => {
      let (checkpoint, decisions) = checkpoint_effect(
        document_id, checkpoint, false,
      )
      ({ ..record, save: Saving(operation, Some(checkpoint)), }, decisions)
    }
    _ => (record, [])
  }
}

///|
fn complete_waiting_delete(
  documents : Documents,
  record : DocumentRecord,
  delete_operation : DeleteOperation,
  retained : DocumentsSaveStatus,
  saved : @source_repository.SavedDocuments?,
) -> (Documents, Array[DocumentsDecision]) {
  let document_id = record.document.id()
  let (deleting, decision) = issue_delete_record(
    record, delete_operation, retained,
  )
  (
    {
      ..documents,
      saved: saved.unwrap_or(documents.saved),
      records: replace_record(documents.records, document_id, _ => deleting),
    },
    [decision],
  )
}

///|
fn complete_stored(
  documents : Documents,
  record : DocumentRecord,
  pending : DocumentsCheckpoint?,
  saved : @source_repository.SavedDocuments,
) -> (Documents, Array[DocumentsDecision]) {
  let document_id = record.document.id()
  let completed = { ..record, origin: Existing, }
  match record.delete {
    Waiting(delete_operation) => {
      let retained = match pending {
        Some(checkpoint) if saved.find(document_id) != Some(record.document) =>
          DocumentsSaveStatus::Waiting(checkpoint)
        _ => Saved
      }
      complete_waiting_delete(
        documents,
        completed,
        delete_operation,
        retained,
        Some(saved),
      )
    }
    Deleting(_) | Available | Failed(_, _) =>
      match pending {
        Some(_) if saved.find(document_id) == Some(record.document) =>
          (
            {
              ..documents,
              saved,
              records: replace_record(documents.records, document_id, _ => {
                ..completed,
                save: Saved,
              }),
            },
            [],
          )
        Some(checkpoint) if checkpoint.eligibility ==
          DocumentsCheckpointEligibility::Eligible &&
          !is_composing(record.edit) => {
          let (next, decisions) = begin_save(completed)
          (
            {
              ..documents,
              saved,
              records: replace_record(documents.records, document_id, _ => next),
            },
            decisions,
          )
        }
        Some(checkpoint) =>
          (
            {
              ..documents,
              saved,
              records: replace_record(documents.records, document_id, _ => {
                ..completed,
                save: Waiting(checkpoint),
              }),
            },
            [],
          )
        None =>
          (
            {
              ..documents,
              saved,
              records: replace_record(documents.records, document_id, _ => {
                ..completed,
                save: Saved,
              }),
            },
            [],
          )
      }
  }
}

///|
fn complete_failed(
  documents : Documents,
  record : DocumentRecord,
  pending : DocumentsCheckpoint?,
  failure : @source_repository.SaveFailure,
) -> (Documents, Array[DocumentsDecision]) {
  let document_id = record.document.id()
  match record.delete {
    Waiting(delete_operation) =>
      if documents.saved.find(document_id) is Some(_) {
        complete_waiting_delete(
          documents,
          record,
          delete_operation,
          Failed(failure),
          None,
        )
      } else {
        (
          {
            ..documents,
            records: remove_record(documents.records, document_id),
          },
          [],
        )
      }
    Deleting(_) | Available | Failed(_, _) =>
      match pending {
        Some(checkpoint) if checkpoint.eligibility ==
          DocumentsCheckpointEligibility::Eligible &&
          !is_composing(record.edit) => {
          let (next, decisions) = begin_save({
            ..record,
            save: Waiting(checkpoint),
          })
          (
            {
              ..documents,
              records: replace_record(documents.records, document_id, _ => next),
            },
            decisions,
          )
        }
        Some(checkpoint) =>
          (
            {
              ..documents,
              records: replace_record(documents.records, document_id, _ => {
                ..record,
                save: Waiting(checkpoint),
              }),
            },
            [],
          )
        None =>
          (
            {
              ..documents,
              records: replace_record(documents.records, document_id, _ => {
                ..record,
                save: Failed(failure),
              }),
            },
            [],
          )
      }
  }
}

///|
fn complete(
  documents : Documents,
  operation : SaveOperation,
  result : @source_repository.SaveResult,
) -> (Documents, Array[DocumentsDecision]) {
  let document_id = operation.document.id()
  guard find_record(documents.records, document_id) is Some(record) else {
    return (documents, [])
  }
  guard record.save is Saving(current, pending) && current == operation else {
    return (documents, [])
  }
  match result {
    Stored(document) => {
      guard document == operation.document else { return (documents, []) }
      guard documents.saved.apply(
          @source_repository.RepositoryChange::Stored(document),
        )
        is Some(saved) else {
        return (documents, [])
      }
      complete_stored(documents, record, pending, saved)
    }
    SaveFailed(failure) => complete_failed(documents, record, pending, failure)
  }
}
