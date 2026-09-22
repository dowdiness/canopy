///|
fn begin_sync_start(
  documents : State,
  account : @source_repository.AccountId,
) -> (State, @source_repository.DocumentReplica) {
  let document = documents.document(source_key("one")).unwrap()
  guard documents.sync_start(source_key("one"), account) is Ready(action) else {
    abort("sync start unavailable")
  }
  let (documents, effects) = documents.start_sync(action) catch {
    _ => abort("valid sync start")
  }
  guard effects is [StoreReplica(write)] &&
    write is @source_repository.ReplicaWrite::PromoteSource(replica) &&
    replica.account() == account &&
    replica.document() == document else {
    abort("sync start did not begin")
  }
  (documents, @source_repository.DocumentReplica(account, document))
}

///|
test "sync start atomically replaces source membership with a replica" {
  let account = account_id("account")
  let (documents, replica) = begin_sync_start(
    State::State(documents_test_snapshot()),
    account,
  )
  let (documents, effects) = documents.reduce(
    FeedbackReceived(PromotionCompleted(replica.promote_source(), Ok(()))),
  )
  let key = Key::replica(account, document_id("one"))
  assert_true(effects.is_empty())
  assert_eq(documents.snapshot().find(document_id("one")), None)
  assert_eq(
    documents.snapshot().replica(account, document_id("one")),
    Some(replica),
  )
  assert_eq(documents.text(source_key("one")), None)
  assert_eq(documents.text(key), Some("one"))
}

///|
test "edit during sync start follows the document into replica storage" {
  let account = account_id("account")
  let (documents, replica) = begin_sync_start(
    State::State(documents_test_snapshot()),
    account,
  )
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "latest"),
  )
  let (documents, effects) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  assert_true(effects.is_empty())
  let (documents, effects) = documents.reduce(
    FeedbackReceived(PromotionCompleted(replica.promote_source(), Ok(()))),
  )
  guard effects is [SaveReplica(submission)] else {
    fail("latest text must continue through replica persistence")
  }
  assert_eq(submission.durable().account(), account)
  assert_eq(submission.document().text(), "latest")
  assert_eq(
    documents.text(Key::replica(account, document_id("one"))),
    Some("latest"),
  )
}

///|
test "failed sync start resumes local persistence for a newer edit" {
  let account = account_id("account")
  let (documents, replica) = begin_sync_start(
    State::State(documents_test_snapshot()),
    account,
  )
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "latest"),
  )
  let (documents, _) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  let (documents, effects) = documents.reduce(
    FeedbackReceived(
      PromotionCompleted(replica.promote_source(), Err(WriteFailed)),
    ),
  )
  guard effects is [PersistSource(latest)] else {
    fail("latest edit must return to source persistence")
  }
  assert_eq(latest.document.text(), "latest")
  assert_eq(documents.text(source_key("one")), Some("latest"))
  assert_eq(
    documents.snapshot().find(document_id("one")).map(d => d.text()),
    Some("one"),
  )
}

///|
test "composition remains active while sync start changes persistence owner" {
  let account = account_id("account")
  let (documents, replica) = begin_sync_start(
    State::State(documents_test_snapshot()),
    account,
  )
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "composing"),
  )
  let (documents, _) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  let (documents, effects) = documents.reduce(
    FeedbackReceived(PromotionCompleted(replica.promote_source(), Ok(()))),
  )
  assert_true(effects.is_empty())
  let key = Key::replica(account, document_id("one"))
  assert_true(documents.is_composing(key))
  let (_, effects) = documents.reduce(CompositionEnded(key))
  guard effects is [SaveReplica(submission)] else {
    fail("composition end must save through replica persistence")
  }
  assert_eq(submission.durable().account(), account)
  assert_eq(submission.document().text(), "composing")
}

///|
test "sync start waits for acknowledged source persistence" {
  let account = account_id("account")
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "new"))
  assert_true(documents.sync_start(source_key("one"), account) is Unavailable)
}

///|
test "maximum timer follows a document across sync-start rekeying" {
  let account = account_id("account")
  let (documents, replica) = begin_sync_start(
    State::State(documents_test_snapshot()),
    account,
  )
  let (documents, effects) = documents.reduce(
    TextChanged(source_key("one"), "latest"),
  )
  guard effects is [ArmMaximum(maximum)] else { fail("maximum") }
  let (documents, _) = documents.reduce(
    FeedbackReceived(PromotionCompleted(replica.promote_source(), Ok(()))),
  )
  let (_, effects) = documents.reduce(FeedbackReceived(MaximumElapsed(maximum)))
  guard effects is [SaveReplica(submission)] else { fail("replica save") }
  assert_eq(submission.durable().account(), account)
  assert_eq(submission.document().text(), "latest")
}
