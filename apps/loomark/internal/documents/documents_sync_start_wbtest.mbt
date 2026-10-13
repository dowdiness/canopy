///|
fn sync_applied(outcome : Update) -> (Model, ReadOnlyArray[Action]) {
  match outcome {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("expected current update to apply")
  }
}

///|
fn sync_changed(model : Model, outcome : Edit) -> (Model, ReadOnlyArray[Action]) {
  match outcome {
    Changed(transition) => (transition.model, transition.effects)
    SameText => (model, [])
  }
}

///|
fn sync_deleted(model : Model, outcome : Delete) -> (Model, ReadOnlyArray[Action]) {
  match outcome {
    Accepted(transition) => (transition.model, transition.effects)
    AlreadyPending => (model, [])
  }
}

///|
test "sync start atomically replaces source membership with a replica" {
  let account = account_id("account")
  let (documents, replica) = begin_sync_start(
    Model::Model(documents_test_snapshot()),
    account,
  )
  let (documents, effects) = sync_applied(documents.update(Promoted(replica.promote_source())))
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
    Model::Model(documents_test_snapshot()),
    account,
  )
  let (documents, _) = sync_changed(documents, documents.edit(source_key("one"), "latest"))
  let (documents, effects) = sync_applied(documents.update(ApplyPendingEdit(source_key("one"), pending_revision(documents, source_key("one")))))
  assert_true(effects.is_empty())
  let (documents, effects) = sync_applied(documents.update(Promoted(replica.promote_source())))
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
    Model::Model(documents_test_snapshot()),
    account,
  )
  let (documents, _) = sync_changed(documents, documents.edit(source_key("one"), "latest"))
  let (documents, _) = sync_applied(documents.update(ApplyPendingEdit(source_key("one"), pending_revision(documents, source_key("one")))))
  let (documents, effects) = sync_applied(documents.update(PromotionFailed(replica.promote_source(), WriteFailed)))
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
    Model::Model(documents_test_snapshot()),
    account,
  )
  let (documents, _) = sync_applied(documents.update(CompositionStarted(source_key("one"))))
  let (documents, _) = sync_changed(documents, documents.edit(source_key("one"), "composing"))
  let (documents, _) = sync_applied(documents.update(ApplyPendingEdit(source_key("one"), pending_revision(documents, source_key("one")))))
  let (documents, effects) = sync_applied(documents.update(Promoted(replica.promote_source())))
  assert_true(effects.is_empty())
  let key = Key::replica(account, document_id("one"))
  assert_true(documents.is_composing(key))
  let (_, effects) = sync_applied(documents.update(CompositionEnded(key)))
  guard effects is [SaveReplica(submission)] else {
    fail("composition end must save through replica persistence")
  }
  assert_eq(submission.durable().account(), account)
  assert_eq(submission.document().text(), "composing")
}

///|
test "sync start waits for acknowledged source persistence" {
  let account = account_id("account")
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = sync_changed(documents, source_key("one"), "new"))
  assert_true(documents.sync_start(source_key("one"), account) is Unavailable)
}

///|
test "maximum timer follows a document across sync-start rekeying" {
  let account = account_id("account")
  let (documents, replica) = begin_sync_start(
    Model::Model(documents_test_snapshot()),
    account,
  )
  let (documents, effects) = sync_changed(documents, documents.edit(source_key("one"), "latest"))
  guard effects is [ArmMaximum(maximum)] else { fail("maximum") }
  let (documents, _) = sync_applied(documents.update(Promoted(replica.promote_source())))
  let (_, effects) = sync_applied(documents.update(MaximumElapsed(maximum)))
  guard effects is [SaveReplica(submission)] else { fail("replica save") }
  assert_eq(submission.durable().account(), account)
  assert_eq(submission.document().text(), "latest")
}
