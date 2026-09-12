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
    composing: false,
    save: Saved,
    delete: Available,
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
  let updated = {
    ..record,
    document,
    origin: if record.origin == EphemeralNew {
      EphemeralNew
    } else {
      record.origin
    },
  }
  let acknowledged = documents.saved.find(document_id)
  let is_clean = acknowledged is Some(saved) && saved.text() == text
  let (documents, checkpoint, new_checkpoint) = match record.save {
    Saving(_, Some(checkpoint)) => {
      let (d, c) = revise_checkpoint(documents, checkpoint)
      (d, c, false)
    }
    Saving(_, None) => {
      let (d, c) = allocate_checkpoint(documents)
      (d, c, true)
    }
    Waiting(checkpoint) => {
      let (d, c) = revise_checkpoint(documents, checkpoint)
      (d, c, false)
    }
    Saved | Failed(_) => {
      let (d, c) = allocate_checkpoint(documents)
      (d, c, true)
    }
  }
  let checkpoint = if updated.composing && new_checkpoint {
    { ..checkpoint, maximum_armed: false, }
  } else {
    checkpoint
  }
  let in_flight = match record.save {
    Saving(_, _) => true
    _ => false
  }
  let save = if is_clean && !in_flight {
    Saved
  } else {
    match record.save {
      Saving(operation, _) => Saving(operation, Some(checkpoint))
      _ => Waiting(checkpoint)
    }
  }
  let documents = {
    ..documents,
    records: prepend_record(remove_record(documents.records, document_id), {
      ..updated,
      save,
    }),
  }
  if is_clean && !in_flight {
    (documents, [])
  } else if updated.composing {
    (documents, [])
  } else {
    (documents, checkpoint_effect(document_id, checkpoint, new_checkpoint))
  }
}

///|
fn eligible_quiet(
  documents : Documents,
  document_id : String,
  revision : Int,
) -> (Documents, Array[DocumentsDecision]) {
  match find_record(documents.records, document_id) {
    Some(record) if delete_is_active(record.delete) => (documents, [])
    Some(record) =>
      match record.save {
        Waiting(checkpoint) if checkpoint.quiet_revision == revision =>
          mark_eligible(documents, document_id, checkpoint)
        Saving(_, Some(checkpoint)) if checkpoint.quiet_revision == revision =>
          mark_eligible(documents, document_id, checkpoint)
        _ => (documents, [])
      }
    None => (documents, [])
  }
}

///|
fn eligible_maximum(
  documents : Documents,
  document_id : String,
  maximum_id : Int,
) -> (Documents, Array[DocumentsDecision]) {
  match find_record(documents.records, document_id) {
    Some(record) =>
      match record.save {
        Waiting(checkpoint) if checkpoint.maximum_id == maximum_id =>
          mark_eligible(documents, document_id, checkpoint)
        Saving(_, Some(checkpoint)) if checkpoint.maximum_id == maximum_id =>
          mark_eligible(documents, document_id, checkpoint)
        _ => (documents, [])
      }
    None => (documents, [])
  }
}

///|
fn mark_eligible(
  documents : Documents,
  document_id : String,
  checkpoint : DocumentsCheckpoint,
) -> (Documents, Array[DocumentsDecision]) {
  let checkpoint = {
    ..checkpoint,
    eligibility: DocumentsCheckpointEligibility::Eligible,
  }
  let record = find_record(documents.records, document_id).unwrap()
  match record.save {
    Waiting(_) if record.composing =>
      (
        {
          ..documents,
          records: replace_record(documents.records, document_id, r => {
            ..r,
            save: Waiting(checkpoint),
          }),
        },
        [],
      )
    Waiting(_) => {
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
    Saving(operation, _) =>
      (
        {
          ..documents,
          records: replace_record(documents.records, document_id, r => {
            ..r,
            save: Saving(operation, Some(checkpoint)),
          }),
        },
        [],
      )
    _ => (documents, [])
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
      let completed = { ..record, origin: Existing, }
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
          !record.composing => {
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
    SaveFailed(failure) =>
      match pending {
        Some(checkpoint) if checkpoint.eligibility ==
          DocumentsCheckpointEligibility::Eligible &&
          !record.composing => {
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
