///|
test "untouched new document is locally durable" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(New(document_id("new")))
  assert_true(
    documents.local_durability(@replica_persistence.State::State())
    is LocalDurability::Durable,
  )
}

///|
test "imported blank document is not durable before persistence" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(Imported(document_id("new"), ""))
  assert_true(
    documents.local_durability(@replica_persistence.State::State())
    is LocalDurability::Saving,
  )
}

///|
test "composition requires input before local durability" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
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
  let documents = State(saved)
  assert_true(
    documents.local_durability(persistence) is LocalDurability::Saving,
  )
  let (failed, _) = persistence.complete(
    attempt.unwrap(),
    Err(@source_repository.ReplicaFailure::StorageUnavailable),
  )
  assert_true(documents.local_durability(failed) is LocalDurability::Failed(_))
  let committed = State(saved.apply_replica_write(write))
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
    State(saved).local_durability(persistence) is LocalDurability::Saving,
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
    State(saved).local_durability(persistence) is LocalDurability::Saving,
  )
  let durable = saved.apply_replica_write(deletion)
  assert_true(
    State(durable).local_durability(persistence) is LocalDurability::Durable,
  )
}

///|
test "promotion waits for ownership commit and newer accepted text" {
  let source = documents_test_document("one", "one")
  let account = account_id("account")
  let write = @source_repository.DocumentReplica(account, source).promote_source()
  let (persistence, _) = @replica_persistence.State().submit(write)
  let documents = State(documents_test_snapshot())
  assert_true(
    documents.local_durability(persistence) is LocalDurability::Saving,
  )
  let committed = documents.saved.apply_replica_write(write)
  assert_true(
    State(committed).local_durability(persistence) is LocalDurability::Durable,
  )
  let pending = {
    ..documents,
    saved: committed,
    records: replace_record(documents.records, source_key("one"), record => {
      ..record,
      persistence: StartingSync(account, source),
      document: source.update("newer accepted text"),
    }),
  }
  assert_true(pending.local_durability(persistence) is LocalDurability::Saving)
}

///|
test "fork recovery commit does not cover text accepted after forking" {
  let recovery = documents_test_document("one", "recovery")
  let documents = State(documents_test_snapshot())
  let documents = {
    ..documents,
    saved: @source_repository.SavedDocuments::from_documents([recovery]).unwrap(),
    records: [
      {
        persistence: Forking({
          account: account_id("account"),
          original: document_id("original"),
          recovery,
        }),
        document: recovery.update("newer recovery"),
        version: 1,
        edit: Idle,
        save: Saved,
        lead_source: Unlisted,
      },
    ],
  }
  assert_true(
    documents.local_durability(@replica_persistence.State())
    is LocalDurability::Saving,
  )
}

///|
test "imported blank save failure releases local durability instead of waiting forever" {
  let documents = State(documents_test_snapshot())
  let (documents, actions) = documents.reduce(
    Imported(document_id("blank"), ""),
  )
  guard actions[0] is PersistSource(operation) else {
    fail("import persists immediately")
  }
  let (documents, _) = documents.reduce(
    FeedbackReceived(
      SaveCompleted(
        operation,
        @source_repository.SaveResult::SaveFailed(
          @source_repository.SaveFailure::StorageUnavailable,
        ),
      ),
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
  let (documents, _) = State(saved).reduce(DeleteConfirmed(key))
  let (documents, _) = documents.reduce(
    FeedbackReceived(
      ReplicaDeletionFailed(
        write,
        @source_repository.ReplicaFailure::StorageUnavailable,
      ),
    ),
  )
  let (retrying, _) = @replica_persistence.State().submit(write)
  let (saved_after_changes, _) = documents.save_changes()
  assert_true(
    saved_after_changes.local_durability(retrying) is LocalDurability::Saving,
  )
}
