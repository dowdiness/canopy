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
fn begin_save(
  record : DocumentRecord,
) -> (DocumentRecord, Array[DocumentsDecision]) {
  let operation = { document: record.document, origin: record.origin }
  (
    { ..record, save: Saving(operation, None) },
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
      composing: false,
      save: Saved,
      delete: Available,
    })
  {
    saved,
    records,
    last_checkpoint_id: 0,
    last_quiet_revision: 0,
    last_delete_request: 0,
  }
}

///|
fn allocate_checkpoint(
  documents : Documents,
) -> (Documents, DocumentsCheckpoint) {
  let id = documents.last_checkpoint_id + 1
  let revision = documents.last_quiet_revision + 1
  (
    { ..documents, last_checkpoint_id: id, last_quiet_revision: revision },
    {
      maximum_id: id,
      quiet_revision: revision,
      maximum_armed: true,
      eligibility: DocumentsCheckpointEligibility::Deferred,
    },
  )
}

///|
fn revise_checkpoint(
  documents : Documents,
  checkpoint : DocumentsCheckpoint,
) -> (Documents, DocumentsCheckpoint) {
  let revision = documents.last_quiet_revision + 1
  (
    { ..documents, last_quiet_revision: revision },
    {
      ..checkpoint,
      quiet_revision: revision,
      eligibility: DocumentsCheckpointEligibility::Deferred,
    },
  )
}

///|
fn checkpoint_effect(
  document_id : String,
  checkpoint : DocumentsCheckpoint,
  new_checkpoint : Bool,
) -> Array[DocumentsDecision] {
  if checkpoint.eligibility == DocumentsCheckpointEligibility::Eligible {
    []
  } else if new_checkpoint || !checkpoint.maximum_armed {
    [
      DocumentsArmQuiet(document_id, checkpoint.quiet_revision),
      DocumentsArmMaximum(document_id, checkpoint.maximum_id),
    ]
  } else {
    [DocumentsArmQuiet(document_id, checkpoint.quiet_revision)]
  }
}
