/// Shared fixtures and state extraction for document reducer tests.

///|
fn documents_test_snapshot() -> @source_repository.SavedDocuments {
  @source_repository.SavedDocuments::from_documents([
    @source_repository.Document::create("one", "one") catch {
      _ => abort("invalid id")
    },
    @source_repository.Document::create("two", "two") catch {
      _ => abort("invalid id")
    },
  ]).unwrap()
}

///|
fn documents_test_document(
  id : String,
  text : String,
) -> @source_repository.Document {
  @source_repository.Document::create(id, text) catch {
    _ => abort("invalid id")
  }
}

///|
fn pending_revision(documents : Documents, id : String) -> Int {
  match find_record(documents.records, id).unwrap().edit {
    Waiting(revision) | ComposingWaiting(revision) => revision
    Idle | ComposingIdle | ComposingReady => abort("no pending revision")
  }
}

///|
fn has_pending(documents : Documents, id : String) -> Bool {
  match find_record(documents.records, id).unwrap().edit {
    Waiting(_) | ComposingWaiting(_) => true
    Idle | ComposingIdle | ComposingReady => false
  }
}
