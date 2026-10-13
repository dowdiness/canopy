///|
fn sign_in_documents() -> @documents.Model {
  @documents.Model(
    @source_repository.SavedDocuments::from_documents([]).unwrap(),
  )
}

///|
test "late authorization result releases a request without advancing a newer save" {
  let ready = Readiness::SignedOut(
    editor=Editor::Ready,
    durability=sign_in_documents().local_durability(
      @replica_persistence.State(),
    ),
  )
  let initial = SignIn()
  guard initial.view(ready) is View::Available(start) else {
    fail("start action")
  }
  let saving = initial.update(Event::Invoke(start), ready)
  let requesting = saving.state.update(Event::Refresh, ready)
  let request = match requesting.effects {
    [Effect::RequestAuthorizationUrl(request)] => request
    _ => fail("authorization request")
  }
  let cancel = match requesting.state.view(ready) {
    View::InProgress(action) => action
    _ => fail("cancel action")
  }
  let canceled = requesting.state.update(Event::Invoke(cancel), ready)
  let interrupted = requesting.state.update(Event::Interrupted, ready)
  assert_true(interrupted.effects is [])
  assert_false(interrupted.state.blocks_editing())
  assert_true(canceled.effects is [Effect::FocusEditor])
  guard canceled.state.view(ready) is View::Available(restart) else {
    fail("restart action")
  }
  let new_saving = canceled.state.update(Event::Invoke(restart), ready)
  assert_true(new_saving.effects is [Effect::SaveChanges])
  let documents = match
    sign_in_documents().update(
      @documents.Msg::Imported(
        @source_repository.DocumentId::parse(
          "00000000-0000-4000-8000-000000000001",
        ),
        "pending text",
      ),
    ) {
    @documents.Update::Applied(transition) => transition.model
    Superseded => fail("import should be applied")
  }
  let released = new_saving.state.update(
    Event::AuthorizationReceived(request, None),
    Readiness::SignedOut(
      editor=Ready,
      durability=documents.local_durability(@replica_persistence.State()),
    ),
  )
  assert_true(released.outcome is Outcome::RequestReleased)
  assert_true(released.state.blocks_editing())
  let resumed = released.state.update(Event::Refresh, ready)
  assert_true(resumed.effects is [Effect::RequestAuthorizationUrl(_)])
}

///|
test "authorization returned during account checking waits and navigates once" {
  let ready = Readiness::SignedOut(
    editor=Editor::Ready,
    durability=sign_in_documents().local_durability(
      @replica_persistence.State(),
    ),
  )
  let initial = SignIn()
  guard initial.view(ready) is View::Available(start) else {
    fail("start action")
  }
  let saving = initial.update(Event::Invoke(start), ready)
  let requesting = saving.state.update(Event::Refresh, ready)
  let request = match requesting.effects {
    [Effect::RequestAuthorizationUrl(request)] => request
    _ => fail("authorization request")
  }
  guard requesting.state.view(ready) is View::InProgress(cancel) else {
    fail("cancel action")
  }
  let url = @account_http.GoogleAuthorizationUrl::parse(
    "https://accounts.google.com/o/oauth2/v2/auth?client_id=test",
  ).unwrap()
  let awaiting = requesting.state.update(
    Event::AuthorizationReceived(request, Some(url)),
    Readiness::CheckingAccount,
  )
  assert_true(awaiting.effects is [])
  let navigating = awaiting.state.update(Event::Refresh, ready)
  guard navigating.effects is [Effect::Navigate(destination)] else {
    fail("navigation")
  }
  assert_true(destination == url)
  let late_cancel = navigating.state.update(Event::Invoke(cancel), ready)
  assert_true(late_cancel.effects is [])
  assert_true(late_cancel.state.view(ready) is View::Leaving)
  assert_true(navigating.state.update(Event::Refresh, ready).effects is [])
  let restored = navigating.state.update(Event::PageRestored, ready)
  assert_true(restored.effects is [Effect::CheckAccount])
}
