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
      accepted_lead_source: Some(source.text()),
      pending_lead_quiet: None,
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
fn accept_lead_quiet(
  documents : Documents,
  document_id : String,
  order : @source_repository.ChangeOrder,
) -> Documents {
  match find_record(documents.records, document_id) {
    Some(record) if !delete_is_active(record.delete) &&
      record.source.change_order() == order =>
      {
        ..documents,
        records: replace_record(documents.records, document_id, r => {
          if r.composing {
            { ..r, pending_lead_quiet: Some(order) }
          } else {
            {
              ..r,
              accepted_lead_source: Some(r.source.text()),
              pending_lead_quiet: None,
            }
          }
        }),
      }
    _ => documents
  }
}

///|
fn accept_pending_lead_quiet(record : DocumentRecord) -> DocumentRecord {
  match record.pending_lead_quiet {
    Some(order) if order == record.source.change_order() && !record.composing =>
      {
        ..record,
        accepted_lead_source: Some(record.source.text()),
        pending_lead_quiet: None,
      }
    Some(_) => { ..record, pending_lead_quiet: None }
    None => record
  }
}

///|
fn Documents::lead_source(self : Self, document_id : String) -> String? {
  match find_record(self.records, document_id) {
    Some(record) => record.accepted_lead_source
    None => None
  }
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
