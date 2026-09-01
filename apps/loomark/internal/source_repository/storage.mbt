///|
let document_store : @indexed_db.Config = @indexed_db.Config::Config(
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
  DocumentIdentityUnavailable
  QuotaExceeded
  WriteFailed
} derive(Eq, Debug)

///|
pub(all) enum SaveFailure {
  InvalidSource
  ChangeOrderExhausted
  StorageUnavailable
  QuotaExceeded
  WriteFailed
} derive(Eq, Debug)

///|
pub(all) enum CreateFailure {
  DocumentIdentityUnavailable
  StorageUnavailable
  QuotaExceeded
  WriteFailed
} derive(Eq, Debug)

///|
pub(all) enum DeleteFailure {
  InvalidSource
  StorageUnavailable
  QuotaExceeded
  WriteFailed
} derive(Eq, Debug)

///|
pub(all) enum ProbeFailure {
  InvalidSource
  StorageUnavailable
  ReadFailed
} derive(Eq, Debug)

///|
pub(all) enum OpenResult {
  Ready(RepositorySnapshot)
  Failed(OpenFailure)
} derive(Eq, Debug)

///|
pub(all) enum SaveResult {
  Stored(SourceRecord)
  Failed(SaveFailure)
} derive(Eq, Debug)

///|
pub(all) enum CreateResult {
  Created(String)
  Failed(CreateFailure)
} derive(Eq, Debug)

///|
pub(all) enum DeleteResult {
  Deleted(String)
  Failed(DeleteFailure)
} derive(Eq, Debug)

///|
pub(all) enum ProbeResult {
  Present(SourceRecord)
  Missing
  Unsupported
  Failed(ProbeFailure)
} derive(Eq, Debug)

///|
pub fn open(result~ : @cmd.Emit[OpenResult]) -> @cmd.Cmd {
  scan_repository(result)
}

///|
fn scan_repository(result : @cmd.Emit[OpenResult]) -> @cmd.Cmd {
  @indexed_db.scan(document_store, result=scanned => {
    match scanned {
      @indexed_db.ScanResult::Scanned(entries) =>
        continue_open(reconcile_scan(entries), result)
      @indexed_db.ScanResult::Unavailable => result(Failed(StorageUnavailable))
      @indexed_db.ScanResult::Failed => result(Failed(ReadFailed))
    }
  })
}

///|
fn finish_open_write(
  stored : @indexed_db.WriteResult,
  result : @cmd.Emit[OpenResult],
) -> @cmd.Cmd {
  match stored {
    @indexed_db.WriteResult::Stored => scan_repository(result)
    @indexed_db.WriteResult::Unavailable => result(Failed(StorageUnavailable))
    @indexed_db.WriteResult::QuotaExceeded => result(Failed(QuotaExceeded))
    @indexed_db.WriteResult::Failed => result(Failed(WriteFailed))
  }
}

///|
fn continue_open(
  reconciliation : Reconciliation,
  result : @cmd.Emit[OpenResult],
) -> @cmd.Cmd {
  match reconciliation {
    Ready(snapshot) => result(Ready(snapshot))
    Migrate(mutations) =>
      @indexed_db.mutate(document_store, mutations, result=stored => {
        finish_open_write(stored, result)
      })
  }
}

///|
fn finish_save(
  source : SourceRecord,
  stored : @indexed_db.WriteResult,
  result : @cmd.Emit[SaveResult],
) -> @cmd.Cmd {
  match stored {
    @indexed_db.WriteResult::Stored => result(Stored(source))
    @indexed_db.WriteResult::Unavailable => result(Failed(StorageUnavailable))
    @indexed_db.WriteResult::QuotaExceeded => result(Failed(QuotaExceeded))
    @indexed_db.WriteResult::Failed => result(Failed(WriteFailed))
  }
}

///|
pub fn save(
  snapshot : RepositorySnapshot,
  document_id : String,
  text : String,
  change_order? : ChangeOrder,
  result~ : @cmd.Emit[SaveResult],
) -> @cmd.Cmd {
  guard snapshot.source(document_id) is Some(current) else {
    return result(Failed(InvalidSource))
  }
  let change_order = change_order.unwrap_or(current.change_order())
  guard SourceRecord::new(document_id, text, change_order~) is Some(source) &&
    source_key(document_id) is Some(key) else {
    return result(Failed(InvalidSource))
  }
  @indexed_db.put(document_store, key, encode_source(source), result=stored => {
    finish_save(source, stored, result)
  })
}

///|
fn finish_delete(
  document_id : String,
  stored : @indexed_db.WriteResult,
  result : @cmd.Emit[DeleteResult],
) -> @cmd.Cmd {
  match stored {
    @indexed_db.WriteResult::Stored => result(Deleted(document_id))
    @indexed_db.WriteResult::Unavailable => result(Failed(StorageUnavailable))
    @indexed_db.WriteResult::QuotaExceeded => result(Failed(QuotaExceeded))
    @indexed_db.WriteResult::Failed => result(Failed(WriteFailed))
  }
}

///|
pub fn delete(
  snapshot : RepositorySnapshot,
  document_id : String,
  result~ : @cmd.Emit[DeleteResult],
) -> @cmd.Cmd {
  guard snapshot.source(document_id) is Some(_) &&
    source_key(document_id) is Some(key) else {
    return result(Failed(InvalidSource))
  }
  @indexed_db.mutate(document_store, [@indexed_db.Mutation::Delete(key)], result=stored => {
    finish_delete(document_id, stored, result)
  })
}

///|
fn finish_probe(
  document_id : String,
  read : @indexed_db.ReadResult,
  result : @cmd.Emit[ProbeResult],
) -> @cmd.Cmd {
  match read {
    @indexed_db.ReadResult::Loaded(encoded) =>
      match decode_source(source_key(document_id).unwrap(), encoded) {
        Ok(source) => result(Present(source))
        Err(_) => result(Unsupported)
      }
    @indexed_db.ReadResult::Missing => result(Missing)
    @indexed_db.ReadResult::Unavailable => result(Failed(StorageUnavailable))
    @indexed_db.ReadResult::Failed => result(Failed(ReadFailed))
  }
}

///|
/// Check current storage after an earlier operation had an unknown outcome.
pub fn probe(
  snapshot : RepositorySnapshot,
  document_id : String,
  result~ : @cmd.Emit[ProbeResult],
) -> @cmd.Cmd {
  guard snapshot.source(document_id) is Some(_) &&
    source_key(document_id) is Some(key) else {
    return result(Failed(InvalidSource))
  }
  @indexed_db.get(document_store, key, result=read => {
    finish_probe(document_id, read, result)
  })
}

///|
fn create_with_document_id(
  snapshot : RepositorySnapshot,
  document_id : String,
  result : @cmd.Emit[CreateResult],
) -> @cmd.Cmd {
  guard source_key(document_id) is Some(key) &&
    !snapshot.occupied_source_keys().contains(key) else {
    return result(Failed(DocumentIdentityUnavailable))
  }
  result(Created(document_id))
}

///|
pub fn create(
  snapshot : RepositorySnapshot,
  result~ : @cmd.Emit[CreateResult],
) -> @cmd.Cmd {
  guard random_uuid_available() else {
    return result(Failed(DocumentIdentityUnavailable))
  }
  create_with_document_id(snapshot, random_uuid(), result)
}

///|
pub fn store_new(
  snapshot : RepositorySnapshot,
  document_id : String,
  text : String,
  change_order : ChangeOrder,
  result~ : @cmd.Emit[SaveResult],
) -> @cmd.Cmd {
  guard snapshot.source(document_id) is None &&
    source_key(document_id) is Some(key) &&
    !snapshot.occupied_source_keys().contains(key) &&
    SourceRecord::new(document_id, text, change_order~) is Some(source) else {
    return result(Failed(InvalidSource))
  }
  @indexed_db.put(document_store, key, encode_source(source), result=stored => {
    finish_save(source, stored, result)
  })
}
