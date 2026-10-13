///|
fn signed_out_model(editing : EditingDocument) -> Model {
  let (sync, lookup) = @sync.State().begin_lookup() catch {
    _ => abort("fresh session lookup")
  }
  test_model(Editing(editing), sync.resolved(lookup, @sync.SignedOut).0)
}

///|
fn start_sign_in(model : Model) -> (Model, @cmd.Cmd) {
  let action = match account_controls_input(model).sign_in {
    @sign_in.Available(action) | Failed(_, retry=Some(action)) => action
    _ => abort("sign-in is not offered")
  }
  test_root_update(model, SignIn(@sign_in.Invoke(action)))
}

///|
fn cancel_sign_in_action(model : Model) -> @sign_in.Action {
  guard account_controls_input(model).sign_in is @sign_in.InProgress(action) else {
    abort("sign-in is not in progress")
  }
  action
}

///|
fn sign_in_request(model : Model) -> @sign_in.Request {
  guard model.sign_in is @sign_in.Connecting(request~, ..) else {
    abort("authorization URL was not requested")
  }
  request
}

///|
fn redirecting_model() -> Model {
  let (model, _) = start_sign_in(signed_out_model(test_editing()))
  let url = @account_http.GoogleAuthorizationUrl::parse(
    "https://accounts.google.com/o/oauth2/auth?state=test",
  ).unwrap()
  test_root_update(
    model,
    SignIn(@sign_in.AuthorizationReceived(sign_in_request(model), Some(url))),
  ).0
}

///|
test "sign-in advances on the final local save completion" {
  let initial = test_editing()
  let key = initial.activation.key
  let __document_transition_0 = expect_document_edit(initial.documents, key, "latest")
let documents = __document_transition_0.model
  let __document_transition_1 = expect_document_update(documents, @documents.Msg::ApplyPendingEdit(key, 1))
  let documents = __document_transition_1.model
let actions = __document_transition_1.effects.to_array()
  guard actions[0] is @documents.Action::PersistSource(operation) else {
    fail("source save")
  }
  let (waiting, _) = start_sign_in(signed_out_model({ ..initial, documents, }))
  assert_true(waiting.sign_in is @sign_in.SavingChanges(..))
  let (ready, _) = test_root_update(
    waiting,
    DocumentSaved(operation, operation.document),
  )
  assert_true(ready.sign_in is @sign_in.Connecting(..))
  assert_eq(
    ready.page
    .saved_documents()
    .unwrap()
    .find(operation.document.id())
    .unwrap()
    .text(),
    "latest",
  )
}

///|
test "local save failure releases editing and sign-in retries the failed save" {
  let initial = test_editing()
  let key = initial.activation.key
  let __document_transition_2 = expect_document_edit(initial.documents, key, "latest")
let documents = __document_transition_2.model
  let __document_transition_3 = expect_document_update(documents, @documents.Msg::ApplyPendingEdit(key, 1))
  let documents = __document_transition_3.model
let actions = __document_transition_3.effects.to_array()
  guard actions[0] is @documents.Action::PersistSource(operation) else {
    fail("source save")
  }
  let (waiting, _) = start_sign_in(signed_out_model({ ..initial, documents, }))
  let (failed, _) = test_root_update(
    waiting,
    DocumentSaveFailed(operation, WriteFailed),
  )
  assert_true(
    account_controls_input(failed).sign_in
    is @sign_in.Failed(@sign_in.Save(_), ..),
  )
  assert_false(failed.sign_in.blocks_editing())
  let (retrying, _) = start_sign_in(failed)
  assert_true(retrying.sign_in is @sign_in.SavingChanges(..))
  guard retrying.page is Editing(editing) else {
    fail("editing remains available")
  }
  assert_true(
    editing.documents.save_status(key) is Some(@documents.SaveStatus::Unsaved),
  )
}

///|
test "logout fences lookup and hides account membership without discarding open text" {
  let account = sync_test_account("account")
  let initial = test_editing()
  let key = @documents.Key::replica(account, document_id("one"))
  let saved = test_sync_snapshot(account)
  let editing = {
    ..initial,
    documents: @documents.Model(saved).project_account(account),
    activation: { key, generation: 0, },
  }
  let (old_lookup, lookup) = current_sync(account).begin_lookup()
  let sync = old_lookup.resolved(lookup, @sync.Resolved(account, "Writer")).0
  let (revoking, _) = test_root_update(
    test_model(Editing(editing), sync),
    LogoutRequested,
  )
  guard revoking.sync().session() is @sync.Session::Revoking(attempt) else {
    fail("revoking session")
  }
  let (focused, _) = test_root_update(revoking, VisibilityChanged(false))
  assert_true(focused.sync().session() is @sync.Session::Revoking(_))
  let (logged_out, _) = test_root_update(
    focused,
    LogoutCompleted(attempt, @account_http.SignedOut),
  )
  let (late, _) = test_root_update(
    logged_out,
    Sync(AccountResolved(lookup, @sync.Resolved(account, "Writer"))),
  )
  assert_true(late.sync().session() is @sync.Session::NoAccount)
  guard late.page is Editing(editing) else { fail("open editor retained") }
  assert_eq(editing.documents.text(key), Some("one"))
  assert_false(editing.documents.recent().any(row => row.0 == key))
}

///|
test "signed-out replica edits enter persistence synchronously during sign-in" {
  let account = sync_test_account("account")
  let key = @documents.Key::replica(account, document_id("one"))
  let editing = {
    ..test_editing(),
    documents: @documents.Model(test_sync_snapshot(account)),
    activation: { key, generation: 0, },
  }
  let (edited, _) = test_root_update(
    signed_out_model(editing),
    TextChanged(0, @text_change.TextChange::ReplaceAll("offline change")),
  )
  let (waiting, _) = start_sign_in(edited)
  assert_true(waiting.sign_in is @sign_in.SavingChanges(..))
  assert_eq(
    waiting.replication
    .pending(account, document_id("one"))
    .unwrap()
    .document()
    .unwrap()
    .text(),
    "offline change",
  )
}

///|
test "racing text cancels sign-in and fences provider completion" {
  let (connecting, _) = start_sign_in(signed_out_model(test_editing()))
  let request = sign_in_request(connecting)
  let (edited, _) = test_root_update(
    connecting,
    TextChanged(0, @text_change.TextChange::ReplaceAll("racing text")),
  )
  let (late, _) = test_root_update(
    edited,
    SignIn(@sign_in.AuthorizationReceived(request, None)),
  )
  assert_true(account_controls_input(late).sign_in is @sign_in.Available(_))
  guard late.page is Editing(editing) else { fail("editing") }
  assert_eq(editing.documents.text(editing.activation.key), Some("racing text"))
}

///|
test "uncertain logout can retry without duplicate root session state" {
  let account = sync_test_account("account")
  let (revoking, _) = test_root_update(
    test_model(Editing(test_editing()), current_sync(account)),
    LogoutRequested,
  )
  guard revoking.sync().session() is @sync.Session::Revoking(first) else {
    fail("logout started")
  }
  let (uncertain, _) = test_root_update(
    revoking,
    LogoutCompleted(first, @account_http.Unconfirmed),
  )
  assert_true(uncertain.sync().session() is @sync.Session::LogoutUnconfirmed(_))
  let (retrying, _) = test_root_update(uncertain, LogoutRequested)
  guard retrying.sync().session() is @sync.Session::Revoking(second) else {
    fail("logout retried")
  }
  assert_true(first != second)
  let (stale, _) = test_root_update(
    retrying,
    LogoutCompleted(first, @account_http.SignedOut),
  )
  assert_true(stale.sync().session() == retrying.sync().session())
  let (done, _) = test_root_update(
    stale,
    LogoutCompleted(second, @account_http.SignedOut),
  )
  assert_true(done.sync().session() is @sync.Session::NoAccount)
}

///|
test "a joined sign-in consumes the physical result and stale results cannot release its retry" {
  let (first, _) = start_sign_in(signed_out_model(test_editing()))
  let physical = sign_in_request(first)
  let first_cancel = cancel_sign_in_action(first)
  let (canceled, _) = test_root_update(
    first,
    TextChanged(0, @text_change.TextChange::ReplaceAll("one")),
  )
  let (joined, _) = start_sign_in(canceled)
  assert_true(cancel_sign_in_action(joined) != first_cancel)
  assert_true(sign_in_request(joined) == physical)
  let (failed, _) = test_root_update(
    joined,
    SignIn(@sign_in.AuthorizationReceived(physical, None)),
  )
  assert_true(
    account_controls_input(failed).sign_in
    is @sign_in.Failed(Authentication, ..),
  )
  assert_false(failed.sign_in.blocks_editing())
  let (retrying, _) = start_sign_in(failed)
  let next = sign_in_request(retrying)
  assert_true(next != physical)
  let (stale, _) = test_root_update(
    retrying,
    SignIn(@sign_in.AuthorizationReceived(physical, None)),
  )
  assert_true(sign_in_request(stale) == next)
  let (completed, _) = test_root_update(
    stale,
    SignIn(@sign_in.AuthorizationReceived(next, None)),
  )
  assert_true(
    account_controls_input(completed).sign_in
    is @sign_in.Failed(Authentication, ..),
  )
}

///|
test "account resolution cancels sign-in without releasing its physical request" {
  let (connecting, _) = start_sign_in(signed_out_model(test_editing()))
  let physical = sign_in_request(connecting)
  let (sync, lookup) = connecting.sync().begin_lookup()
  let (signed_in, _) = test_root_update(
    connecting.with_sync(sync),
    Sync(
      AccountResolved(
        lookup,
        @sync.Resolved(sync_test_account("other"), "Other"),
      ),
    ),
  )
  assert_false(signed_in.sign_in.blocks_editing())
  let (sync, lookup) = signed_in.sync().begin_lookup()
  let (signed_out, _) = test_root_update(
    signed_in.with_sync(sync),
    Sync(AccountResolved(lookup, @sync.SignedOut)),
  )
  let (joined, _) = start_sign_in(signed_out)
  let (completed, _) = test_root_update(
    joined,
    SignIn(@sign_in.AuthorizationReceived(physical, None)),
  )
  assert_true(
    account_controls_input(completed).sign_in
    is @sign_in.Failed(Authentication, ..),
  )
}

///|
test "physical completion during a newer save cannot bypass local persistence" {
  let initial = test_editing()
  let (connecting, _) = start_sign_in(signed_out_model(initial))
  let physical = sign_in_request(connecting)
  let (edited, _) = test_root_update(
    connecting,
    TextChanged(0, @text_change.TextChange::ReplaceAll("new text")),
  )
  let (_, actions) = edited.page.documents_state().unwrap().save_changes() catch {
    @documents.DeleteError::DocumentMissing(_) => fail("document missing during test save")
    @documents.DeleteError::OwnershipTransferInProgress(_) => fail("document transfer during test save")
    @documents.DeleteError::ReplicaMissing(_) => fail("replica missing during test save")
  }
  guard actions is [@documents.Action::PersistSource(operation)] else {
    fail("latest source persistence")
  }
  let (saving, _) = start_sign_in(edited)
  assert_true(saving.sign_in is @sign_in.SavingChanges(..))
  let (waiting, _) = test_root_update(
    saving,
    SignIn(@sign_in.AuthorizationReceived(physical, None)),
  )
  assert_true(waiting.sign_in is @sign_in.SavingChanges(..))
  let (ready, _) = test_root_update(
    waiting,
    DocumentSaved(operation, operation.document),
  )
  let next = sign_in_request(ready)
  assert_true(next != physical)
  let (failed, _) = test_root_update(
    ready,
    SignIn(@sign_in.AuthorizationReceived(next, None)),
  )
  assert_true(
    account_controls_input(failed).sign_in
    is @sign_in.Failed(Authentication, ..),
  )
}

///|
test "a visibility account lookup suspends rather than cancels sign-in" {
  let (connecting, _) = start_sign_in(signed_out_model(test_editing()))
  let physical = sign_in_request(connecting)
  let (resolving, _) = test_root_update(connecting, VisibilityChanged(false))
  guard resolving.sync().session() is @sync.Session::Resolving(lookup) else {
    fail("account lookup")
  }
  assert_true(sign_in_request(resolving) == physical)
  let (signed_out, _) = test_root_update(
    resolving,
    Sync(AccountResolved(lookup, @sync.SignedOut)),
  )
  let (failed, _) = test_root_update(
    signed_out,
    SignIn(@sign_in.AuthorizationReceived(physical, None)),
  )
  assert_true(
    account_controls_input(failed).sign_in
    is @sign_in.Failed(Authentication, ..),
  )
}

///|
test "explicit cancellation retains the physical request and fences stale cancellations" {
  let (connecting, _) = start_sign_in(signed_out_model(test_editing()))
  let physical = sign_in_request(connecting)
  let cancel = cancel_sign_in_action(connecting)
  let (canceled, _) = test_root_update(
    connecting,
    SignIn(@sign_in.Invoke(cancel)),
  )
  assert_false(canceled.sign_in.blocks_editing())
  let (joined, _) = start_sign_in(canceled)
  let current_cancel = cancel_sign_in_action(joined)
  assert_true(current_cancel != cancel)
  let (still_joined, _) = test_root_update(
    joined,
    SignIn(@sign_in.Invoke(cancel)),
  )
  assert_true(cancel_sign_in_action(still_joined) == current_cancel)
  let (completed, _) = test_root_update(
    still_joined,
    SignIn(@sign_in.AuthorizationReceived(physical, None)),
  )
  assert_true(
    account_controls_input(completed).sign_in
    is @sign_in.Failed(Authentication, ..),
  )
}

///|
test "canceling sign-in leaves its save alive and preserves subsequent editing" {
  let initial = test_editing()
  let key = initial.activation.key
  let __document_transition_4 = expect_document_edit(initial.documents, key, "saving")
let documents = __document_transition_4.model
  let __document_transition_5 = expect_document_update(documents, @documents.Msg::ApplyPendingEdit(key, 1))
  let documents = __document_transition_5.model
let actions = __document_transition_5.effects.to_array()
  guard actions[0] is @documents.Action::PersistSource(operation) else {
    fail("source save")
  }
  let (waiting, _) = start_sign_in(signed_out_model({ ..initial, documents, }))
  let cancel = cancel_sign_in_action(waiting)
  let (canceled, _) = test_root_update(waiting, SignIn(@sign_in.Invoke(cancel)))
  assert_false(canceled.sign_in.blocks_editing())
  let (edited, _) = test_root_update(
    canceled,
    TextChanged(0, @text_change.TextChange::ReplaceAll("newer text")),
  )
  let (completed, _) = test_root_update(
    edited,
    DocumentSaved(operation, operation.document),
  )
  assert_true(
    account_controls_input(completed).sign_in is @sign_in.Available(_),
  )
  assert_eq(
    completed.page.documents_state().unwrap().text(key),
    Some("newer text"),
  )
  assert_eq(
    completed.page
    .saved_documents()
    .unwrap()
    .find(operation.document.id())
    .unwrap()
    .text(),
    "saving",
  )
}

///|
test "queued input cannot cancel an already dispatched redirect" {
  let redirecting = redirecting_model()
  let (after_input, _) = test_root_update(
    redirecting,
    TextChanged(0, @text_change.TextChange::ReplaceAll("queued text")),
  )
  assert_true(account_controls_input(after_input).sign_in is @sign_in.Leaving)
  assert_true(after_input.sign_in.blocks_editing())
  assert_eq(
    after_input.page
    .documents_state()
    .unwrap()
    .text(test_editing().activation.key),
    Some("queued text"),
  )
  let (sync, lookup) = after_input.sync().begin_lookup()
  let (after_lookup, _) = test_root_update(
    after_input.with_sync(sync),
    Sync(AccountResolved(lookup, @sync.AccountUnavailable)),
  )
  assert_true(after_lookup.sign_in.blocks_editing())
}

///|
test "BFCache restoration releases redirecting and fences the old account lookup" {
  let initial = redirecting_model()
  let (sync, old_lookup) = initial.sync().begin_lookup()
  let redirecting = initial.with_sync(sync)
  let (restored, _) = test_root_update(redirecting, PageRestored)
  assert_false(restored.sign_in.blocks_editing())
  guard restored.sync().session() is Resolving(lookup) else {
    fail("restoration checks the current account")
  }
  let (stale, _) = test_root_update(
    restored,
    Sync(AccountResolved(old_lookup, @sync.AccountUnavailable)),
  )
  assert_true(stale.sync().session() is Resolving(_))
  let (confirmed, _) = test_root_update(
    stale,
    Sync(AccountResolved(lookup, @sync.SignedOut)),
  )
  assert_true(confirmed.sync().session() is NoAccount)
  let (edited, _) = test_root_update(
    confirmed,
    TextChanged(0, @text_change.TextChange::ReplaceAll("after Back")),
  )
  assert_eq(
    edited.page.documents_state().unwrap().text(test_editing().activation.key),
    Some("after Back"),
  )
}

///|
test "page restoration does not cancel sign-in before navigation" {
  let initial = signed_out_model(test_editing())
  let (connecting, _) = start_sign_in(initial)
  let physical = sign_in_request(connecting)
  let (restored, _) = test_root_update(connecting, PageRestored)
  assert_true(sign_in_request(restored) == physical)
  assert_true(
    cancel_sign_in_action(restored) == cancel_sign_in_action(connecting),
  )
}

///|
test "an offered sign-in waits for composition accepted before the click is processed" {
  let initial = signed_out_model(test_editing())
  guard account_controls_input(initial).sign_in is @sign_in.Available(start) else {
    fail("sign-in offered")
  }
  let (composing, _) = test_root_update(initial, CompositionStarted(0))
  assert_true(account_controls_input(composing).sign_in is @sign_in.Unavailable)
  let (waiting, _) = test_root_update(composing, SignIn(@sign_in.Invoke(start)))
  assert_true(waiting.sign_in is @sign_in.SavingChanges(..))
  let (ready, _) = test_root_update(waiting, CompositionEnded(0))
  assert_true(ready.sign_in is @sign_in.Connecting(..))
}

///|
test "an offered sign-in cannot restart authentication after the account changes" {
  let initial = signed_out_model(test_editing())
  guard account_controls_input(initial).sign_in is @sign_in.Available(start) else {
    fail("sign-in offered")
  }
  let signed_in = initial.with_sync(
    current_sync(sync_test_account("signed-in")),
  )
  let (unchanged, _) = test_root_update(
    signed_in,
    SignIn(@sign_in.Invoke(start)),
  )
  assert_false(unchanged.sign_in.blocks_editing())
  assert_true(unchanged.sync().session() is @sync.Current(_, _))
}

///|
test "authentication return retains a pending request and its failure notice during account lookup failure" {
  let (connecting, _) = start_sign_in(signed_out_model(test_editing()))
  let request = sign_in_request(connecting)
  let (failed, _) = test_root_update(connecting, AuthenticationReturned(true))
  assert_true(
    account_controls_input(failed).sign_in
    is @sign_in.Failed(Authentication, ..),
  )
  let (retrying, _) = start_sign_in(failed)
  assert_true(sign_in_request(retrying) == request)
  let (failed, _) = test_root_update(
    retrying,
    SignIn(@sign_in.AuthorizationReceived(request, None)),
  )
  let (sync, lookup) = failed.sync().begin_lookup()
  let (unavailable, _) = test_root_update(
    failed.with_sync(sync),
    Sync(AccountResolved(lookup, @sync.AccountUnavailable)),
  )
  assert_true(
    account_controls_input(unavailable).sign_in
    is @sign_in.Failed(Authentication, retry=None),
  )
}
