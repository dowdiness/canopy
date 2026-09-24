///|
fn fork_fixture() -> (
  State,
  @source_repository.AccountId,
  Key,
  @source_repository.ReplicaWrite,
) {
  let account = account_id("account")
  let document = documents_test_document("one", "local")
  let remote = @source_repository.RemoteDocument::Present(
    @source_repository.SavedRevision::parse(1.0) catch {
      _ => abort("valid revision")
    },
    "remote",
  )
  let initial = @source_repository.DocumentReplica(account, document)
  guard initial.reconcile(remote)
    is @source_repository.ReconcilePlan::Persist(diverged) else {
    abort("diverged replica")
  }
  let replica = diverged.replica()
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(replica) catch {
      _ => abort("valid replica")
    }
  let write = replica.fork(document_id("recovery")) catch {
    _ => abort("valid recovery")
  }
  (
    State::State(saved).project_account(account),
    account,
    Key::replica(account, document.id()),
    write,
  )
}

///|
test "fork transfers the working copy after an eligible Replica edit" {
  let (documents, account, original, write) = fork_fixture()
  let (documents, _) = documents.reduce(TextChanged(original, "latest"))
  let (documents, effects) = documents.reduce(
    ApplyPendingEdit(original, pending_revision(documents, original)),
  )
  guard effects is [SaveReplica(edit)] else { fail("eligible edit") }
  assert_eq(edit.document().text(), "latest")

  let documents = documents.begin_fork(write) catch { _ => abort("valid fork") }
  let recovery = Key::source(document_id("recovery"))
  assert_eq(documents.text(original), None)
  assert_eq(documents.text(recovery), Some("latest"))
  assert_eq(
    documents.replica_owner(recovery),
    Some((account, document_id("one"))),
  )
  let projected = documents
    .project_account(account_id("other"))
    .project_account(account)
  assert_eq(projected.text(original), None)
  assert_eq(projected.text(recovery), Some("latest"))
}

///|
test "edit during fork remains local and resumes ordinary Source persistence" {
  let (documents, _, original, write) = fork_fixture()
  let recovery = Key::source(document_id("recovery"))
  let documents = documents.begin_fork(write) catch { _ => abort("valid fork") }
  let (documents, _) = documents.reduce(TextChanged(recovery, "newer local"))
  let (documents, effects) = documents.reduce(
    ApplyPendingEdit(recovery, pending_revision(documents, recovery)),
  )
  assert_true(effects.is_empty())

  let (documents, effects) = documents.reduce(
    FeedbackReceived(ReplicaSettled(write, None)),
  )
  assert_eq(documents.text(original), Some("remote"))
  assert_eq(documents.text(recovery), Some("newer local"))
  assert_eq(documents.replica_owner(recovery), None)
  guard effects is [PersistSource(operation)] else {
    fail("new recovery edit must persist")
  }
  assert_eq(operation.document.text(), "newer local")
}

///|
test "fork preserves composition state and working-copy identity" {
  let (documents, _, original, write) = fork_fixture()
  let recovery = Key::source(document_id("recovery"))
  let (documents, _) = documents.reduce(CompositionStarted(original))
  let documents = documents.begin_fork(write) catch { _ => abort("valid fork") }
  assert_true(documents.is_composing(recovery))
  let (documents, _) = documents.reduce(
    FeedbackReceived(ReplicaSettled(write, None)),
  )
  assert_true(documents.is_composing(recovery))
}

///|
test "a newer committed Replica refreshes the unmounted branch created by a fork" {
  let (documents, _, original, fork) = fork_fixture()
  let recovery = Key::source(document_id("recovery"))
  let documents = documents.begin_fork(fork) catch { _ => abort("valid fork") }
  let (documents, _) = documents.reduce(
    FeedbackReceived(ReplicaSettled(fork, Some(recovery))),
  )
  assert_eq(documents.text(original), Some("remote"))

  let next = @source_repository.RemoteDocument::Present(
    @source_repository.SavedRevision::parse(2.0) catch {
      _ => abort("valid revision")
    },
    "newer remote",
  )
  guard fork.replica().reconcile(next)
    is @source_repository.ReconcilePlan::Persist(available) &&
    available
    .replica()
    .open(
      @source_repository.SavedRevision::parse(2.0) catch {
        _ => abort("valid revision")
      },
    )
    is @source_repository.OpenStep::Persist(write) else {
    fail("newer remote write")
  }
  let (documents, _) = documents.reduce(
    FeedbackReceived(ReplicaSettled(write, Some(recovery))),
  )
  assert_eq(documents.text(original), Some("newer remote"))
  assert_eq(documents.text(recovery), Some("local"))
}
