///|
fn durability_applied(outcome : Update) -> (Model, ReadOnlyArray[Action]) {
  match outcome {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => abort("expected current update to apply")
  }
}

///|
fn durability_changed(
  _model : Model,
  outcome : Edit,
) -> (Model, ReadOnlyArray[Action]) {
  match outcome {
    Changed(transition) => (transition.model, transition.effects)
    SameText => abort("expected changed text")
  }
}

///|
fn durability_deleted(
  _model : Model,
  outcome : Delete,
) -> (Model, ReadOnlyArray[Action]) {
  match outcome {
    Accepted(transition) => (transition.model, transition.effects)
    AlreadyPending => abort("expected accepted deletion")
  }
}

///|
test "untouched new document is locally durable" {
  let documents = Model::Model(documents_test_snapshot())
  let documents = documents.create(document_id("new")).model
  assert_true(
    documents.local_durability(@replica_persistence.State::State())
    is LocalDurability::Durable,
  )
}

///|
test "imported blank document is not durable before persistence" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = durability_applied(
    documents.update(Imported(document_id("new"), "")),
  )
  assert_true(
    documents.local_durability(@replica_persistence.State::State())
    is LocalDurability::Saving,
  )
}

///|
test "composition requires input before local durability" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = durability_applied(
    documents.update(CompositionStarted(source_key("one"))),
  )
  assert_true(
    documents.local_durability(@replica_persistence.State::State())
    is LocalDurability::AwaitingInput,
  )
}

///|
test "hidden replica candidates are not committed text and failures unblock saving" {
  let replica = @source_repository.DocumentReplica(
    account_id("hidden"),
    documents_test_document("replica", "durable"),
  )
  let saved = documents_test_snapshot().apply_replica(replica)
  guard replica.edit("accepted") is @source_repository.EditPlan::Persist(write) else {
    fail("changed text")
  }
  let (persistence, attempt) = @replica_persistence.State().submit(write)
  let documents = Model(saved)
  assert_true(
    documents.local_durability(persistence) is LocalDurability::Saving,
  )
  let (failed, _) = persistence.complete(
    attempt.unwrap(),
    Err(@source_repository.ReplicaFailure::StorageUnavailable),
  )
  assert_true(documents.local_durability(failed) is LocalDurability::Failed(_))
  let committed = Model(saved.apply_replica_write(write))
  assert_true(
    committed.local_durability(persistence) is LocalDurability::Durable,
  )
}

///|
test "queued return to durable text still waits for older in-flight write" {
  let replica = @source_repository.DocumentReplica(
    account_id("hidden"),
    documents_test_document("replica", "durable"),
  )
  let saved = documents_test_snapshot().apply_replica(replica)
  guard replica.edit("intermediate")
    is @source_repository.EditPlan::Persist(older) else {
    fail("changed text")
  }
  guard older.replica().edit("durable")
    is @source_repository.EditPlan::Persist(newer) else {
    fail("changed back")
  }
  let (persistence, _) = @replica_persistence.State().submit(older)
  let (persistence, _) = persistence.submit(newer)
  assert_true(
    Model(saved).local_durability(persistence) is LocalDurability::Saving,
  )
}

///|
test "replica deletion waits for local intent but not durable remote delivery" {
  let replica = @source_repository.DocumentReplica::receive(
    account_id("hidden"),
    documents_test_document("replica", "durable"),
    @source_repository.SavedRevision::parse(1),
  )
  let saved = documents_test_snapshot().apply_replica(replica)
  let deletion = replica.request_deletion()
  let (persistence, _) = @replica_persistence.State().submit(deletion)
  assert_true(
    Model(saved).local_durability(persistence) is LocalDurability::Saving,
  )
  let durable = saved.apply_replica_write(deletion)
  assert_true(
    Model(durable).local_durability(persistence) is LocalDurability::Durable,
  )
}

///|
test "promotion waits for ownership commit and newer accepted text" {
  let source = documents_test_document("one", "one")
  let account = account_id("account")
  let write = @source_repository.DocumentReplica(account, source).promote_source()
  let (persistence, _) = @replica_persistence.State().submit(write)
  let documents = Model(documents_test_snapshot())
  assert_true(
    documents.local_durability(persistence) is LocalDurability::Saving,
  )
  let committed = documents.saved.apply_replica_write(write)
  assert_true(
    Model(committed).local_durability(persistence) is LocalDurability::Durable,
  )
  let (pending, _) = durability_changed(
    documents,
    documents.edit(source_key("one"), "newer accepted text"),
  )
  assert_true(pending.local_durability(persistence) is LocalDurability::Saving)
}

///|
test "fork recovery commit does not cover text accepted after forking" {
  let (documents, _, _, fork) = fork_fixture()
  let documents = documents.begin_fork(fork) catch { _ => abort("valid fork") }
  let (persistence, _) = @replica_persistence.State().submit(fork)
  assert_true(
    documents.local_durability(persistence) is LocalDurability::Saving,
  )
}

///|
test "imported blank save failure releases local durability instead of waiting forever" {
  let documents = Model(documents_test_snapshot())
  let (documents, actions) = durability_applied(
    documents.update(Imported(document_id("blank"), "")),
  )
  guard actions[0] is PersistSource(operation) else {
    fail("import persists immediately")
  }
  let (documents, _) = durability_applied(
    documents.update(
      SaveFailed(operation, @source_repository.SaveFailure::StorageUnavailable),
    ),
  )
  assert_true(
    documents.local_durability(@replica_persistence.State())
    is LocalDurability::Failed(_),
  )
}

///|
test "saving retries failed replica deletion without retaining stale failure" {
  let replica = @source_repository.DocumentReplica::receive(
    account_id("account"),
    documents_test_document("replica", "durable"),
    @source_repository.SavedRevision::parse(1),
  )
  let saved = documents_test_snapshot().apply_replica(replica)
  let key = Key::replica(replica.account(), replica.document_id())
  let write = replica.request_deletion()
  let (documents, _) = durability_deleted(
    Model(saved),
    Model(saved).delete(key),
  )
  let (documents, _) = durability_applied(
    documents.update(
      ReplicaDeletionFailed(
        write,
        @source_repository.ReplicaFailure::StorageUnavailable,
      ),
    ),
  )
  let (retrying, _) = @replica_persistence.State().submit(write)
  let saved_after_changes = documents.save_changes() catch {
    _ => abort("save changes must recover the replica lane")
  }
  assert_true(saved_after_changes.model.local_durability(retrying) is Saving)
}
