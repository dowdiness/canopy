///|
fn reconcile_scan(
  entries : Array[@indexed_db.Entry],
) -> (SavedDocuments, Document?) {
  let documents : Array[Document] = []
  let replicas : Array[DocumentReplica] = []
  let issues : Array[RepositoryIssue] = []
  let observed : Array[String] = []
  let observed_replicas : Array[String] = []
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
        } else if key.strip_prefix(REPLICA_KEY_PREFIX) is Some(_) {
          observed_replicas.push(key)
          match decode_replica(key, encoded) {
            Some(replica) if replicas
              .iter()
              .all(existing => {
                existing.account() != replica.account() ||
                existing.document().id() != replica.document().id()
              }) => replicas.push(replica)
            _ => issues.push(InvalidDocumentReplica(key))
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
        } else if key.strip_prefix(REPLICA_KEY_PREFIX) is Some(_) {
          observed_replicas.push(key)
          issues.push(InvalidDocumentReplica(key))
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
    documents, issues, observed, replicas, observed_replicas,
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
