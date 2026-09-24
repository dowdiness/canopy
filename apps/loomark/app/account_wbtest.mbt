///|
fn signed_out_model(editing : EditingState) -> Model {
  let (sync, lookup) = @sync.State().begin_lookup() catch {
    _ => abort("fresh session lookup")
  }
  test_model(Editing(editing), sync.resolved(lookup, @sync.SignedOut).0)
}

///|
test "sign-in advances on the final local save completion" {
  let initial = test_editing()
  let key = initial.activation.key
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::TextChanged(key, "latest"),
  )
  let (documents, actions) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(key, 1),
  )
  guard actions[0] is @documents.Action::PersistSource(operation) else {
    fail("source save")
  }
  let (waiting, _) = test_root_update(
    signed_out_model({ ..initial, documents, }),
    LoginRequested,
  )
  assert_true(waiting.departure is SavingBeforeLogin(_))
  let (ready, _) = test_root_update(
    waiting,
    DocumentsLifecycle(
      @documents.Feedback::SaveCompleted(operation, Stored(operation.document)),
    ),
  )
  assert_true(ready.departure is PreparingLogin(_))
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
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::TextChanged(key, "latest"),
  )
  let (documents, actions) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(key, 1),
  )
  guard actions[0] is @documents.Action::PersistSource(operation) else {
    fail("source save")
  }
  let (waiting, _) = test_root_update(
    signed_out_model({ ..initial, documents, }),
    LoginRequested,
  )
  let (failed, _) = test_root_update(
    waiting,
    DocumentsLifecycle(
      @documents.Feedback::SaveCompleted(operation, SaveFailed(WriteFailed)),
    ),
  )
  assert_true(failed.departure is LoginFailed(SaveFailed(_)))
  assert_false(failed.departure.editor_disabled())
  let (retrying, _) = test_root_update(failed, LoginRequested)
  assert_true(retrying.departure is SavingBeforeLogin(_))
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
    documents: @documents.State::State(saved).project_account(account),
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
    documents: @documents.State::State(test_sync_snapshot(account)),
    activation: { key, generation: 0, },
  }
  let (edited, _) = test_root_update(
    signed_out_model(editing),
    TextChanged(0, @text_change.TextChange::ReplaceAll("offline change")),
  )
  let (waiting, _) = test_root_update(edited, LoginRequested)
  assert_true(waiting.departure is SavingBeforeLogin(_))
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
test "racing text cancels departure and fences provider completion" {
  let (preparing, _) = test_root_update(
    signed_out_model(test_editing()),
    LoginRequested,
  )
  guard preparing.departure is PreparingLogin(attempt) else {
    fail("local copy already durable")
  }
  let (edited, _) = test_root_update(
    preparing,
    TextChanged(0, @text_change.TextChange::ReplaceAll("racing text")),
  )
  let (late, _) = test_root_update(
    edited,
    LoginPrepared(attempt, @account_http.Unavailable),
  )
  assert_true(late.departure is Stable)
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
  let (first, _) = test_root_update(
    signed_out_model(test_editing()),
    LoginRequested,
  )
  guard first.departure is PreparingLogin(physical) else {
    fail("first request")
  }
  let (canceled, _) = test_root_update(
    first,
    TextChanged(0, @text_change.TextChange::ReplaceAll("one")),
  )
  let (joined, _) = test_root_update(canceled, LoginRequested)
  guard joined.departure is PreparingLogin(current) else {
    fail("joined request")
  }
  assert_true(current != physical)
  let (failed, _) = test_root_update(
    joined,
    LoginPrepared(physical, @account_http.Unavailable),
  )
  assert_true(failed.departure is LoginFailed(AuthenticationFailed))
  assert_false(failed.departure.editor_disabled())
  let (retrying, _) = test_root_update(failed, LoginRequested)
  guard retrying.departure is PreparingLogin(next) else {
    fail("explicit retry")
  }
  assert_true(next != physical)
  let (stale, _) = test_root_update(
    retrying,
    LoginPrepared(physical, @account_http.Unavailable),
  )
  assert_true(stale.departure is PreparingLogin(_))
  let (completed, _) = test_root_update(
    stale,
    LoginPrepared(next, @account_http.Unavailable),
  )
  assert_true(completed.departure is LoginFailed(AuthenticationFailed))
}

///|
test "account resolution cancels departure without releasing its physical request" {
  let (preparing, _) = test_root_update(
    signed_out_model(test_editing()),
    LoginRequested,
  )
  guard preparing.departure is PreparingLogin(physical) else { fail("request") }
  let (sync, lookup) = preparing.sync().begin_lookup()
  let (signed_in, _) = test_root_update(
    preparing.with_sync(sync),
    Sync(
      AccountResolved(
        lookup,
        @sync.Resolved(sync_test_account("other"), "Other"),
      ),
    ),
  )
  assert_false(signed_in.departure.editor_disabled())
  let (sync, lookup) = signed_in.sync().begin_lookup()
  let (signed_out, _) = test_root_update(
    signed_in.with_sync(sync),
    Sync(AccountResolved(lookup, @sync.SignedOut)),
  )
  let (joined, _) = test_root_update(signed_out, LoginRequested)
  let (completed, _) = test_root_update(
    joined,
    LoginPrepared(physical, @account_http.Unavailable),
  )
  assert_true(completed.departure is LoginFailed(AuthenticationFailed))
}

///|
test "physical completion during a newer save cannot bypass local persistence" {
  let initial = test_editing()
  let (preparing, _) = test_root_update(
    signed_out_model(initial),
    LoginRequested,
  )
  guard preparing.departure is PreparingLogin(physical) else { fail("request") }
  let (edited, _) = test_root_update(
    preparing,
    TextChanged(0, @text_change.TextChange::ReplaceAll("new text")),
  )
  let (_, actions) = edited.page.documents_state().unwrap().prepare_departure()
  guard actions is [@documents.Action::PersistSource(operation)] else {
    fail("latest source persistence")
  }
  let (saving, _) = test_root_update(edited, LoginRequested)
  assert_true(saving.departure is SavingBeforeLogin(_))
  let (waiting, _) = test_root_update(
    saving,
    LoginPrepared(physical, @account_http.Unavailable),
  )
  assert_true(waiting.departure is SavingBeforeLogin(_))
  let (ready, _) = test_root_update(
    waiting,
    DocumentsLifecycle(
      @documents.Feedback::SaveCompleted(operation, Stored(operation.document)),
    ),
  )
  guard ready.departure is PreparingLogin(next) else {
    fail("fresh request after save")
  }
  assert_true(next != physical)
  let (failed, _) = test_root_update(
    ready,
    LoginPrepared(next, @account_http.Unavailable),
  )
  assert_true(failed.departure is LoginFailed(AuthenticationFailed))
}

///|
test "a visibility account lookup suspends rather than cancels sign-in" {
  let (preparing, _) = test_root_update(
    signed_out_model(test_editing()),
    LoginRequested,
  )
  guard preparing.departure is PreparingLogin(physical) else { fail("request") }
  let (resolving, _) = test_root_update(preparing, VisibilityChanged(false))
  guard resolving.sync().session() is @sync.Session::Resolving(lookup) else {
    fail("account lookup")
  }
  assert_true(resolving.departure is PreparingLogin(_))
  let (signed_out, _) = test_root_update(
    resolving,
    Sync(AccountResolved(lookup, @sync.SignedOut)),
  )
  let (failed, _) = test_root_update(
    signed_out,
    LoginPrepared(physical, @account_http.Unavailable),
  )
  assert_true(failed.departure is LoginFailed(AuthenticationFailed))
}

///|
test "explicit cancellation retains the physical request and fences stale cancellations" {
  let (preparing, _) = test_root_update(
    signed_out_model(test_editing()),
    LoginRequested,
  )
  guard preparing.departure is PreparingLogin(physical) else { fail("request") }
  let (canceled, _) = test_root_update(preparing, LoginCancelled(physical))
  assert_false(canceled.departure.editor_disabled())
  let (joined, _) = test_root_update(canceled, LoginRequested)
  guard joined.departure is PreparingLogin(current) else { fail("joined") }
  assert_true(current != physical)
  let (still_joined, _) = test_root_update(joined, LoginCancelled(physical))
  assert_true(still_joined.departure == PreparingLogin(current))
  let (completed, _) = test_root_update(
    still_joined,
    LoginPrepared(physical, @account_http.Unavailable),
  )
  assert_true(completed.departure is LoginFailed(AuthenticationFailed))
  assert_true(
    Departure::Redirecting(current).cancel(current) == Redirecting(current),
  )
}

///|
test "canceling departure leaves its save alive and preserves subsequent editing" {
  let initial = test_editing()
  let key = initial.activation.key
  let (documents, _) = initial.documents.reduce(
    @documents.Msg::TextChanged(key, "saving"),
  )
  let (documents, actions) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(key, 1),
  )
  guard actions[0] is @documents.Action::PersistSource(operation) else {
    fail("source save")
  }
  let (waiting, _) = test_root_update(
    signed_out_model({ ..initial, documents, }),
    LoginRequested,
  )
  guard waiting.departure is SavingBeforeLogin(attempt) else { fail("saving") }
  let (canceled, _) = test_root_update(waiting, LoginCancelled(attempt))
  assert_false(canceled.departure.editor_disabled())
  let (edited, _) = test_root_update(
    canceled,
    TextChanged(0, @text_change.TextChange::ReplaceAll("newer text")),
  )
  let (completed, _) = test_root_update(
    edited,
    DocumentsLifecycle(
      @documents.Feedback::SaveCompleted(operation, Stored(operation.document)),
    ),
  )
  assert_true(completed.departure is Stable)
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
  let initial = signed_out_model(test_editing())
  let redirecting = { ..initial, departure: Redirecting(LoginAttempt(1)), }
  let (after_input, _) = test_root_update(
    redirecting,
    TextChanged(0, @text_change.TextChange::ReplaceAll("queued text")),
  )
  assert_true(after_input.departure is Redirecting(_))
  assert_true(after_input.departure.editor_disabled())
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
  assert_true(after_lookup.departure is Redirecting(_))
}
