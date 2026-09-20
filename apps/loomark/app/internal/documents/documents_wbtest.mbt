/// Shared fixtures and state extraction for document reducer tests.

///|
fn document_id(value : String) -> @source_repository.DocumentId {
  let mut hash = 0
  for byte in value {
    hash = (hash * 131 + byte.to_int()) % 65521
  }
  let hex = hash.to_string(radix=16)
  let id = "a0000000-0000-4000-8000-" +
    String::make(12 - hex.length(), '0') +
    hex
  @source_repository.DocumentId::parse(id) catch {
    _ => abort("invalid test document id")
  }
}

///|
fn source_key(value : String) -> Key {
  Key::source(document_id(value))
}

///|
fn account_id(value : String) -> @source_repository.AccountId {
  @source_repository.AccountId::parse(value) catch {
    _ => abort("invalid test account id")
  }
}

///|
fn documents_test_snapshot() -> @source_repository.SavedDocuments {
  @source_repository.SavedDocuments::from_documents([
    @source_repository.Document::create(document_id("one"), "one"),
    @source_repository.Document::create(document_id("two"), "two"),
  ]).unwrap()
}

///|
fn documents_test_document(
  id : String,
  text : String,
) -> @source_repository.Document {
  @source_repository.Document::create(document_id(id), text)
}

///|
fn pending_revision(documents : State, id : Key) -> Int {
  match find_record(documents.records, id).unwrap().edit {
    Waiting(revision) | ComposingWaiting(revision) => revision
    Idle | ComposingIdle | ComposingReady => abort("no pending revision")
  }
}

///|
fn has_pending(documents : State, id : Key) -> Bool {
  match find_record(documents.records, id).unwrap().edit {
    Waiting(_) | ComposingWaiting(_) => true
    Idle | ComposingIdle | ComposingReady => false
  }
}

///|
test "source and account identities cannot collide" {
  let id = document_id("checkpoint/9/account-a/6/shared")
  let account_a = account_id("account-a")
  let account_b = account_id("account-b")
  let source = Key::source(id)
  let checkpoint_a = Key::checkpoint(account_a, id)
  let checkpoint_b = Key::checkpoint(account_b, id)
  assert_true(source != checkpoint_a)
  assert_true(checkpoint_a != checkpoint_b)
  assert_true(source.lifecycle_key() != checkpoint_a.lifecycle_key())
  assert_true(checkpoint_a.lifecycle_key() != checkpoint_b.lifecycle_key())
}

///|
test "same document id remains isolated across source and accounts" {
  let id = document_id("shared")
  let account_a = account_id("account-a")
  let account_b = account_id("account-b")
  let saved = @source_repository.SavedDocuments::from_documents([
    @source_repository.Document::create(id, "source"),
  ]).unwrap()
  let saved = saved.apply_checkpoint(
    @source_repository.SyncCheckpoint::enroll(
      account_a,
      @source_repository.Document::create(id, "account A"),
    ),
  ) catch {
    _ => abort("valid account A checkpoint")
  }
  let saved = saved.apply_checkpoint(
    @source_repository.SyncCheckpoint::enroll(
      account_b,
      @source_repository.Document::create(id, "account B"),
    ),
  ) catch {
    _ => abort("valid account B checkpoint")
  }
  let source = Key::source(id)
  let checkpoint_a = Key::checkpoint(account_a, id)
  let checkpoint_b = Key::checkpoint(account_b, id)
  let state = State(saved).project_account(account_a).project_account(account_b)
  let (state, _) = state.reduce(TextChanged(checkpoint_a, "edited A"))
  assert_eq(state.text(source), Some("source"))
  assert_eq(state.text(checkpoint_a), Some("edited A"))
  assert_eq(state.text(checkpoint_b), Some("account B"))
}
