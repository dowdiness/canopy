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
  Created(DocumentId)
  CreateFailed(CreateFailure)
} derive(Eq, Debug)

///|
pub(all) enum DeleteResult {
  Deleted(DocumentId)
  DeleteFailed(DeleteFailure)
} derive(Eq, Debug)

///|
pub(all) enum ReplicaFailure {
  InvalidReplica
  StorageUnavailable
  QuotaExceeded
  WriteFailed
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
fn replica_failure(outcome : @indexed_db.WriteError) -> ReplicaFailure {
  match outcome {
    @indexed_db.WriteError::Unavailable => ReplicaFailure::StorageUnavailable
    @indexed_db.WriteError::QuotaExceeded => ReplicaFailure::QuotaExceeded
    Failed(_, _) => ReplicaFailure::WriteFailed
  }
}

///|
fn replica_result(
  outcome : @indexed_db.WriteError?,
) -> Result[Unit, ReplicaFailure] {
  match outcome {
    None => Ok(())
    Some(failure) => Err(replica_failure(failure))
  }
}

///|
fn replica_mutations(write : ReplicaWrite) -> Array[@indexed_db.Mutation] {
  let replica = write.replica()
  let replica_mutation = @indexed_db.Mutation::Set(
    replica_key(replica.account, replica.document.id()),
    encode_replica(replica),
  )
  match write {
    Store(_) => [replica_mutation]
    Fork(_, recovery) =>
      [
        replica_mutation,
        @indexed_db.Mutation::Set(
          source_key(recovery.id()),
          encode_document(recovery),
        ),
      ]
    PromoteSource(_) =>
      [
        replica_mutation,
        @indexed_db.Mutation::Delete(source_key(replica.document.id())),
      ]
  }
}

///|
pub fn persist_replica_write(
  saved : SavedDocuments,
  write : ReplicaWrite,
  msg : @cmd.Emit[Result[Unit, ReplicaFailure]],
) -> @cmd.Cmd {
  let replica = write.replica()
  guard (match write {
    Store(_) => true
    Fork(_, recovery) =>
      saved.find(recovery.id()) is None &&
      !saved.observed(source_key(recovery.id()))
    PromoteSource(_) =>
      saved.find(replica.document().id()) == Some(replica.document()) &&
      !saved.observed_replicas(
        replica_key(replica.account(), replica.document().id()),
      )
  }) else {
    return msg(Err(ReplicaFailure::InvalidReplica))
  }
  document_store.apply(replica_mutations(write), outcome => {
    msg(replica_result(outcome))
  })
}

///|
pub fn EditingDocumentHint::remember(self : Self) -> @cmd.Cmd {
  document_store.set(EDITING_DOCUMENT_KEY, self.0.value(), _ => @cmd.none)
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
  let key = source_key(document.id())
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
  document_id : DocumentId,
  msg : @cmd.Emit[DeleteResult],
) -> @cmd.Cmd {
  guard saved.find(document_id) is Some(_) else {
    return msg(DeleteFailed(DeleteFailure::InvalidSource))
  }
  let key = source_key(document_id)
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
  let id = DocumentId::parse(random_uuid()) catch {
    _ => return msg(CreateFailed(CreateFailure::DocumentIdentityUnavailable))
  }
  guard saved.find(id) is None && !saved.observed(source_key(id)) else {
    return msg(CreateFailed(CreateFailure::DocumentIdentityUnavailable))
  }
  msg(Created(id))
}

///|
pub fn operation_id(msg : @cmd.Emit[OperationId?]) -> @cmd.Cmd {
  guard random_uuid_available() else { return msg(None) }
  let id = OperationId::parse(random_uuid()) catch { _ => return msg(None) }
  msg(Some(id))
}
