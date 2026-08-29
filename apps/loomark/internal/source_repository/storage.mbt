///|
const ACTIVE_DOCUMENT_KEY : String = "active"

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
  InvalidRecord
  StorageUnavailable
  ReadFailed
  DocumentIdentityUnavailable
} derive(Eq)

///|
pub(all) enum SaveFailure {
  StorageUnavailable
  QuotaExceeded
  WriteFailed
} derive(Eq)

///|
pub(all) enum OpenResult {
  New(String)
  Loaded(String, String)
  Failed(OpenFailure)
} derive(Eq)

///|
pub(all) enum SaveResult {
  Stored
  Failed(SaveFailure)
} derive(Eq)

///|
pub fn open(result~ : @cmd.Emit[OpenResult]) -> @cmd.Cmd {
  @indexed_db.get(document_store, ACTIVE_DOCUMENT_KEY, migrate_legacy=false, result=stored => {
    result(
      match stored {
        @indexed_db.ReadResult::Missing =>
          if random_uuid_available() {
            New(random_uuid())
          } else {
            Failed(DocumentIdentityUnavailable)
          }
        @indexed_db.ReadResult::Loaded(encoded) => decode_document(encoded)
        @indexed_db.ReadResult::Unavailable => Failed(StorageUnavailable)
        @indexed_db.ReadResult::Failed => Failed(ReadFailed)
      },
    )
  })
}

///|
pub fn save(
  document_id : String,
  text : String,
  result~ : @cmd.Emit[SaveResult],
) -> @cmd.Cmd {
  @indexed_db.put(
    document_store,
    ACTIVE_DOCUMENT_KEY,
    encode_document(document_id, text),
    result=stored => {
      result(
        match stored {
          @indexed_db.WriteResult::Stored => Stored
          @indexed_db.WriteResult::Unavailable => Failed(StorageUnavailable)
          @indexed_db.WriteResult::QuotaExceeded => Failed(QuotaExceeded)
          @indexed_db.WriteResult::Failed => Failed(WriteFailed)
        },
      )
    },
  )
}
