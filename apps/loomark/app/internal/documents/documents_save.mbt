///|
fn import_document(
  documents : State,
  document_id : @source_repository.DocumentId,
  text : String,
) -> (State, Array[Effect]) {
  let key = Key::source(document_id)
  guard find_record(documents.records, key) is None else {
    return (documents, [])
  }
  let document = @source_repository.Document::create(document_id, text)
  let record = {
    persistence: Source(ImportedNew, SourceDeletePhase::Available),
    document,
    edit: Idle,
    save: Saved,
    lead_source: LeadSource::Available(text),
  }
  let (record, effects) = begin_save(documents.saved, record)
  (
    { ..documents, records: prepend_record(documents.records, record), },
    effects,
  )
}

///|
fn acknowledged_document(
  saved : @source_repository.SavedDocuments,
  key : Key,
) -> @source_repository.Document? {
  match key {
    Source(document_id) => saved.find(document_id)
    Checkpoint(account, document_id) =>
      saved.checkpoint(account, document_id).map(value => value.document())
  }
}

///|
fn apply_text(
  documents : State,
  document_id : Key,
  text : String,
) -> (State, Array[Effect]) {
  guard find_record(documents.records, document_id) is Some(record) else {
    return (documents, [])
  }
  guard !delete_is_active(record.delete_phase()) &&
    record.document.text() != text else {
    return (documents, [])
  }
  let document = record.document.update(text)
  let lead_source = match record.lead_source {
    LeadSource::Unlisted => LeadSource::Available(text)
    source => source
  }
  let acknowledged = acknowledged_document(documents.saved, record.key())
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
  documents : State,
  document_id : Key,
  revision : Int,
) -> (State, Array[Effect]) {
  guard find_record(documents.records, document_id) is Some(record) else {
    return (documents, [])
  }
  guard !delete_is_active(record.delete_phase()) else { return (documents, []) }
  match record.edit {
    Waiting(current) if current == revision => {
      let (record, decisions) = accept_pending(documents.saved, record)
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
  documents : State,
  document_id : Key,
  maximum_id : Int,
) -> (State, Array[Effect]) {
  guard find_record(documents.records, document_id) is Some(record) else {
    return (documents, [])
  }
  guard !delete_is_active(record.delete_phase()) else { return (documents, []) }
  match record.save {
    Waiting(checkpoint) if checkpoint.maximum_id == maximum_id => {
      let (record, decisions) = mark_eligible(documents.saved, record)
      (
        {
          ..documents,
          records: replace_record(documents.records, document_id, _ => record),
        },
        decisions,
      )
    }
    Saving(_, Some(checkpoint)) if checkpoint.maximum_id == maximum_id => {
      let (record, decisions) = mark_eligible(documents.saved, record)
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
  saved : @source_repository.SavedDocuments,
  record : Record,
) -> (Record, Array[Effect]) {
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
      begin_save(saved, {
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
  saved : @source_repository.SavedDocuments,
  record : Record,
) -> (Record, Array[Effect]) {
  let record = {
    ..record,
    edit: Idle,
    lead_source: LeadSource::Available(record.document.text()),
  }
  mark_eligible(saved, record)
}

///|
fn finish_composition(
  saved : @source_repository.SavedDocuments,
  document_id : Key,
  record : Record,
) -> (Record, Array[Effect]) {
  match record.save {
    Waiting(checkpoint) if checkpoint.eligibility ==
      DocumentsCheckpointEligibility::Eligible => begin_save(saved, record)
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
  documents : State,
  record : Record,
  origin : LocalDocumentOrigin,
  delete_operation : DeleteOperation,
  retained : DocumentsSaveStatus,
  saved : @source_repository.SavedDocuments,
) -> (State, Array[Effect]) {
  let document_id = record.key()
  let (deleting, decision) = issue_delete_record(
    record, origin, delete_operation, retained,
  )
  (
    {
      ..documents,
      saved,
      records: replace_record(documents.records, document_id, _ => deleting),
    },
    [decision],
  )
}

///|
fn complete_stored(
  documents : State,
  record : Record,
  pending : DocumentsCheckpoint?,
  saved : @source_repository.SavedDocuments,
) -> (State, Array[Effect]) {
  let document_id = record.key()
  let persistence = match record.persistence {
    Source(EphemeralNew | ImportedNew, deletion) =>
      DocumentPersistence::Source(Existing, deletion)
    Source(Existing, _) | Checkpoint(_) => record.persistence
  }
  let completed = { ..record, persistence, }
  match record.persistence {
    Source(origin, SourceDeletePhase::Waiting(delete_operation)) => {
      let retained = match pending {
        Some(checkpoint) if acknowledged_document(saved, record.key()) !=
          Some(record.document) => DocumentsSaveStatus::Waiting(checkpoint)
        _ => Saved
      }
      complete_waiting_delete(
        documents, completed, origin, delete_operation, retained, saved,
      )
    }
    Source(
      _,
      SourceDeletePhase::Deleting(_)
      | SourceDeletePhase::Available
      | SourceDeletePhase::Failed(_, _)
    )
    | Checkpoint(_) => {
      let (next, decisions) = match pending {
        Some(_) if acknowledged_document(saved, record.key()) ==
          Some(record.document) => ({ ..completed, save: Saved, }, [])
        Some(checkpoint) if checkpoint.eligibility ==
          DocumentsCheckpointEligibility::Eligible &&
          !is_composing(record.edit) => begin_save(saved, completed)
        Some(checkpoint) => ({ ..completed, save: Waiting(checkpoint), }, [])
        None => ({ ..completed, save: Saved, }, [])
      }
      (
        {
          ..documents,
          saved,
          records: replace_record(documents.records, document_id, _ => next),
        },
        decisions,
      )
    }
  }
}

///|
fn complete_failed(
  documents : State,
  record : Record,
  pending : DocumentsCheckpoint?,
  failure : @source_repository.SaveFailure,
) -> (State, Array[Effect]) {
  let document_id = record.key()
  match record.persistence {
    Source(origin, SourceDeletePhase::Waiting(delete_operation)) =>
      if acknowledged_document(documents.saved, record.key()) is Some(_) {
        complete_waiting_delete(
          documents,
          record,
          origin,
          delete_operation,
          Failed(failure),
          documents.saved,
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
    Source(
      _,
      SourceDeletePhase::Deleting(_)
      | SourceDeletePhase::Available
      | SourceDeletePhase::Failed(_, _)
    )
    | Checkpoint(_) => {
      let (next, decisions) = if acknowledged_document(
          documents.saved,
          record.key(),
        ) ==
        Some(record.document) {
        ({ ..record, save: Saved, }, [])
      } else {
        match pending {
          Some(checkpoint) if checkpoint.eligibility ==
            DocumentsCheckpointEligibility::Eligible &&
            !is_composing(record.edit) =>
            begin_save(documents.saved, { ..record, save: Waiting(checkpoint), })
          Some(checkpoint) => ({ ..record, save: Waiting(checkpoint), }, [])
          None => ({ ..record, save: Failed(failure), }, [])
        }
      }
      (
        {
          ..documents,
          records: replace_record(documents.records, document_id, _ => next),
        },
        decisions,
      )
    }
  }
}

///|
fn complete(
  documents : State,
  operation : SaveOperation,
  result : @source_repository.SaveResult,
) -> (State, Array[Effect]) {
  let document_id = operation.key
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

///|
fn checkpoint_failure(
  failure : @source_repository.CheckpointFailure,
) -> @source_repository.SaveFailure {
  match failure {
    InvalidCheckpoint => @source_repository.SaveFailure::InvalidSource
    StorageUnavailable => @source_repository.SaveFailure::StorageUnavailable
    QuotaExceeded => @source_repository.SaveFailure::QuotaExceeded
    WriteFailed => @source_repository.SaveFailure::WriteFailed
  }
}

///|
fn complete_checkpoint(
  documents : State,
  result : @source_repository.CheckpointResult,
) -> (State, Array[Effect]) {
  match result {
    CheckpointStored(checkpoint) => {
      let saved = documents.saved.apply_checkpoint(checkpoint) catch {
        _ => return (documents, [])
      }
      let documents = { ..documents, saved, }
      let key = Key::checkpoint(
        checkpoint.account(),
        checkpoint.document().id(),
      )
      let document_id = key
      guard find_record(documents.records, document_id) is Some(record) &&
        record.save is Saving(operation, pending) &&
        operation.key == key &&
        operation.document == checkpoint.document() else {
        return (documents, [])
      }
      complete_stored(documents, record, pending, saved)
    }
    CheckpointFailed(checkpoint, failure) => {
      let key = Key::checkpoint(
        checkpoint.account(),
        checkpoint.document().id(),
      )
      let document_id = key
      guard find_record(documents.records, document_id) is Some(record) &&
        record.save is Saving(operation, pending) &&
        operation.key == key &&
        operation.document == checkpoint.document() else {
        return (documents, [])
      }
      complete_failed(documents, record, pending, checkpoint_failure(failure))
    }
  }
}
