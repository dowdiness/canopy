///|
const UNTITLED_SOURCE : String = "# Untitled\n"

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
pub(all) enum OpenResult {
  Ready(RepositorySnapshot)
  Failed(OpenFailure)
} derive(Eq, Debug)

///|
pub(all) enum SaveResult {
  Stored(RepositorySnapshot)
  Failed(SaveFailure)
} derive(Eq, Debug)

///|
pub(all) enum CreateResult {
  Created(RepositorySnapshot, String)
  Failed(CreateFailure)
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
    Empty(issues, occupied_source_keys) =>
      create_baseline(issues, occupied_source_keys, result)
  }
}

///|
fn create_baseline(
  _issues : Array[RepositoryIssue],
  occupied_source_keys : Array[String],
  result : @cmd.Emit[OpenResult],
) -> @cmd.Cmd {
  guard random_uuid_available() else {
    return result(Failed(DocumentIdentityUnavailable))
  }
  let document_id = random_uuid()
  guard source_key(document_id) is Some(key) &&
    !occupied_source_keys.contains(key) else {
    return result(Failed(DocumentIdentityUnavailable))
  }
  let source = SourceRecord::new(document_id, UNTITLED_SOURCE).unwrap()
  @indexed_db.put(document_store, key, encode_source(source), result=stored => {
    finish_open_write(stored, result)
  })
}

///|
fn finish_save(
  snapshot : RepositorySnapshot,
  source : SourceRecord,
  stored : @indexed_db.WriteResult,
  result : @cmd.Emit[SaveResult],
) -> @cmd.Cmd {
  match stored {
    @indexed_db.WriteResult::Stored =>
      result(Stored(accepted_source(snapshot, source)))
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
  result~ : @cmd.Emit[SaveResult],
) -> @cmd.Cmd {
  guard snapshot.source(document_id) is Some(_) else {
    return result(Failed(InvalidSource))
  }
  guard SourceRecord::new(document_id, text) is Some(source) &&
    source_key(document_id) is Some(key) else {
    return result(Failed(InvalidSource))
  }
  @indexed_db.put(document_store, key, encode_source(source), result=stored => {
    finish_save(snapshot, source, stored, result)
  })
}

///|
fn finish_create(
  snapshot : RepositorySnapshot,
  source : SourceRecord,
  stored : @indexed_db.WriteResult,
  result : @cmd.Emit[CreateResult],
) -> @cmd.Cmd {
  match stored {
    @indexed_db.WriteResult::Stored =>
      result(Created(accepted_source(snapshot, source), source.document_id()))
    @indexed_db.WriteResult::Unavailable => result(Failed(StorageUnavailable))
    @indexed_db.WriteResult::QuotaExceeded => result(Failed(QuotaExceeded))
    @indexed_db.WriteResult::Failed => result(Failed(WriteFailed))
  }
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
  let source = SourceRecord::new(document_id, UNTITLED_SOURCE).unwrap()
  @indexed_db.put(document_store, key, encode_source(source), result=stored => {
    finish_create(snapshot, source, stored, result)
  })
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
