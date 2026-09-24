///|
priv enum AccountState {
  CheckingAccount
  SignedOut
  SignedIn(String)
  SavingBeforeLogin
  StartingLogin
  RedirectingToGoogle
  LoginFailed(LoginFailure)
  AccountUnavailable
  SigningOut(String)
  LogoutFailed(String)
} derive(Eq)

///|
priv enum LoginFailure {
  SaveFailed
  AuthenticationFailed
} derive(Eq)

///|
fn AccountState::leaving(self : Self) -> Bool {
  match self {
    SavingBeforeLogin | StartingLogin | RedirectingToGoogle => true
    _ => false
  }
}

///|
fn EditingState::can_login(self : Self) -> Bool {
  !(self.creation is Creating(_)) &&
  self.imports_pending == 0 &&
  self.deletion == NoDeletion &&
  self.documents.known_keys().all(key => !self.documents.is_composing(key))
}

///|
// Consume only the callback marker; never display provider error text.
extern "js" fn consume_authentication_error() -> Bool =
  #| () => {
  #|   const url = new URL(window.location.href);
  #|   if (!url.searchParams.has("error")) return false;
  #|   url.searchParams.delete("error");
  #|   url.searchParams.delete("error_description");
  #|   window.history.replaceState(window.history.state, "", url.href);
  #|   return true;
  #| }

///|
extern "js" fn load_url(url : String) =
  #| url => window.location.assign(url)

///|
fn check_account(emit : @rabbita.Emit[Msg]) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    let failed = consume_authentication_error()
    // Better Auth returns null for anonymous sessions, unlike /api/account's 401.
    scheduler.add(
      @http.get("/api/auth/get-session").expect_json(
        emit.map(result => AccountLoaded(result, failed)),
      ),
    )
  })
}

///|
fn account_result(
  result : Result[Json, Error],
  callback_failed : Bool,
) -> AccountState {
  match result {
    Ok({ "user": { "id": String(id), "name": String(name), .. }, .. }) if !id.is_empty() =>
      SignedIn(name)
    Ok(Null) =>
      if callback_failed {
        LoginFailed(AuthenticationFailed)
      } else {
        SignedOut
      }
    _ => AccountUnavailable
  }
}

///|
fn google_authorization_url(result : Result[Json, Error]) -> String? {
  match result {
    Ok({ "url": String(url), .. }) if url.has_prefix(
        "https://accounts.google.com/",
      ) => Some(url)
    _ => None
  }
}

///|
fn begin_login(
  editing : EditingState,
  emit : @rabbita.Emit[Msg],
) -> (Page, @rabbita.Cmd) {
  guard editing.can_login() else { return (Editing(editing), @cmd.none) }
  let (documents, actions) = editing.documents
    .known_keys()
    .fold(init=(editing.documents, ([] : Array[@documents.Action])), (
      state,
      key,
    ) => {
      let event = match state.0.save_status(key) {
        Some(SaveFailed(_)) => @documents.Msg::RetrySave(key)
        _ => @documents.Msg::VisibilityFlush(key)
      }
      let (documents, next) = state.0.reduce(event)
      (documents, state.1 + next)
    })
  (
    Editing({ ..editing, documents, account: SavingBeforeLogin, }),
    run_actions(documents, actions, emit),
  )
}

///|
fn advance_login(
  model : Page,
  emit : @rabbita.Emit[Msg],
  command : @rabbita.Cmd,
) -> (Page, @rabbita.Cmd) {
  guard model is Editing(editing) && editing.account == SavingBeforeLogin else {
    return (model, command)
  }
  let statuses = editing.documents
    .known_keys()
    .map(key => editing.documents.save_status(key))
  if statuses.any(status => status is Some(SaveFailed(_))) {
    (Editing({ ..editing, account: LoginFailed(SaveFailed), }), command)
  } else if statuses.all(status => status is Some(Clean)) {
    (
      Editing({ ..editing, account: StartingLogin, }),
      @cmd.batch([
        command,
        @http.post("/api/auth/sign-in/social")
        .with_json(
          (
            {
              "provider": "google",
              "callbackURL": "/",
              "errorCallbackURL": "/",
              "disableRedirect": true,
            } : Json),
        )
        .expect_json(emit.map(result => LoginPrepared(result))),
      ]),
    )
  } else {
    (model, command)
  }
}

///|
fn login_blocks_message(msg : Msg) -> Bool {
  match msg {
    ExampleSelected(_, _)
    | TextChanged(_, _)
    | CompositionStarted(_)
    | ImportFilesSelected(_)
    | DocumentSelected(_)
    | CreateRequested
    | DeleteRequested(_)
    | DeleteConfirmed(_)
    | RetryDelete(_) => true
    _ => false
  }
}

///|
fn account_controls(
  editing : EditingState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let (label, disabled, action) = match editing.account {
    CheckingAccount => ("Checking account…", true, @cmd.none)
    SignedOut =>
      ("Sign in with Google", !editing.can_login(), emit(LoginRequested))
    SignedIn(_) | LogoutFailed(_) => ("Sign out", false, emit(LogoutRequested))
    SavingBeforeLogin => ("Saving before sign-in…", true, @cmd.none)
    StartingLogin | RedirectingToGoogle =>
      ("Opening Google…", true, @cmd.none)
    LoginFailed(_) =>
      ("Retry sign-in", !editing.can_login(), emit(LoginRequested))
    AccountUnavailable => ("Retry account", false, emit(CheckAccount))
    SigningOut(_) => ("Signing out…", true, @cmd.none)
  }
  @html.div(class="flex min-w-0 flex-wrap items-center gap-2", [
    match editing.account {
      SignedIn(name) | SigningOut(name) | LogoutFailed(name) =>
        @html.span(
          class="max-w-32 truncate text-xs text-lm-ink",
          title=name,
          @html.text(name),
        )
      _ => @html.nothing
    },
    @html.button(
      type_="button",
      class="min-h-8 shrink-0 cursor-pointer rounded-md border border-lm-rule bg-transparent px-2 py-1 text-xs text-lm-ink hover:bg-lm-foundation focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-lm-accent disabled:cursor-default disabled:opacity-60 max-[641px]:min-h-11",
      disabled~,
      on_click=action,
      @html.text(label),
    ),
  ])
}

///|
fn account_notice(account : AccountState) -> @rabbita.Html {
  let message = match account {
    LoginFailed(SaveFailed) =>
      "Changes could not be saved. Retry sign-in to save again. You have not left this page."
    LoginFailed(AuthenticationFailed) =>
      "Google sign-in did not complete. Try again. Your documents remain in this browser."
    AccountUnavailable =>
      "Account service unavailable. Retry to check your account. You can keep editing locally."
    LogoutFailed(_) => "Sign-out could not be confirmed. Try signing out again."
    _ => return @html.nothing
  }
  @html.p(
    class="m-0 shrink-0 bg-lm-danger-soft px-3 py-2 text-sm text-lm-danger",
    attrs=@html.Attrs::build().role("alert"),
    @html.text(message),
  )
}
