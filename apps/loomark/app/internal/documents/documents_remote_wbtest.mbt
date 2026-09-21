///|
fn remote_fixture(
  remote : @source_repository.RemoteDocument,
) -> (State, @source_repository.DocumentReplica, RemoteChange) {
  let account = account_id("account")
  let document = documents_test_document("one", "base")
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let replica = @source_repository.DocumentReplica::receive(
    account,
    document,
    revision,
  )
  guard replica.reconcile(remote)
    is @source_repository.ReconcilePlan::Persist(write) else {
    abort("remote update")
  }
  let replica = write.replica()
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(replica) catch {
      _ => abort("valid replica")
    }
  let documents = State::State(saved).project_account(account)
  let change = documents.remote_change(replica).unwrap()
  (documents, replica, change)
}

///|
fn remote_revision(value : Double, text : String) -> @source_repository.RemoteDocument {
  @source_repository.RemoteDocument::Present(
    @source_repository.SavedRevision::parse(value) catch {
      _ => abort("valid revision")
    },
    text,
  )
}

///|
test "remote update capability expires after a local edit" {
  let (documents, replica, change) = remote_fixture(
    remote_revision(2.0, "remote"),
  )
  guard change is UpdateAvailable(action) else { fail("available update") }
  let key = Key::replica(replica.account(), replica.document().id())
  let (documents, _) = documents.reduce(TextChanged(key, "local"))
  let expired = try documents.accept_remote(replica, action) catch {
    ExpiredAction => true
  } noraise {
    _ => false
  }
  assert_true(expired)
}

///|
test "remote update capability expires when its account is no longer visible" {
  let (documents, replica, change) = remote_fixture(
    remote_revision(2.0, "remote"),
  )
  guard change is UpdateAvailable(action) else { fail("available update") }
  let other = account_id("other")
  let documents = documents.project_account(other)
  let expired = try documents.accept_remote(replica, action) catch {
    ExpiredAction => true
  } noraise {
    _ => false
  }
  assert_true(expired)
}

///|
test "remote update capability expires when a newer revision commits" {
  let (documents, replica, change) = remote_fixture(
    remote_revision(2.0, "remote two"),
  )
  guard change is UpdateAvailable(action) else { fail("available update") }
  guard replica.reconcile(remote_revision(3.0, "remote three"))
    is @source_repository.ReconcilePlan::Persist(write) else {
    fail("newer revision")
  }
  let newer = write.replica()
  let (documents, _) = documents.reduce(
    FeedbackReceived(ReplicaCommitted(write)),
  )
  let expired = try documents.accept_remote(newer, action) catch {
    ExpiredAction => true
  } noraise {
    _ => false
  }
  assert_true(expired)
}

///|
test "accepting a remote update replaces only the parsed replica revision" {
  let (documents, replica, change) = remote_fixture(
    remote_revision(2.0, "remote"),
  )
  guard change is UpdateAvailable(action) else { fail("available update") }
  guard documents.accept_remote(replica, action)
    is RemoteAcceptance::Opened(documents, document, write) else {
    fail("accepted update")
  }
  let key = Key::replica(replica.account(), replica.document().id())
  assert_eq(document.text(), "remote")
  assert_eq(documents.text(key), Some("remote"))
  assert_eq(write.replica().document(), document)
}

///|
test "accepting a remote deletion removes the working copy without inventing text" {
  let deleted = @source_repository.RemoteDocument::Deleted(
    @source_repository.SavedRevision::parse(2.0) catch {
      _ => abort("valid revision")
    },
  )
  let (documents, replica, change) = remote_fixture(deleted)
  guard change is DeletedRemotely(action) else { fail("remote deletion") }
  guard documents.accept_remote(replica, action)
    is RemoteAcceptance::Removed(documents, write) else {
    fail("accepted deletion")
  }
  let key = Key::replica(replica.account(), replica.document().id())
  assert_eq(documents.text(key), None)
  assert_eq(write.replica().document().text(), "base")
  assert_true(write.replica().is_deleted())
  let switched = documents
    .project_account(account_id("other"))
    .project_account(replica.account())
  assert_eq(switched.text(key), None)
  let committed = documents.snapshot().apply_replica_write(write) catch {
    _ => abort("valid deletion")
  }
  let restarted = State::State(committed).project_account(replica.account())
  assert_eq(restarted.text(key), None)
}
