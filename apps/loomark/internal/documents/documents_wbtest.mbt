/// Shared fixtures and state extraction for document lifecycle tests.

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
fn pending_revision(documents : Model, id : Key) -> Int {
  match find_record(documents.records, id).unwrap().edit {
    Waiting(revision) | ComposingWaiting(revision) => revision
    Idle | ComposingIdle | ComposingReady => abort("no pending revision")
  }
}

///|
fn has_pending(documents : Model, id : Key) -> Bool {
  match find_record(documents.records, id).unwrap().edit {
    Waiting(_) | ComposingWaiting(_) => true
    Idle | ComposingIdle | ComposingReady => false
  }
}

///|
test "source and account identities cannot collide" {
  let id = document_id("replica/9/account-a/6/shared")
  let account_a = account_id("account-a")
  let account_b = account_id("account-b")
  let source = Key::source(id)
  let replica_a = Key::replica(account_a, id)
  let replica_b = Key::replica(account_b, id)
  assert_true(source != replica_a)
  assert_true(replica_a != replica_b)
  assert_true(source.lifecycle_key() != replica_a.lifecycle_key())
  assert_true(replica_a.lifecycle_key() != replica_b.lifecycle_key())
}

///|
test "replica completion classifies promotion independently of a newer write" {
  let replica = @source_repository.DocumentReplica(
    account_id("account"),
    documents_test_document("one", "one"),
  )
  let promotion = replica.promote_source()
  let (lane, active) = @replica_persistence.State().submit(promotion)
  guard active is Some(active) else { fail("active promotion") }
  let (lane, next) = lane.submit(replica.store())
  guard next is None else { fail("newer write must wait") }
  let (_, completion) = lane.complete(active, Ok(()))
  guard completion is @replica_persistence.Completion::Superseded(_, _) else {
    fail("superseded promotion")
  }
  guard Msg::from_replica_completion(
      promotion,
      completion,
      Some(source_key("one")),
    )
    is Some(Promoted(write)) &&
    write == promotion else {
    fail("promotion must rekey even when superseded")
  }

///|
test "replica completion distinguishes current, superseded, and deletion failure" {
  let replica = @source_repository.DocumentReplica(
    account_id("account"),
    documents_test_document("one", "one"),
  )
  let write = replica.store()
  let mounted = Key::replica(replica.account(), replica.document_id())
  guard Msg::from_replica_completion(
      write,
      @replica_persistence.Completion::Current(write),
      Some(mounted),
    )
    is Some(ReplicaSettled(_, Some(key))) &&
    key == mounted else {
    fail("current completion must carry mounted identity")
  }
  let (lane, active) = @replica_persistence.State().submit(write)
  guard active is Some(active) else { fail("active write") }
  let (lane, next) = lane.submit(replica.rewrite())
  guard next is None else { fail("newer write must wait") }
  let (_, completion) = lane.complete(active, Ok(()))
  guard Msg::from_replica_completion(write, completion, Some(mounted))
    is Some(ReplicaAdvanced(_)) else {
    fail("superseded success cannot settle current working copy")
  }
  let deletion = replica.request_deletion()
  guard Msg::from_replica_completion(
      deletion,
      @replica_persistence.Completion::Failed(deletion, StorageUnavailable),
      Some(mounted),
    )
    is Some(ReplicaDeletionFailed(_, StorageUnavailable)) else {
    fail("deletion failure must be shown")
  }
  guard Msg::from_replica_completion(
      write,
      @replica_persistence.Completion::Failed(write, StorageUnavailable),
      Some(mounted),
    )
    is None else {
    fail("ordinary write failure stays with the persistence lane")
  }

///|
test "same document id remains isolated across source and accounts" {
  let id = document_id("shared")
  let account_a = account_id("account-a")
  let account_b = account_id("account-b")
  let saved = @source_repository.SavedDocuments::from_documents([
    @source_repository.Document::create(id, "source"),
  ]).unwrap()
  let saved = saved.apply_replica(
    @source_repository.DocumentReplica(
      account_a,
      @source_repository.Document::create(id, "account A"),
    ),
  ) catch {
    _ => abort("valid account A replica")
  }
  let saved = saved.apply_replica(
    @source_repository.DocumentReplica(
      account_b,
      @source_repository.Document::create(id, "account B"),
    ),
  ) catch {
    _ => abort("valid account B replica")
  }
  let source = Key::source(id)
  let replica_a = Key::replica(account_a, id)
  let replica_b = Key::replica(account_b, id)
  let state = Model(saved).project_account(account_a).project_account(account_b)
  guard (try state.edit(replica_a, "edited A") catch {
    _ => abort("unexpected edit error")
  }) is Changed(transition) else {
    fail("replica edit")
  }
  let state = transition.model
