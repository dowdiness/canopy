///|
/// Allocate a browser-owned identity without exposing the JS provider.
pub fn fresh_id(prefix : String) -> String {
  prefix + @storage_js.random_uuid()
}

///|
/// The one active-document slot owned by standalone Loomark.
pub const ACTIVE_DOCUMENT_KEY : String = "loomark.active-document-archive"

///|
/// Typed result of the browser provider's callback-shaped read.
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
  priv request_id : @repository.LocalArchiveRequestId
  priv result : LocalArchiveStorageWrite
}

///|
pub fn LocalArchiveWriteCompletion::request_id(
  self : Self,
) -> @repository.LocalArchiveRequestId {
  self.request_id
}

///|
pub fn LocalArchiveWriteCompletion::result(
  self : Self,
) -> LocalArchiveStorageWrite {
  self.result
}

///|
/// Map the JS provider's read code into the repository shell taxonomy.
pub fn load(callback : (LocalArchiveStorageRead) -> Unit) -> Unit {
  @storage_js.get_item(ACTIVE_DOCUMENT_KEY, (kind, value) => {
    match kind {
      0 => callback(Missing)
      1 => callback(Loaded(value))
      2 =>
        callback(
          Failed(@repository.LocalArchiveStorageReadFailure::Unavailable),
        )
      _ => callback(Failed(@repository.LocalArchiveStorageReadFailure::Failed))
    }
  })
}

///|
/// Schedule one atomic complete archive replacement.
pub fn replace(
  request_id : @repository.LocalArchiveRequestId,
  encoded : String,
  completed~ : @cmd.Emit[LocalArchiveWriteCompletion],
) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=@cmd.Immediately, scheduler => {
    @storage_js.set_item(ACTIVE_DOCUMENT_KEY, encoded, kind => {
      let result = match kind {
        0 => LocalArchiveStorageWrite::Stored
        1 =>
          LocalArchiveStorageWrite::Failed(
            @repository.LocalArchiveStorageWriteFailure::Unavailable,
          )
        2 =>
          LocalArchiveStorageWrite::Failed(
            @repository.LocalArchiveStorageWriteFailure::QuotaExceeded,
          )
        _ =>
          LocalArchiveStorageWrite::Failed(
            @repository.LocalArchiveStorageWriteFailure::Failed,
          )
      }
      scheduler.add(completed({ request_id, result }))
    })
  })
}
