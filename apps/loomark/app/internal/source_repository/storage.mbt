///|
let document_store : @indexed_db.Store = @indexed_db.Store::Store(
  "loomark", 1, "documents",
)

///|
extern "js" fn random_uuid_available() -> Bool =
  #| () => typeof globalThis.crypto?.randomUUID === "function"

///|
extern "js" fn random_uuid() -> String =
  #| () => globalThis.crypto.randomUUID()

///|
pub(all) enum OpenFailure {
  StorageUnavailable
  ReadFailed
} derive(Eq, Debug)

///|
pub(all) enum SaveFailure {
  InvalidSource
  StorageUnavailable
  QuotaExceeded
  WriteFailed
} derive(Eq, Debug)

///|
pub(all) enum CreateFailure {
  DocumentIdentityUnavailable
} derive(Eq, Debug)

///|
pub(all) enum DeleteFailure {
  InvalidSource
  StorageUnavailable
  QuotaExceeded
  WriteFailed
} derive(Eq, Debug)

///|
pub(all) enum OpenResult {
  Ready(SavedDocuments, Document?)
  OpenFailed(OpenFailure)
} derive(Eq, Debug)

///|
pub(all) enum SaveResult {
  Stored(Document)
  SaveFailed(SaveFailure)
} derive(Eq, Debug)

///|
pub(all) enum CreateResult {
  Created(String)
  CreateFailed(CreateFailure)
} derive(Eq, Debug)

///|
pub(all) enum DeleteResult {
  Deleted(String)
  DeleteFailed(DeleteFailure)
} derive(Eq, Debug)

///|
pub(all) enum CheckpointFailure {
  InvalidCheckpoint
  StorageUnavailable
  QuotaExceeded
  WriteFailed
} derive(Eq, Debug)

///|
pub(all) enum CheckpointResult {
  CheckpointStored(SyncCheckpoint)
  CheckpointFailed(SyncCheckpoint, CheckpointFailure)
} derive(Eq, Debug)

///|
pub fn open(msg : @cmd.Emit[OpenResult]) -> @cmd.Cmd {
  document_store.entries(entries => {
    match entries {
      Ok(entries) => {
        let (saved, selected) = reconcile_scan(entries)
        msg(Ready(saved, selected))
      }
      Err(@indexed_db.ReadError::Unavailable) =>
        msg(OpenFailed(OpenFailure::StorageUnavailable))
      Err(Failed(_, _)) => msg(OpenFailed(OpenFailure::ReadFailed))
    }
  })
}

///|
fn checkpoint_failure(outcome : @indexed_db.WriteError) -> CheckpointFailure {
  match outcome {
    @indexed_db.WriteError::Unavailable => CheckpointFailure::StorageUnavailable
    @indexed_db.WriteError::QuotaExceeded => CheckpointFailure::QuotaExceeded
    Failed(_, _) => CheckpointFailure::WriteFailed
  }
}

///|
fn checkpoint_result(
  checkpoint : SyncCheckpoint,
  outcome : @indexed_db.WriteError?,
) -> CheckpointResult {
  match outcome {
    None => CheckpointStored(checkpoint)
    Some(failure) => CheckpointFailed(checkpoint, checkpoint_failure(failure))
  }
}

///|
pub fn enroll_for_sync(
  saved : SavedDocuments,
  account : AccountId,
  document : Document,
  msg : @cmd.Emit[CheckpointResult],
) -> @cmd.Cmd {
  let checkpoint = SyncCheckpoint::enroll(account, document)
  let key = sync_key(account, document.id())
  guard saved.find(document.id()) == Some(document) && !saved.observed_sync(key) else {
    return msg(
      CheckpointFailed(checkpoint, CheckpointFailure::InvalidCheckpoint),
    )
  }
  document_store.apply(
    [
      @indexed_db.Mutation::Set(key, encode_checkpoint(checkpoint)),
      @indexed_db.Mutation::Delete(SOURCE_KEY_PREFIX + document.id()),
    ],
    outcome => msg(checkpoint_result(checkpoint, outcome)),
  )
}

///|
fn checkpoint_mutations(write : CheckpointWrite) -> Array[@indexed_db.Mutation] {
  let checkpoint = write.checkpoint()
  let checkpoint_mutation = @indexed_db.Mutation::Set(
    sync_key(checkpoint.account, checkpoint.document.id()),
    encode_checkpoint(checkpoint),
  )
  match write {
    CheckpointOnly(_) => [checkpoint_mutation]
    CheckpointAndRecovery(_, recovery) =>
      [
        checkpoint_mutation,
        @indexed_db.Mutation::Set(
          SOURCE_KEY_PREFIX + recovery.id(),
          encode_document(recovery),
        ),
      ]
  }
}

///|
pub fn persist_checkpoint_write(
  saved : SavedDocuments,
  write : CheckpointWrite,
  msg : @cmd.Emit[CheckpointResult],
) -> @cmd.Cmd {
  let checkpoint = write.checkpoint()
  guard (match write {
    CheckpointOnly(_) => true
    CheckpointAndRecovery(_, recovery) =>
      saved.find(recovery.id()) is None &&
      !saved.observed(SOURCE_KEY_PREFIX + recovery.id())
  }) else {
    return msg(
      CheckpointFailed(checkpoint, CheckpointFailure::InvalidCheckpoint),
    )
  }
  document_store.apply(checkpoint_mutations(write), outcome => {
    msg(checkpoint_result(checkpoint, outcome))
  })
}

///|
pub fn EditingDocumentHint::remember(self : Self) -> @cmd.Cmd {
  document_store.set(EDITING_DOCUMENT_KEY, self.0, _ => @cmd.none)
}

///|
fn save_result(
  document : Document,
  outcome : @indexed_db.WriteError?,
) -> SaveResult {
  match outcome {
    None => Stored(document)
    Some(@indexed_db.WriteError::Unavailable) =>
      SaveFailed(SaveFailure::StorageUnavailable)
    Some(@indexed_db.WriteError::QuotaExceeded) =>
      SaveFailed(SaveFailure::QuotaExceeded)
    Some(Failed(_, _)) => SaveFailed(SaveFailure::WriteFailed)
  }
}

///|
pub fn save(
  saved : SavedDocuments,
  document : Document,
  msg : @cmd.Emit[SaveResult],
) -> @cmd.Cmd {
  let key = SOURCE_KEY_PREFIX + document.id()
  guard saved.find(document.id()) is Some(_) || !saved.observed(key) else {
    return msg(SaveFailed(SaveFailure::InvalidSource))
  }
  document_store.set(key, encode_document(document), outcome => {
    msg(save_result(document, outcome))
  })
}

///|
pub fn delete(
  saved : SavedDocuments,
  document_id : String,
  msg : @cmd.Emit[DeleteResult],
) -> @cmd.Cmd {
  guard saved.find(document_id) is Some(_) &&
    source_key(document_id) is Some(key) else {
    return msg(DeleteFailed(DeleteFailure::InvalidSource))
  }
  document_store.delete(key, outcome => {
    match outcome {
      None => msg(Deleted(document_id))
      Some(@indexed_db.WriteError::Unavailable) =>
        msg(DeleteFailed(DeleteFailure::StorageUnavailable))
      Some(@indexed_db.WriteError::QuotaExceeded) =>
        msg(DeleteFailed(DeleteFailure::QuotaExceeded))
      Some(Failed(_, _)) => msg(DeleteFailed(DeleteFailure::WriteFailed))
    }
  })
}

///|
pub fn create(
  saved : SavedDocuments,
  msg : @cmd.Emit[CreateResult],
) -> @cmd.Cmd {
  guard random_uuid_available() else {
    return msg(CreateFailed(CreateFailure::DocumentIdentityUnavailable))
  }
  let id = random_uuid()
  guard saved.find(id) is None && !saved.observed(SOURCE_KEY_PREFIX + id) else {
    return msg(CreateFailed(CreateFailure::DocumentIdentityUnavailable))
  }
  msg(Created(id))
}
