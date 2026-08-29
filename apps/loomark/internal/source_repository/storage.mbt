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
pub(all) enum OpenResult {
  Ready(RepositorySnapshot)
  Failed(OpenFailure)
} derive(Eq, Debug)

///|
pub(all) enum SaveResult {
  Stored(SaveSuccess)
  Failed(SaveFailure)
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
fn continue_open(
  reconciliation : Reconciliation,
  result : @cmd.Emit[OpenResult],
) -> @cmd.Cmd {
  match reconciliation {
    Ready(snapshot, CatalogCurrent) => result(Ready(snapshot))
    Ready(snapshot, RepairCatalog(encoded)) =>
      @indexed_db.put(document_store, CATALOG_KEY, encoded, result=stored => {
        match stored {
          @indexed_db.WriteResult::Stored => result(Ready(snapshot))
          @indexed_db.WriteResult::Unavailable
          | @indexed_db.WriteResult::QuotaExceeded
          | @indexed_db.WriteResult::Failed =>
            result(Ready(snapshot.with_issue(CatalogWriteFailure)))
        }
      })
    Migrate(mutations) =>
      @indexed_db.mutate(document_store, mutations, result=stored => {
        match stored {
          @indexed_db.WriteResult::Stored => scan_repository(result)
          @indexed_db.WriteResult::Unavailable =>
            result(Failed(StorageUnavailable))
          @indexed_db.WriteResult::QuotaExceeded
          | @indexed_db.WriteResult::Failed => result(Failed(WriteFailed))
        }
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
    match stored {
      @indexed_db.WriteResult::Stored => scan_repository(result)
      @indexed_db.WriteResult::Unavailable => result(Failed(StorageUnavailable))
      @indexed_db.WriteResult::QuotaExceeded
      | @indexed_db.WriteResult::Failed => result(Failed(WriteFailed))
    }
  })
}

///|
pub fn save(
  catalog : Catalog,
  document_id : String,
  text : String,
  result~ : @cmd.Emit[SaveResult],
) -> @cmd.Cmd {
  guard SourceRecord::new(document_id, text) is Some(source) &&
    source_key(document_id) is Some(key) else {
    return result(Failed(InvalidSource))
  }
  let (next, issues) = next_catalog(catalog, document_id, text)
  @indexed_db.put(document_store, key, encode_source(source), result=stored => {
    match stored {
      @indexed_db.WriteResult::Stored =>
        persist_catalog_after_source(next, issues, result)
      @indexed_db.WriteResult::Unavailable => result(Failed(StorageUnavailable))
      @indexed_db.WriteResult::QuotaExceeded => result(Failed(QuotaExceeded))
      @indexed_db.WriteResult::Failed => result(Failed(WriteFailed))
    }
  })
}

///|
fn persist_catalog_after_source(
  catalog : Catalog,
  issues : Array[RepositoryIssue],
  result : @cmd.Emit[SaveResult],
) -> @cmd.Cmd {
  @indexed_db.put(document_store, CATALOG_KEY, encode_catalog(catalog), result=stored => {
    match stored {
      @indexed_db.WriteResult::Stored =>
        result(Stored(SaveSuccess::new(catalog, issues)))
      @indexed_db.WriteResult::Unavailable
      | @indexed_db.WriteResult::QuotaExceeded
      | @indexed_db.WriteResult::Failed => {
        let completed_issues = issues.copy()
        completed_issues.push(CatalogWriteFailure)
        result(Stored(SaveSuccess::new(catalog, completed_issues)))
      }
    }
  })
}
