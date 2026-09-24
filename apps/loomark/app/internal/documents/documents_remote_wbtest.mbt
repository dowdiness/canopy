///|
fn remote_fixture(
  remote : @source_repository.RemoteDocument,
) -> (
  State,
  @source_repository.DocumentReplica,
  @source_repository.RemoteHead,
  RemoteState,
) {
  let account = account_id("account")
  let document = documents_test_document("one", "base")
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let replica = @source_repository.DocumentReplica::receive(
    account, document, revision,
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
  let head = replica.remote_update().unwrap().head()
  let remote = documents.remote_state(replica, Some(head))
  (documents, replica, head, remote)
}

///|
fn remote_revision(
  value : Double,
  text : String,
) -> @source_repository.RemoteDocument {
  @source_repository.RemoteDocument::Present(
    @source_repository.SavedRevision::parse(value) catch {
      _ => abort("valid revision")
    },
    text,
  )
}

///|
test "remote update capability expires after a local edit" {
  let (documents, replica, head, remote) = remote_fixture(
    remote_revision(2.0, "remote"),
  )
  guard remote is UpdateAvailable(action) else { fail("available update") }
  let key = Key::replica(replica.account(), replica.document_id())
  let (documents, _) = documents.reduce(TextChanged(key, "local"))
  let expired = try documents.accept_remote(replica, Some(head), action) catch {
    ExpiredAction => true
  } noraise {
    _ => false
  }
  assert_true(expired)
}

///|
test "remote update capability expires when its account is no longer visible" {
  let (documents, replica, head, remote) = remote_fixture(
    remote_revision(2.0, "remote"),
  )
  guard remote is UpdateAvailable(action) else { fail("available update") }
  let other = account_id("other")
  let documents = documents.project_account(other)
  let expired = try documents.accept_remote(replica, Some(head), action) catch {
    ExpiredAction => true
  } noraise {
    _ => false
  }
  assert_true(expired)
}

///|
test "remote update capability expires when a newer revision commits" {
  let (documents, replica, _, remote) = remote_fixture(
    remote_revision(2.0, "remote two"),
  )
  guard remote is UpdateAvailable(action) else { fail("available update") }
  guard replica.reconcile(remote_revision(3.0, "remote three"))
    is @source_repository.ReconcilePlan::Persist(write) else {
    fail("newer revision")
  }
  let newer = write.replica()
  let (documents, _) = documents.reduce(
    FeedbackReceived(ReplicaSettled(write, None)),
  )
  let newer_head = newer.remote_update().unwrap().head()
  let expired = try
    documents.accept_remote(newer, Some(newer_head), action)
  catch {
    ExpiredAction => true
  } noraise {
    _ => false
  }
  assert_true(expired)
}

///|
test "remote update capability expires when catalog observes a newer head" {
  let (documents, replica, _, remote) = remote_fixture(
    remote_revision(2.0, "remote two"),
  )
  guard remote is UpdateAvailable(action) else { fail("available update") }
  let newer_head = @source_repository.RemoteHead::Present(
    @source_repository.SavedRevision::parse(3.0) catch {
      _ => abort("valid revision")
    },
  )
  assert_true(
    documents.remote_state(replica, Some(newer_head))
    is RemoteState::RemoteAhead,
  )
  let expired = try
    documents.accept_remote(replica, Some(newer_head), action)
  catch {
    ExpiredAction => true
  } noraise {
    _ => false
  }
  assert_true(expired)
}

///|
test "newer catalog deletion replaces a stored update without exposing its action" {
  let (documents, replica, _, _) = remote_fixture(
    remote_revision(2.0, "remote two"),
  )
  let deleted = @source_repository.RemoteHead::Deleted(
    @source_repository.SavedRevision::parse(3.0) catch {
      _ => abort("valid revision")
    },
  )
  assert_true(
    documents.remote_state(replica, Some(deleted))
    is RemoteState::DeletedRemotely,
  )
}

///|
test "durable remote update remains available without a catalog entry" {
  let (documents, replica, _, _) = remote_fixture(
    remote_revision(2.0, "remote"),
  )
  guard documents.remote_state(replica, None)
    is RemoteState::UpdateAvailable(action) else {
    fail("durable update remains available")
  }
  assert_true(
    documents.accept_remote(replica, None, action)
    is RemoteAcceptance::Opened(_, _, _),
  )
}

///|
test "older catalog entry cannot erase a durable remote deletion" {
  let deleted = @source_repository.RemoteDocument::Deleted(
    @source_repository.SavedRevision::parse(2.0) catch {
      _ => abort("valid revision")
    },
  )
  let (documents, replica, _, _) = remote_fixture(deleted)
  let older = @source_repository.RemoteHead::Present(
    @source_repository.SavedRevision::parse(1.0) catch {
      _ => abort("valid revision")
    },
  )
  guard documents.remote_state(replica, Some(older))
    is RemoteState::DeletionAvailable(action) else {
    fail("durable deletion remains available")
  }
  assert_true(
    documents.accept_remote(replica, Some(older), action)
    is RemoteAcceptance::Removed(_, _),
  )
}

///|
test "accepting a remote update replaces only the parsed replica revision" {
  let (documents, replica, head, remote) = remote_fixture(
    remote_revision(2.0, "remote"),
  )
  guard remote is UpdateAvailable(action) else { fail("available update") }
  guard documents.accept_remote(replica, Some(head), action)
    is RemoteAcceptance::Opened(documents, document, write) else {
    fail("accepted update")
  }
  let key = Key::replica(replica.account(), replica.document_id())
  assert_eq(document.text(), "remote")
  assert_eq(documents.text(key), Some("remote"))
  assert_eq(write.replica().document(), Some(document))
}

///|
test "accepting a remote deletion removes the working copy without inventing text" {
  let deleted = @source_repository.RemoteDocument::Deleted(
    @source_repository.SavedRevision::parse(2.0) catch {
      _ => abort("valid revision")
    },
  )
  let (documents, replica, head, remote) = remote_fixture(deleted)
  guard remote is DeletionAvailable(action) else { fail("remote deletion") }
  guard documents.accept_remote(replica, Some(head), action)
    is RemoteAcceptance::Removed(documents, write) else {
    fail("accepted deletion")
  }
  let key = Key::replica(replica.account(), replica.document_id())
  assert_eq(documents.text(key), None)
  assert_eq(write.replica().document(), None)
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

///|
fn accepted_remote_write(
  replica : @source_repository.DocumentReplica,
  remote : @source_repository.RemoteDocument,
) -> @source_repository.ReplicaWrite {
  guard replica.reconcile(remote)
    is @source_repository.ReconcilePlan::Persist(observed) &&
    observed.replica().remote_update() is Some(update) else {
    abort("available remote update")
  }
  update.accept()
}

///|
test "replica commit refreshes only an unmounted clean working copy" {
  let account = account_id("account")
  let document = documents_test_document("one", "base")
  let first = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid revision")
  }
  let base = @source_repository.DocumentReplica::receive(
    account, document, first,
  )
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(base)
  let key = Key::replica(account, document.id())
  let write = accepted_remote_write(base, remote_revision(2.0, "remote"))

  let clean = State::State(saved).project_account(account)
  let (refreshed, _) = clean.reduce(
    FeedbackReceived(ReplicaSettled(write, None)),
  )
  assert_eq(refreshed.text(key), Some("remote"))

  let (mounted, _) = clean.reduce(
    FeedbackReceived(ReplicaSettled(write, Some(key))),
  )
  assert_eq(mounted.text(key), Some("base"))

  let (edited, _) = clean.reduce(TextChanged(key, "local"))
  let (edited, _) = edited.reduce(FeedbackReceived(ReplicaSettled(write, None)))
  assert_eq(edited.text(key), Some("local"))
}
