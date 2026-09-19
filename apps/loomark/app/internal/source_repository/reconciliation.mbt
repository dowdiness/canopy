///|
fn reconcile_scan(
  entries : Array[@indexed_db.Entry],
) -> (SavedDocuments, Document?) {
  let documents : Array[Document] = []
  let checkpoints : Array[SyncCheckpoint] = []
  let issues : Array[RepositoryIssue] = []
  let observed : Array[String] = []
  let observed_sync : Array[String] = []
  let mut editing : DocumentId? = None
  for entry in entries {
    match entry {
      @indexed_db.Entry::StringRecord(key, encoded) =>
        if key == EDITING_DOCUMENT_KEY {
          editing = Some(DocumentId::parse(encoded)) catch { _ => None }
        } else if key.strip_prefix(SOURCE_KEY_PREFIX) is Some(_) {
          observed.push(key)
          match decode_document(key, encoded) {
            Some(document) if documents
              .iter()
              .all(existing => existing.id() != document.id()) =>
              documents.push(document)
            _ => issues.push(InvalidSource(key))
          }
        } else if key.strip_prefix(SYNC_KEY_PREFIX) is Some(_) {
          observed_sync.push(key)
          match decode_checkpoint(key, encoded) {
            Some(checkpoint) if checkpoints
              .iter()
              .all(existing => {
                existing.account() != checkpoint.account() ||
                existing.document().id() != checkpoint.document().id()
              }) => checkpoints.push(checkpoint)
            _ => issues.push(InvalidSyncCheckpoint(key))
          }
        } else if key.strip_prefix("source/v") is Some(_) {
          issues.push(UnsupportedSourceSchema(key))
        } else {
          issues.push(UnknownRecord(key))
        }
      @indexed_db.Entry::UnsupportedValue(key) =>
        if key.strip_prefix(SOURCE_KEY_PREFIX) is Some(_) {
          observed.push(key)
          issues.push(InvalidSource(key))
        } else if key.strip_prefix(SYNC_KEY_PREFIX) is Some(_) {
          observed_sync.push(key)
          issues.push(InvalidSyncCheckpoint(key))
        } else if key == EDITING_DOCUMENT_KEY {
          ()
        } else {
          issues.push(UnsupportedRecord(key))
        }
      @indexed_db.Entry::UnsupportedKey(position) =>
        issues.push(UnsupportedKey(position))
    }
  }
  let saved = rebuild_saved_documents(
    documents, issues, observed, checkpoints, observed_sync,
  )
  let selected = match editing {
    Some(id) =>
      match saved.find(id) {
        Some(document) => Some(document)
        None => saved.all().get(0)
      }
    None => saved.all().get(0)
  }
  (saved, selected)
}
