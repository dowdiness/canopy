///|
fn test_account(value : String) -> @source_repository.AccountId {
  @source_repository.AccountId::parse(value) catch {
    _ => abort("invalid test account")
  }
}

///|
fn test_document_id(
  value? : String = "document",
) -> @source_repository.DocumentId {
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
fn test_document(text : String) -> @source_repository.Document {
  @source_repository.Document::create(test_document_id(), text)
}

///|
fn test_operation_id() -> @source_repository.OperationId {
  @source_repository.OperationId::parse("10000000-0000-4000-8000-000000000001") catch {
    _ => abort("invalid test operation id")
  }
}

///|
fn revision(value : Double) -> @source_repository.SavedRevision {
  @source_repository.SavedRevision::parse(value) catch {
    _ => abort("invalid revision")
  }
}

///|
fn edit_write(
  checkpoint : @source_repository.SyncCheckpoint,
  text : String,
) -> @source_repository.CheckpointWrite {
  guard checkpoint.edit(text) is @source_repository.EditPlan::Persist(write) else {
    abort("expected edit write")
  }
  write
}

///|
fn sending_checkpoint() -> @source_repository.SyncCheckpoint {
  let checkpoint = @source_repository.SyncCheckpoint::enroll(
    test_account("account"),
    test_document("sent"),
  )
  guard checkpoint.plan_save() is @source_repository.OperationPlan::Start(draft) else {
    abort("expected save draft")
  }
  draft.start(test_operation_id()).checkpoint()
}

///|
fn signed_in(account : @source_repository.AccountId) -> State {
  let (state, lookup) = State().begin_lookup()
  state.resolved(lookup, Resolved(account, "Writer")).0
}

///|
fn with_catalog(
  state : State,
  account : @source_repository.AccountId,
  entries : Array[@source_repository.RemoteEntry],
) -> State {
  let (state, discovery) = state.begin_discovery()
  state.discovered(account, discovery.unwrap(), Some(entries)).0
}

///|
test "only the latest account lookup can select an account" {
  let (state, first) = State().begin_lookup()
  let (state, second) = state.begin_lookup()
  let account = test_account("account-a")
  let (stale, selected) = state.resolved(first, Resolved(account, "A"))
  assert_eq(selected, None)
  assert_true(stale.session() == Resolving(second))
  let (current, selected) = stale.resolved(second, Resolved(account, "A"))
  assert_eq(selected, Some(AccountSelection::AccountSelected(account)))
  assert_true(current.session() == Current(account, "A"))
}

///|
test "writer coalesces to the newest eligible checkpoint" {
  let account = test_account("account")
  let first = edit_write(
    @source_repository.SyncCheckpoint::enroll(account, test_document("base")),
    "first",
  )
  let latest = edit_write(first.checkpoint(), "latest")
  let (state, active) = State().persist(first)
  let active = active.unwrap()
  let (state, duplicate) = state.persist(latest)
  assert_eq(duplicate, None)
  let (state, next) = state.stored(active.request_id(), first.checkpoint())
  let next = next.unwrap()
  assert_eq(next.write(), latest)
  let stale : Result[(State, Attempt?), CompletionError] = Ok(
    state.stored(active.request_id(), first.checkpoint()),
  ) catch {
    error => Err(error)
  }
  assert_eq(stale, Err(CompletionError::StaleCompletion))
}

///|
test "delivery capability prevents operation-id ABA" {
  let durable = sending_checkpoint()
  let state = signed_in(durable.account())
  guard state.drive(durable) is (state, Some(Deliver(first, _, _, _))) else {
    fail("first delivery")
  }
  let state = state.delivery_failed(durable, first, test_operation_id())
  guard state.drive(durable) is (state, Some(Deliver(second, _, _, _))) else {
    fail("second delivery")
  }
  assert_true(first != second)
  let stale : Result[(State, Attempt?), WorkError] = Ok(
    state.acknowledged(durable, first, test_operation_id(), revision(1.0)),
  ) catch {
    error => Err(error)
  }
  assert_eq(stale, Err(WorkError::StaleWork))
}

///|
test "reselecting an opening document reuses its checkpoint write" {
  let account = test_account("account")
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Remote",
  )
  guard signed_in(account).begin_open(entry)
    is (state, None, Some(GetRemote(effect, _, _, Open(first, expected)))) else {
    fail("open read")
  }
  let remote = @source_repository.RemoteDocument::Present(
    revision(2.0),
    "remote text",
  )
  let (state, attempt) = state.opened(
    effect,
    account,
    test_document_id(),
    first,
    expected,
    None,
    remote,
  )
  let attempt = attempt.unwrap()
  let (state, duplicate, action) = state.begin_open(entry)
  assert_eq(duplicate, None)
  assert_eq(action, None)
  guard state.pending_open() is Some((second, _, _, _)) else {
    fail("new open intent")
  }
  assert_true(first != second)
  let (_, next) = state.stored(
    attempt.request_id(),
    attempt.write().checkpoint(),
  )
  assert_eq(next, None)
}

///|
test "reselecting after storage failure restarts the retained write" {
  let account = test_account("account")
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Remote",
  )
  guard signed_in(account).begin_open(entry)
    is (state, None, Some(GetRemote(effect, _, _, Open(intent, expected)))) else {
    fail("open read")
  }
  let remote = @source_repository.RemoteDocument::Present(
    revision(2.0),
    "remote text",
  )
  let (state, attempt) = state.opened(
    effect,
    account,
    test_document_id(),
    intent,
    expected,
    None,
    remote,
  )
  let attempt = attempt.unwrap()
  let (state, _) = state.failed(
    attempt.request_id(),
    attempt.write().checkpoint(),
  )
  guard state.begin_open(entry) is (state, Some(retry), None) else {
    fail("storage retry")
  }
  assert_eq(retry.write(), attempt.write())
  assert_true(state.pending_open() is Some(_))
}

///|
test "newer reopen is a monotonic successor of the first checkpoint" {
  let account = test_account("account")
  let first_entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(1.0),
    "First",
  )
  guard signed_in(account).begin_open(first_entry)
    is (
      state,
      None,
      Some(GetRemote(first_effect, _, _, Open(first_intent, first_expected))),
    ) else {
    fail("first open")
  }
  let first_remote = @source_repository.RemoteDocument::Present(
    revision(1.0),
    "first text",
  )
  let (state, first_attempt) = state.opened(
    first_effect,
    account,
    test_document_id(),
    first_intent,
    first_expected,
    None,
    first_remote,
  )
  let first_attempt = first_attempt.unwrap()
  let second_entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Second",
  )
  guard state.begin_open(second_entry)
    is (
      state,
      None,
      Some(GetRemote(second_effect, _, _, Open(second_intent, second_expected))),
    ) else {
    fail("second open")
  }
  let second_remote = @source_repository.RemoteDocument::Present(
    revision(2.0),
    "second text",
  )
  let (state, duplicate) = state.opened(
    second_effect,
    account,
    test_document_id(),
    second_intent,
    second_expected,
    None,
    second_remote,
  )
  assert_eq(duplicate, None)
  let (state, second_attempt) = state.stored(
    first_attempt.request_id(),
    first_attempt.write().checkpoint(),
  )
  let second_attempt = second_attempt.unwrap()
  let second = second_attempt.write().checkpoint()
  assert_eq(
    second.generation(),
    first_attempt.write().checkpoint().generation() + 1.0,
  )
  assert_eq(second.baseline_revision(), 2.0)
  assert_eq(second.document().text(), "second text")
  let (state, next) = state.stored(second_attempt.request_id(), second)
  assert_eq(next, None)
  assert_true(state.pending_open() is Some(_))
}

///|
test "newer reopen advances a checkpoint that already became durable" {
  let account = test_account("account")
  let first_entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(1.0),
    "First",
  )
  guard signed_in(account).begin_open(first_entry)
    is (
      state,
      None,
      Some(GetRemote(first_effect, _, _, Open(first_intent, first_expected))),
    ) else {
    fail("first open")
  }
  let first_remote = @source_repository.RemoteDocument::Present(
    revision(1.0),
    "first text",
  )
  let (state, first_attempt) = state.opened(
    first_effect,
    account,
    test_document_id(),
    first_intent,
    first_expected,
    None,
    first_remote,
  )
  let first_attempt = first_attempt.unwrap()
  let first = first_attempt.write().checkpoint()
  let (state, next) = state.stored(first_attempt.request_id(), first)
  assert_eq(next, None)

  let second_entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Second",
  )
  guard state.begin_open(second_entry)
    is (
      state,
      None,
      Some(GetRemote(second_effect, _, _, Open(second_intent, second_expected))),
    ) else {
    fail("second open")
  }
  let second_remote = @source_repository.RemoteDocument::Present(
    revision(2.0),
    "second text",
  )
  let (_, second_attempt) = state.opened(
    second_effect,
    account,
    test_document_id(),
    second_intent,
    second_expected,
    Some(first),
    second_remote,
  )
  let second = second_attempt.unwrap().write().checkpoint()
  assert_eq(second.generation(), first.generation() + 1.0)
  assert_eq(second.baseline_revision(), 2.0)
  assert_eq(second.document().text(), "second text")
}

///|
test "navigation invalidates activation but not the completed persistence" {
  let account = test_account("account")
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Remote",
  )
  guard signed_in(account).begin_open(entry)
    is (state, None, Some(GetRemote(effect, _, _, Open(intent, expected)))) else {
    fail("open read")
  }
  let (state, attempt) = state.opened(
    effect,
    account,
    test_document_id(),
    intent,
    expected,
    None,
    @source_repository.RemoteDocument::Present(revision(2.0), "remote"),
  )
  let attempt = attempt.unwrap()
  let (state, _) = state
    .cancel_open()
    .stored(attempt.request_id(), attempt.write().checkpoint())
  assert_eq(state.pending_open(), None)
}

///|
test "catalog facts are level-triggered after storage becomes idle" {
  let account = test_account("account")
  let durable = @source_repository.SyncCheckpoint::receive(
    account,
    test_document("base"),
    revision(1.0),
  )
  let entry = @source_repository.RemoteEntry::Present(
    test_document_id(),
    revision(2.0),
    "Remote",
  )
  let state = with_catalog(signed_in(account), account, [entry])
  let (state, saving) = state.save(durable, "local")
  let saving = saving.unwrap()
  assert_eq(state.drive(durable).1, None)
  let checkpoint = saving.write().checkpoint()
  let (state, _) = state.stored(saving.request_id(), checkpoint)
  assert_true(
    state.drive(checkpoint).1
    is Some(GetRemote(_, _, _, RemoteRead::Revision(_))),
  )
}

///|
test "eligible edit reconciles an available revision immediately" {
  let account = test_account("account")
  let durable = @source_repository.SyncCheckpoint::receive(
    account,
    test_document("base"),
    revision(1.0),
  )
  guard durable.reconcile(
      @source_repository.RemoteDocument::Present(revision(2.0), "remote"),
    )
    is @source_repository.ReconcilePlan::Persist(write) else {
    fail("available update")
  }
  let available = write.checkpoint()
  let (state, storing) = signed_in(account).save(available, "local")
  let storing = storing.unwrap()
  let diverged = storing.write().checkpoint()
  assert_eq(
    diverged.directive(),
    @source_repository.SyncDirective::RecoveryRequired,
  )
  let (state, _) = state.stored(storing.request_id(), diverged)
  guard state.drive(diverged) is (state, Some(CreateRecovery(effect, _, _))) else {
    fail("recovery effect")
  }
  let recovery_id = test_document_id(value="recovery")
  guard state.recover(diverged, effect, recovery_id).1.unwrap().write()
    is @source_repository.CheckpointAndRecovery(checkpoint, recovery) else {
    fail("atomic recovery")
  }
  assert_eq(recovery.text(), "local")
  assert_true(
    checkpoint.directive() is @source_repository.SyncDirective::Conflict(_, _),
  )
}

///|
test "recovery completion preserves the newest causal head" {
  let account = test_account("account")
  let base = @source_repository.SyncCheckpoint::receive(
    account,
    test_document("base"),
    revision(1.0),
  )
  let edited = edit_write(base, "local-a").checkpoint()
  guard edited.reconcile(
      @source_repository.RemoteDocument::Present(revision(2.0), "remote"),
    )
    is @source_repository.ReconcilePlan::Persist(divergence) else {
    fail("divergence")
  }
  let diverged = divergence.checkpoint()
  guard signed_in(account).drive(diverged)
    is (state, Some(CreateRecovery(effect, _, _))) else {
    fail("recovery")
  }
  let (state, newer) = state.save(diverged, "local-b")
  let newer = newer.unwrap()
  let recovery_id = test_document_id(value="recovery")
  let (state, recovery) = state.recover(diverged, effect, recovery_id)
  guard recovery is None else {
    fail("recovery must queue behind the newer write")
  }
  let (_, recovery) = state.stored(
    newer.request_id(),
    newer.write().checkpoint(),
  )
  guard recovery.unwrap().write()
    is @source_repository.CheckpointAndRecovery(checkpoint, document) else {
    fail("atomic recovery")
  }
  assert_eq(document.text(), "local-b")
  assert_eq(
    checkpoint.generation(),
    newer.write().checkpoint().generation() + 1.0,
  )
}

///|
test "recovery completion uses an edit that became durable while it waited" {
  let account = test_account("account")
  let base = @source_repository.SyncCheckpoint::receive(
    account,
    test_document("base"),
    revision(1.0),
  )
  let edited = edit_write(base, "local-a").checkpoint()
  guard edited.reconcile(
      @source_repository.RemoteDocument::Present(revision(2.0), "remote"),
    )
    is @source_repository.ReconcilePlan::Persist(divergence) else {
    fail("divergence")
  }
  let diverged = divergence.checkpoint()
  guard signed_in(account).drive(diverged)
    is (state, Some(CreateRecovery(effect, _, _))) else {
    fail("recovery")
  }
  let (state, newer) = state.save(diverged, "local-b")
  let newer = newer.unwrap()
  let durable = newer.write().checkpoint()
  let (state, next) = state.stored(newer.request_id(), durable)
  assert_eq(next, None)
  let (_, recovery) = state.recover(
    durable,
    effect,
    test_document_id(value="recovery"),
  )
  guard recovery.unwrap().write()
    is @source_repository.CheckpointAndRecovery(checkpoint, document) else {
    fail("atomic recovery")
  }
  assert_eq(document.text(), "local-b")
  assert_eq(checkpoint.generation(), durable.generation() + 1.0)
}

///|
test "an available update continues observing newer catalog revisions" {
  let account = test_account("account")
  let base = @source_repository.SyncCheckpoint::receive(
    account,
    test_document("base"),
    revision(1.0),
  )
  guard base.reconcile(
      @source_repository.RemoteDocument::Present(revision(2.0), "remote-two"),
    )
    is @source_repository.ReconcilePlan::Persist(write) else {
    fail("available update")
  }
  let available = write.checkpoint()
  let state = with_catalog(signed_in(account), account, [
    @source_repository.RemoteEntry::Present(
      test_document_id(),
      revision(3.0),
      "Remote three",
    ),
  ])
  assert_true(
    state.drive(available).1
    is Some(GetRemote(_, _, _, RemoteRead::Revision(expected))) &&
    expected == revision(3.0),
  )
}

///|
test "catalog keeps unseen entries and only accepts newer revisions" {
  let account = test_account("account")
  let first = test_document_id(value="a")
  let second = test_document_id(value="b")
  let state = with_catalog(signed_in(account), account, [
    @source_repository.RemoteEntry::Present(first, revision(2.0), "A"),
    @source_repository.RemoteEntry::Present(second, revision(1.0), "B"),
  ])
  let state = with_catalog(state, account, [
    @source_repository.RemoteEntry::Deleted(first, revision(1.0)),
  ])
  assert_true(
    state.remote_entry(first)
    is Some(@source_repository.RemoteEntry::Present(_, _, "A")),
  )
  assert_true(state.remote_entry(second) is Some(_))
  let state = with_catalog(state, account, [
    @source_repository.RemoteEntry::Deleted(first, revision(3.0)),
  ])
  assert_true(
    state.remote_entry(first)
    is Some(@source_repository.RemoteEntry::Deleted(_, _)),
  )
}
