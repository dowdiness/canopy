///|
fn fork_fixture() -> (
  Model,
  @source_repository.AccountId,
  Key,
  @source_repository.ReplicaWrite,
) {
  let account = account_id("account")
  let revision = @source_repository.SavedRevision::parse(1) catch {
    _ => abort("valid revision")
  }
  let base = @source_repository.DocumentReplica::receive(
    account,
    documents_test_document("one", "base"),
    revision,
  )
  let edited = match base.edit("local") {
    @source_repository.EditPlan::Persist(write) => write.replica()
    _ => abort("local edit")
  }
  let remote_revision = @source_repository.SavedRevision::parse(2) catch {
    _ => abort("valid revision")
  }
  let divergence = match
    edited.reconcile(
      @source_repository.RemoteDocument::Present(remote_revision, "remote"),
    ) {
    @source_repository.ReconcilePlan::Persist(write) => write.replica()
    _ => abort("divergence")
  }
  let fork = divergence.fork(document_id("recovery")) catch {
    _ => abort("valid recovery identity")
  }
  let saved = @source_repository.SavedDocuments::from_documents([])
    .unwrap()
    .apply_replica(divergence) catch {
      _ => abort("valid replica")
    }
  (
    Model(saved).project_account(account),
    account,
    Key::replica(account, document_id("one")),
    fork,
  )
}

///|
fn fork_applied(outcome : Update) -> (Model, ReadOnlyArray[Action]) {
  match outcome {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => abort("expected current update to apply")
  }
}

///|
fn fork_changed(
  model : Model,
  key : Key,
  text : String,
) -> (Model, ReadOnlyArray[Action]) {
  match (model.edit(key, text) catch { _ => abort("valid edit") }) {
    Changed(transition) => (transition.model, transition.effects)
    SameText => abort("expected changed text")
  }
}

///|
test "fork transfers the working copy after an eligible Replica edit" {
  let (documents, account, original, write) = fork_fixture()
  let (documents, _) = fork_changed(documents, original, "latest")
  let (documents, effects) = fork_applied(
    documents.update(
      ApplyPendingEdit(original, pending_revision(documents, original)),
    ),
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
  let (documents, _) = fork_changed(documents, recovery, "newer local")
  let (documents, effects) = fork_applied(
    documents.update(
      ApplyPendingEdit(recovery, pending_revision(documents, recovery)),
    ),
  )
  assert_true(effects.is_empty())

  let (documents, effects) = fork_applied(
    documents.update(ReplicaSettled(write, None)),
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
  let (documents, _) = fork_applied(
    documents.update(CompositionStarted(original)),
  )
  let documents = documents.begin_fork(write) catch { _ => abort("valid fork") }
  assert_true(documents.is_composing(recovery))
  let (documents, _) = fork_applied(
    documents.update(ReplicaSettled(write, None)),
  )
  assert_true(documents.is_composing(recovery))
}

///|
test "a newer committed Replica refreshes the unmounted branch created by a fork" {
  let (documents, _, original, fork) = fork_fixture()
  let recovery = Key::source(document_id("recovery"))
  let documents = documents.begin_fork(fork) catch { _ => abort("valid fork") }
  let (documents, _) = fork_applied(
    documents.update(ReplicaSettled(fork, Some(recovery))),
  )
  assert_eq(documents.text(original), Some("remote"))

  let revision = @source_repository.SavedRevision::parse(3.0) catch {
    _ => abort("valid revision")
  }
  let next = @source_repository.RemoteDocument::Present(
    revision, "newer remote",
  )
  guard fork.replica().reconcile(next)
    is @source_repository.ReconcilePlan::Persist(available) &&
    available.replica().open(revision)
    is @source_repository.OpenStep::Persist(write) else {
    fail("newer remote write")
  }
  let (documents, _) = fork_applied(
    documents.update(ReplicaSettled(write, Some(recovery))),
  )
  assert_eq(documents.text(original), Some("newer remote"))
  assert_eq(documents.text(recovery), Some("local"))
}
