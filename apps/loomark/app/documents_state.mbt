///|
fn replace_record(
  records : Array[DocumentRecord],
  document_id : String,
  update : (DocumentRecord) -> DocumentRecord,
) -> Array[DocumentRecord] {
  records.map(record => {
    if record.source.document_id() == document_id {
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
  match
    records
    .view()
    .search_by(record => record.source.document_id() == document_id) {
    Some(index) => Some(records[index])
    None => None
  }
}

///|
fn append_record(
  records : Array[DocumentRecord],
  record : DocumentRecord,
) -> Array[DocumentRecord] {
  let result = records.copy()
  result.push(record)
  result
}

///|
fn checkpoint_effect(
  document_id : String,
  checkpoint : DocumentsCheckpoint,
  new_checkpoint : Bool,
) -> Array[DocumentsDecision] {
  if checkpoint.eligibility == DocumentsCheckpointEligibility::Eligible {
    []
  } else if new_checkpoint {
    [
      DocumentsDecision::DocumentsArmQuiet(document_id, checkpoint.order),
      DocumentsDecision::DocumentsArmMaximum(document_id, checkpoint.id),
    ]
  } else {
    [DocumentsDecision::DocumentsArmQuiet(document_id, checkpoint.order)]
  }
}

///|
fn begin_save(
  record : DocumentRecord,
) -> (DocumentRecord, Array[DocumentsDecision]) {
  let operation = { source: record.source, origin: record.origin }
  (
    { ..record, save: Saving(operation, None) },
    [DocumentsDecision::DocumentsPersist(operation)],
  )
}

///|
fn initial_documents(
  snapshot : @source_repository.RepositorySnapshot,
) -> Documents {
  let records = snapshot
    .sources()
    .to_owned()
    .map(source => {
      source,
      origin: Existing,
      composing: false,
      save: Saved,
      delete: Available,
    })
  {
    snapshot,
    records,
    last_checkpoint_id: 0,
    last_delete_request: 0,
    change_order_floor: snapshot.latest_change_order(),
  }
}

///|
fn acknowledged_source(
  documents : Documents,
  document_id : String,
) -> @source_repository.SourceRecord? {
  documents.snapshot.source(document_id)
}

///|
fn is_clean(documents : Documents, record : DocumentRecord) -> Bool {
  if record.origin == New &&
    record.source.text() == "" &&
    record.source.change_order().value() == 0L &&
    acknowledged_source(documents, record.source.document_id()) is None {
    true
  } else {
    match acknowledged_source(documents, record.source.document_id()) {
      Some(source) => source == record.source
      None => false
    }
  }
}

///|
fn allocate_documents_checkpoint(
  documents : Documents,
  order : @source_repository.ChangeOrder,
) -> (Documents, DocumentsCheckpoint) {
  let id = documents.last_checkpoint_id + 1
  (
    { ..documents, last_checkpoint_id: id },
    { id, order, eligibility: DocumentsCheckpointEligibility::Deferred },
  )
}

///|
fn update_checkpoint(
  checkpoint : DocumentsCheckpoint,
  order : @source_repository.ChangeOrder,
) -> DocumentsCheckpoint {
  { ..checkpoint, order, eligibility: DocumentsCheckpointEligibility::Deferred }
}
