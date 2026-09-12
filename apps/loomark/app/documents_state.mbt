///|
fn replace_record(
  records : Array[DocumentRecord],
  document_id : String,
  update : (DocumentRecord) -> DocumentRecord,
) -> Array[DocumentRecord] {
  records.map(record => {
    if record.document.id() == document_id {
      update(record)
    } else {
      record
    }
  })
}

///|
fn find_record(
  records : Array[DocumentRecord],
  document_id : String,
) -> DocumentRecord? {
  records
  .view()
  .search_by(record => record.document.id() == document_id)
  .map(i => records[i])
}

///|

///|
fn prepend_record(
  records : Array[DocumentRecord],
  record : DocumentRecord,
) -> Array[DocumentRecord] {
  [record] + records
}

///|
fn is_composing(edit : EditState) -> Bool {
  match edit {
    ComposingIdle | ComposingWaiting(_) | ComposingReady => true
    Idle | Waiting(_) => false
  }
}

///|
fn replace_checkpoint(
  documents : Documents,
  document_id : String,
  checkpoint : DocumentsCheckpoint,
) -> Documents {
  {
    ..documents,
    records: replace_record(documents.records, document_id, r => {
      let save = match r.save {
        DocumentsSaveStatus::Waiting(_) =>
          DocumentsSaveStatus::Waiting(checkpoint)
        DocumentsSaveStatus::Saving(operation, _) =>
          DocumentsSaveStatus::Saving(operation, Some(checkpoint))
        Saved | Failed(_) => r.save
      }
      { ..r, save, }
    }),
  }
}

///|
fn begin_save(
  record : DocumentRecord,
) -> (DocumentRecord, Array[DocumentsDecision]) {
  let operation = { document: record.document, origin: record.origin, }
  (
    { ..record, save: Saving(operation, None), },
    [DocumentsDecision::DocumentsPersist(operation)],
  )
}

///|
fn initial_documents(saved : @source_repository.SavedDocuments) -> Documents {
  let records = saved
    .all()
    .to_owned()
    .map(document => {
      document,
      origin: Existing,
      edit: Idle,
      save: Saved,
      lead_source: Available(document.text()),
      delete: Available,
    })
  {
    saved,
    records,
    last_checkpoint_id: 0,
    last_pending_edit_revision: 0,
    last_delete_request: 0,
  }
}

///|
fn allocate_checkpoint(
  documents : Documents,
) -> (Documents, DocumentsCheckpoint) {
  let id = documents.last_checkpoint_id + 1
  (
    { ..documents, last_checkpoint_id: id, },
    {
      maximum_id: id,
      maximum_armed: false,
      eligibility: DocumentsCheckpointEligibility::Deferred,
    },
  )
}

///|
fn revise_checkpoint(checkpoint : DocumentsCheckpoint) -> DocumentsCheckpoint {
  { ..checkpoint, eligibility: DocumentsCheckpointEligibility::Deferred, }
}

///|
fn next_pending_edit(documents : Documents) -> (Documents, Int) {
  let revision = documents.last_pending_edit_revision + 1
  ({ ..documents, last_pending_edit_revision: revision, }, revision)
}

///|
fn checkpoint_effect(
  document_id : String,
  checkpoint : DocumentsCheckpoint,
  rearm : Bool,
) -> (DocumentsCheckpoint, Array[DocumentsDecision]) {
  if checkpoint.eligibility == DocumentsCheckpointEligibility::Eligible ||
    (!rearm && checkpoint.maximum_armed) {
    (checkpoint, [])
  } else {
    (
      { ..checkpoint, maximum_armed: true, },
      [DocumentsArmMaximum(document_id, checkpoint.maximum_id)],
    )
  }
}
