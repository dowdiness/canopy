///|
/// Allocate a browser-owned identity without exposing the JS provider.
pub fn fresh_id(prefix : String) -> String {
  prefix + @storage_js.random_uuid()
}

///|
/// The one active-document slot owned by standalone Loomark.
pub const ACTIVE_DOCUMENT_KEY : String = "loomark.active-document-archive"

///|
/// The one browser database used by the standalone local archive.
let local_repository_config : @indexed_db.Config = @indexed_db.Config::Config(
  "loomark.local-repository", 1, "archives",
)

///|
/// Typed result of one IndexedDB binding read.
pub(all) enum LocalArchiveStorageRead {
  Missing
  Loaded(String)
  Failed(@repository.LocalArchiveStorageReadFailure)
} derive(Eq, Debug)

///|
/// Typed result of one complete archive replacement.
pub(all) enum LocalArchiveStorageWrite {
  Stored
  Failed(@repository.LocalArchiveStorageWriteFailure)
} derive(Eq, Debug)

///|
/// Completion correlated with the repository request that initiated it.
pub struct LocalArchiveWriteCompletion {
  priv pending : @repository.LocalArchivePendingWrite
  priv result : LocalArchiveStorageWrite
}

///|
pub fn LocalArchiveWriteCompletion::pending(
  self : Self,
) -> @repository.LocalArchivePendingWrite {
  self.pending
}

///|
pub fn LocalArchiveWriteCompletion::request_id(
  self : Self,
) -> @repository.LocalArchiveRequestId {
  self.pending.request_id()
}

///|
pub fn LocalArchiveWriteCompletion::result(
  self : Self,
) -> LocalArchiveStorageWrite {
  self.result
}

///|
/// Map the IndexedDB binding's result into the repository shell taxonomy.
pub fn load(result~ : @cmd.Emit[LocalArchiveStorageRead]) -> @cmd.Cmd {
  @indexed_db.get(
    local_repository_config,
    ACTIVE_DOCUMENT_KEY,
    migrate_legacy=true,
    result=stored => {
      result(
        match stored {
          @indexed_db.ReadResult::Missing => Missing
          @indexed_db.ReadResult::Loaded(value) => Loaded(value)
          @indexed_db.ReadResult::Unavailable =>
            Failed(@repository.LocalArchiveStorageReadFailure::Unavailable)
          @indexed_db.ReadResult::Failed =>
            Failed(@repository.LocalArchiveStorageReadFailure::Failed)
        },
      )
    },
  )
}

///|
/// Schedule one atomic complete archive replacement.
pub fn replace(
  pending : @repository.LocalArchivePendingWrite,
  completed~ : @cmd.Emit[LocalArchiveWriteCompletion],
) -> @cmd.Cmd {
  @indexed_db.put(
    local_repository_config,
    ACTIVE_DOCUMENT_KEY,
    pending.encoded(),
    result=stored => {
      let result = match stored {
        @indexed_db.WriteResult::Stored => LocalArchiveStorageWrite::Stored
        @indexed_db.WriteResult::Unavailable =>
          LocalArchiveStorageWrite::Failed(
            @repository.LocalArchiveStorageWriteFailure::Unavailable,
          )
        @indexed_db.WriteResult::QuotaExceeded =>
          LocalArchiveStorageWrite::Failed(
            @repository.LocalArchiveStorageWriteFailure::QuotaExceeded,
          )
        @indexed_db.WriteResult::Failed =>
          LocalArchiveStorageWrite::Failed(
            @repository.LocalArchiveStorageWriteFailure::Failed,
          )
      }
      completed({ pending, result })
    },
  )
}
