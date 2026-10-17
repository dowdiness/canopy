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
test "promotion commit remains non-durable until newer accepted text is stored" {
  let account = account_id("account")
  let (documents, replica) = begin_sync_start(
    Model(documents_test_snapshot()),
    account,
  )
  let promotion = replica.promote_source()
  let (persistence, attempt) = @replica_persistence.State().submit(promotion)
  guard attempt is Some(attempt) else { fail("promotion must start") }
  let (documents, _) = durability_changed(
    documents,
    documents.edit(source_key("one"), "newer accepted text"),
  )
  assert_true(documents.local_durability(persistence) is Saving)

  let (persistence, completion) = persistence.complete(attempt, Ok(()))
  guard completion is @replica_persistence.Completion::Current(committed) else {
    fail("promotion must finish without queued writes")
  }
  let (documents, effects) = durability_applied(
    documents.update(Promoted(committed)),
  )
  let key = Key::replica(account, document_id("one"))
  assert_true(effects.is_empty())
  assert_eq(persistence.pending_writes().count(), 0)
  assert_eq(documents.snapshot().find(document_id("one")), None)
  assert_eq(
    documents
    .snapshot()
    .replica(account, document_id("one"))
    .bind(replica => replica.document()),
    Some(documents_test_document("one", "one")),
  )
  assert_eq(documents.text(key), Some("newer accepted text"))
  assert_true(documents.local_durability(persistence) is Saving)

  guard documents.pending_edits() is [(pending_key, revision)] &&
    pending_key == key else {
    fail("newer text must retain its pending edit after promotion")
  }
  let (documents, effects) = durability_applied(
    documents.update(ApplyPendingEdit(key, revision)),
  )
  guard effects is [SaveReplica(edit)] else {
    fail("newer text must save through the promoted Replica")
  }
  assert_eq(edit.document().text(), "newer accepted text")
  assert_true(documents.local_durability(persistence) is Saving)
  guard edit.durable().edit(edit.document().text())
    is @source_repository.EditPlan::Persist(write) else {
    fail("newer Replica text must require persistence")
  }
  let (persistence, attempt) = persistence.submit(write)
  guard attempt is Some(attempt) else { fail("newer Replica write must start") }
  assert_true(documents.local_durability(persistence) is Saving)
  let (persistence, completion) = persistence.complete(attempt, Ok(()))
  guard completion is @replica_persistence.Completion::Current(committed) else {
    fail("newer Replica write must finish")
  }
  let (documents, effects) = durability_applied(
    documents.update(ReplicaSettled(committed, Some(key))),
  )
  assert_true(effects.is_empty())
  assert_eq(
    documents
    .snapshot()
    .replica(account, document_id("one"))
    .bind(replica => replica.document()),
    Some(edit.document()),
  )
  assert_true(documents.local_durability(persistence) is Durable)
}

///|
test "fork recovery commit remains non-durable until newer accepted text is stored" {
  let (documents, _, _, fork) = fork_fixture()
  guard fork is @source_repository.ReplicaWrite::Fork(_, recovery) else {
    fail("fixture must provide a recovery write")
  }
  let key = Key::source(recovery.id())
  let documents = documents.begin_fork(fork)
  let (persistence, attempt) = @replica_persistence.State().submit(fork)
  guard attempt is Some(attempt) else { fail("fork must start") }
  let (documents, _) = durability_changed(
    documents,
    documents.edit(key, "newer recovery"),
  )
  assert_true(documents.local_durability(persistence) is Saving)

  let (persistence, completion) = persistence.complete(attempt, Ok(()))
  guard completion is @replica_persistence.Completion::Current(committed) else {
    fail("fork must finish without queued writes")
  }
  let (documents, effects) = durability_applied(
    documents.update(ReplicaSettled(committed, Some(key))),
  )
  assert_true(effects.is_empty())
  assert_eq(persistence.pending_writes().count(), 0)
  assert_eq(documents.snapshot().find(recovery.id()), Some(recovery))
  assert_eq(documents.text(key), Some("newer recovery"))
  assert_eq(documents.replica_owner(key), None)
  assert_true(documents.local_durability(persistence) is Saving)

  guard documents.pending_edits() is [(pending_key, revision)] &&
    pending_key == key else {
    fail("newer recovery text must retain its pending edit")
  }
  let (documents, effects) = durability_applied(
    documents.update(ApplyPendingEdit(key, revision)),
  )
  guard effects is [PersistSource(operation)] else {
    fail("newer recovery text must save as a Source")
  }
  assert_eq(operation.document.text(), "newer recovery")
  assert_true(documents.local_durability(persistence) is Saving)
  let (documents, effects) = durability_applied(
    documents.update(Saved(operation, operation.document)),
  )
  assert_true(effects.is_empty())
  assert_eq(documents.snapshot().find(recovery.id()), Some(operation.document))
  assert_true(documents.local_durability(persistence) is Durable)
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
