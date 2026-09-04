///|
fn import_document(
  documents : Documents,
  document_id : String,
  text : String,
  observed : @source_repository.ChangeOrder,
) -> (Documents, Array[DocumentsDecision]) {
  guard find_record(documents.records, document_id) is None else {
    return (documents, [])
  }
  match documents.change_order_floor.advance(observed) {
    None => (documents, [])
    Some(order) => {
      guard @source_repository.SourceRecord::new(
          document_id,
          text,
          change_order=order,
        )
        is Some(source) else {
        return (documents, [])
      }
      let (record, decisions) = begin_save({
        source,
        origin: New,
        composing: false,
        save: Saved,
        delete: Available,
      })
      (
        {
          ..documents,
          records: append_record(documents.records, record),
          change_order_floor: order,
        },
        decisions,
      )
    }
  }
}

///|
fn apply_text(
  documents : Documents,
  document_id : String,
  text : String,
  observed : @source_repository.ChangeOrder,
) -> (Documents, Array[DocumentsDecision]) {
  guard find_record(documents.records, document_id) is Some(record) else {
    return (documents, [])
  }
  guard !delete_is_active(record.delete) else { return (documents, []) }
  guard record.source.text() != text else { return (documents, []) }
  guard documents.change_order_floor.advance(observed) is Some(order) else {
    let failed = {
      ..record,
      save: Failed(@source_repository.SaveFailure::ChangeOrderExhausted),
    }
    return (
      {
        ..documents,
        records: replace_record(documents.records, document_id, _ => failed),
      },
      [],
    )
  }
  let source = @source_repository.SourceRecord::new(
    document_id,
    text,
    change_order=order,
  ).unwrap()
  let updated = { ..record, source, }
  let documents = { ..documents, change_order_floor: order }
  match record.save {
    Saving(operation, pending) => {
      let (documents, checkpoint, new_checkpoint) = match pending {
        Some(checkpoint) =>
          (documents, update_checkpoint(checkpoint, order), false)
        None => {
          let (documents, checkpoint) = allocate_documents_checkpoint(
            documents, order,
          )
          (documents, checkpoint, true)
        }
      }
      (
        {
          ..documents,
          records: replace_record(documents.records, document_id, _ => {
            ..updated,
            save: Saving(operation, Some(checkpoint)),
          }),
        },
        if record.composing {
          []
        } else {
          checkpoint_effect(document_id, checkpoint, new_checkpoint)
        },
      )
    }
    Waiting(checkpoint) => {
      let checkpoint = update_checkpoint(checkpoint, order)
      (
        {
          ..documents,
          records: replace_record(documents.records, document_id, _ => {
            ..updated,
            save: Waiting(checkpoint),
          }),
        },
        if record.composing {
          []
        } else {
          checkpoint_effect(document_id, checkpoint, false)
        },
      )
    }
    Saved | Failed(_) =>
      if is_clean(documents, updated) {
        (
          {
            ..documents,
            records: replace_record(documents.records, document_id, _ => {
              ..updated,
              save: Saved,
            }),
          },
          [],
        )
      } else {
        let (documents, checkpoint) = allocate_documents_checkpoint(
          documents, order,
        )
        let decisions = if record.composing {
          []
        } else {
          checkpoint_effect(document_id, checkpoint, true)
        }
        (
          {
            ..documents,
            records: replace_record(documents.records, document_id, _ => {
              ..updated,
              save: Waiting(checkpoint),
            }),
          },
          decisions,
        )
      }
  }
}

///|
fn eligible_quiet(
  documents : Documents,
  document_id : String,
  order : @source_repository.ChangeOrder,
) -> (Documents, Array[DocumentsDecision]) {
  match find_record(documents.records, document_id) {
    Some(record) if delete_is_active(record.delete) => (documents, [])
    Some(record) =>
      match record.save {
        Waiting(checkpoint) if checkpoint.order == order =>
          mark_eligible(documents, document_id, checkpoint)
        Saving(_, Some(checkpoint)) if checkpoint.order == order =>
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
  id : Int,
) -> (Documents, Array[DocumentsDecision]) {
  match find_record(documents.records, document_id) {
    Some(record) if delete_is_active(record.delete) => (documents, [])
    Some(record) =>
      match record.save {
        Waiting(checkpoint) if checkpoint.id == id =>
          mark_eligible(documents, document_id, checkpoint)
        Saving(_, Some(checkpoint)) if checkpoint.id == id =>
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
          records: replace_record(documents.records, document_id, _ => {
            ..record,
            save: Waiting(checkpoint),
          }),
        },
        [],
      )
    Waiting(_) => {
      let (next, decisions) = begin_save({ ..record, save: Waiting(checkpoint) })
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
          records: replace_record(documents.records, document_id, _ => {
            ..record,
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
  let document_id = operation.source.document_id()
  guard find_record(documents.records, document_id) is Some(record) else {
    return (documents, [])
  }
  guard record.save is Saving(current, pending) && current == operation else {
    return (documents, [])
  }
  match result {
    Stored(source) => {
      guard source == operation.source else { return (documents, []) }
      guard documents.snapshot.apply_acknowledged(
          @source_repository.AcknowledgedChange::SourceStored(source),
        )
        is Some(snapshot) else {
        return (documents, [])
      }
      let completed = { ..record, origin: Existing }
      let (next_record, decisions) = match pending {
        Some(checkpoint) if checkpoint.eligibility == Eligible &&
          !record.composing => begin_save(completed)
        Some(checkpoint) => ({ ..completed, save: Waiting(checkpoint) }, [])
        None => ({ ..completed, source: operation.source, save: Saved }, [])
      }
      (
        {
          snapshot,
          records: replace_record(documents.records, document_id, fn(_) {
            next_record
          }),
          last_checkpoint_id: documents.last_checkpoint_id,
          last_delete_request: documents.last_delete_request,
          change_order_floor: documents.change_order_floor,
        },
        decisions,
      )
    }
    Failed(failure) =>
      match pending {
        Some(checkpoint) if checkpoint.eligibility == Eligible &&
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
