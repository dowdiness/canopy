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
    Replica(account, document_id) =>
      saved.replica(account, document_id).map(value => value.document())
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
  // A committed Replica can be older than the active persistence lane. Submit
  // every eligible Replica edit and let that lane compare against its head.
  let is_clean = record.persistence is Source(_, _) &&
    acknowledged is Some(saved) &&
    saved.text() == text
  let in_flight = record.save is Saving(_, _)
  let (documents, replica) = if is_clean && !in_flight {
    (documents, None)
  } else {
    match record.save {
      Saving(_, Some(replica)) | Waiting(replica) =>
        (documents, Some(revise_autosave(replica)))
      Saving(_, None) | Saved | Failed(_) => {
        let (next, replica) = allocate_autosave(documents)
        (next, Some(replica))
      }
    }
  }
  let (documents, revision) = next_pending_edit(documents)
  let needs_lead = match lead_source {
    LeadSource::Available(source) => source != text
    LeadSource::Unlisted => true
  }
  let edit = if needs_lead ||
    (match replica {
      Some(replica) => replica.eligibility == AutosaveEligibility::Deferred
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
  let save = match replica {
    None => Saved
    Some(_) if is_clean && !in_flight => Saved
    Some(replica) =>
      match record.save {
        Saving(operation, _) => Saving(operation, Some(replica))
        _ => Waiting(replica)
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
  match replica {
    None => (documents, [])
    Some(_) if is_composing(edit) => (documents, [])
    Some(replica) => {
      let (replica, decisions) = autosave_effect(replica, false)
      (replace_autosave(documents, document_id, replica), decisions)
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
  maximum_id : Int,
) -> (State, Array[Effect]) {
  guard documents.records
    .view()
    .search_by(record => {
      match record.save {
        Waiting(replica) | Saving(_, Some(replica)) =>
          replica.maximum_id == maximum_id
        Saved | Saving(_, None) | Failed(_) => false
      }
    })
    is Some(index) else {
    return (documents, [])
  }
  let record = documents.records[index]
  let document_id = record.key()
  guard !delete_is_active(record.delete_phase()) else { return (documents, []) }
  match record.save {
    Waiting(replica) if replica.maximum_id == maximum_id => {
      let (record, decisions) = mark_eligible(documents.saved, record)
      (
        {
          ..documents,
          records: replace_record(documents.records, document_id, _ => record),
        },
        decisions,
      )
    }
    Saving(_, Some(replica)) if replica.maximum_id == maximum_id => {
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
    Waiting(replica) if is_composing(record.edit) =>
      (
        {
          ..record,
          save: Waiting({
            ..replica,
            eligibility: AutosaveEligibility::Eligible,
          }),
        },
        [],
      )
    Waiting(replica) =>
      begin_save(saved, {
        ..record,
        save: Waiting({ ..replica, eligibility: AutosaveEligibility::Eligible, }),
      })
    Saving(operation, Some(replica)) =>
      (
        {
          ..record,
          save: Saving(
            operation,
            Some({ ..replica, eligibility: AutosaveEligibility::Eligible, }),
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
  record : Record,
) -> (Record, Array[Effect]) {
  match record.save {
    Waiting(replica) if replica.eligibility == AutosaveEligibility::Eligible =>
      begin_save(saved, record)
    Waiting(replica) => {
      let (replica, decisions) = autosave_effect(replica, false)
      ({ ..record, save: Waiting(replica), }, decisions)
    }
    Saving(operation, Some(replica)) if replica.eligibility ==
      AutosaveEligibility::Deferred => {
      let (replica, decisions) = autosave_effect(replica, false)
      ({ ..record, save: Saving(operation, Some(replica)), }, decisions)
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
  pending : AutosaveWindow?,
  saved : @source_repository.SavedDocuments,
) -> (State, Array[Effect]) {
  let document_id = record.key()
  let persistence = match record.persistence {
    Source(EphemeralNew | ImportedNew, deletion) =>
      DocumentPersistence::Source(Existing, deletion)
    Source(Existing, _) | StartingSync(_, _) | Replica(_) => record.persistence
  }
  let completed = { ..record, persistence, }
  match record.persistence {
    Source(origin, SourceDeletePhase::Waiting(delete_operation)) => {
      let retained = match pending {
        Some(replica) if acknowledged_document(saved, record.key()) !=
          Some(record.document) => DocumentsSaveStatus::Waiting(replica)
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
    | StartingSync(_, _)
    | Replica(_) => {
      let (next, decisions) = match pending {
        Some(_) if acknowledged_document(saved, record.key()) ==
          Some(record.document) => ({ ..completed, save: Saved, }, [])
        Some(replica) if replica.eligibility == AutosaveEligibility::Eligible &&
          !is_composing(record.edit) => begin_save(saved, completed)
        Some(replica) => ({ ..completed, save: Waiting(replica), }, [])
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
  pending : AutosaveWindow?,
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
    | StartingSync(_, _)
    | Replica(_) => {
      let (next, decisions) = if acknowledged_document(
          documents.saved,
          record.key(),
        ) ==
        Some(record.document) {
        ({ ..record, save: Saved, }, [])
      } else {
        match pending {
          Some(replica) if replica.eligibility == AutosaveEligibility::Eligible &&
            !is_composing(record.edit) =>
            begin_save(documents.saved, { ..record, save: Waiting(replica), })
          Some(replica) => ({ ..record, save: Waiting(replica), }, [])
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
fn complete_replica(
  documents : State,
  write : @source_repository.ReplicaWrite,
) -> (State, Array[Effect]) {
  let saved = documents.saved.apply_replica_write(write) catch {
    _ => return (documents, [])
  }
  // Replica persistence acknowledges repository state, not the working-copy
  // Autosave window. A newer edit may have returned to this exact text while
  // another Replica write is still queued.
  ({ ..documents, saved, }, [])
}

///|
pub fn State::start_sync(
  documents : State,
  action : StartSync,
) -> (State, Array[Effect]) raise ActionError {
  guard documents.sync_start(action.key, action.account) == Ready(action) else {
    raise ExpiredAction
  }
  (
    {
      ..documents,
      records: replace_record(documents.records, action.key, current => {
        ..current,
        persistence: StartingSync(action.account, action.document),
      }),
    },
    [
      PersistReplica(
        @source_repository.DocumentReplica(action.account, action.document).promote_source(),
      ),
    ],
  )
}

///|
fn finish_sync_start_record(
  saved : @source_repository.SavedDocuments,
  record : Record,
) -> (Record, Array[Effect]) {
  match record.save {
    Waiting(replica) if replica.eligibility == AutosaveEligibility::Eligible &&
      !is_composing(record.edit) => begin_save(saved, record)
    Saved | Waiting(_) => (record, [])
    Saving(_, _) | Failed(_) => (record, [])
  }
}

///|
fn complete_sync_start(
  documents : State,
  replica : @source_repository.DocumentReplica,
  result : Result[Unit, @source_repository.ReplicaFailure],
) -> (State, Array[Effect]) {
  let source_key = Key::source(replica.document().id())
  guard find_record(documents.records, source_key) is Some(record) &&
    record.persistence is StartingSync(account, source) &&
    account == replica.account() &&
    source == replica.document() else {
    return (documents, [])
  }
  match result {
    Ok(_) => {
      guard documents.saved.apply_sync_start(replica) is Some(saved) else {
        return (documents, [])
      }
      let transitioned = {
        ..record,
        persistence: Replica(account),
        save: if record.document == replica.document() {
          Saved
        } else {
          record.save
        },
      }
      let (transitioned, effects) = finish_sync_start_record(
        saved, transitioned,
      )
      (
        {
          ..documents,
          saved,
          records: prepend_record(
            remove_record(documents.records, source_key),
            transitioned,
          ),
        },
        effects,
      )
    }
    Err(_) => {
      let restored = {
        ..record,
        persistence: Source(Existing, SourceDeletePhase::Available),
      }
      let (restored, effects) = finish_sync_start_record(
        documents.saved,
        restored,
      )
      (
        {
          ..documents,
          records: replace_record(documents.records, source_key, _ => restored),
        },
        effects,
      )
    }
  }
}
