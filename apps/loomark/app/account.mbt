///|
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
extern "js" fn listen_for_page_restore(callback : () -> Unit) -> () -> Unit =
  #| callback => {
  #|   const listener = event => { if (event.persisted) callback(); };
  #|   window.addEventListener("pageshow", listener);
  #|   return () => window.removeEventListener("pageshow", listener);
  #| }

///|
priv suberror PageRestoreSubscription {
  OnRestore(@cmd.Cmd)
}

///|
fn page_restore_subscription(command : @cmd.Cmd) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.page-restored",
    @sub.Scope::Local,
    PageRestoreSubscription::OnRestore(command),
    (payload, scheduler) => {
      guard payload is PageRestoreSubscription::OnRestore(command) else {
        return None
      }
      let mut command = command
      let stop = listen_for_page_restore(() => scheduler.queue_command(command))
      Some({
        unload: _ => stop(),
        update_tagger: next => {
          guard next is PageRestoreSubscription::OnRestore(next) else { return }
          command = next
        },
      })
    },
  )
}

///|
fn account_controls_input(model : Model) -> AccountControlsInput {
  {
    session: model.sync().session(),
    departure: model.departure,
    can_login: match model.page {
      Editing(editing) =>
        !(editing.creation is Creating(_)) &&
        editing.imports_pending == 0 &&
        editing.deletion == NoDeletion &&
        !editing.documents.is_composing(editing.activation.key)
      _ => false
    },
  }
}

///|
fn account_controls(
  input : AccountControlsInput,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  if input.session is SessionUnavailable {
    return @html.div(class="flex flex-col gap-2", [
      @html.p(
        class="m-0 text-xs leading-relaxed text-lm-muted",
        "Couldn’t check sign-in status.",
      ),
      @html.button(
        type_="button",
        class="min-h-8 self-start cursor-pointer rounded-md border border-lm-rule bg-transparent px-2 py-1 text-xs text-lm-ink hover:bg-lm-foundation focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-lm-accent max-[641px]:min-h-11",
        on_click=emit(RetryAccount),
        "Check account connection",
      ),
    ])
  }
  let (label, disabled, command) = match input.departure {
    SavingBeforeLogin(attempt)
    | PreparingLogin(attempt)
    | PreparedLogin(attempt, _) =>
      ("Cancel sign-in", false, emit(LoginCancelled(attempt)))
    Redirecting(_) => ("Signing in…", true, @cmd.none)
    Stable | LoginFailed(_) =>
      match input.session {
        NoAccount =>
          (
            if input.departure is LoginFailed(_) {
              "Retry sign-in"
            } else {
              "Login with Google"
            },
            !input.can_login,
            emit(LoginRequested),
          )
        Current(_, _) => ("Sign out", false, emit(LogoutRequested))
        Revoking(_) => ("Signing out…", true, @cmd.none)
        LogoutUnconfirmed(_) => ("Retry sign-out", false, emit(LogoutRequested))
        Resolving(_) => ("Checking account…", true, @cmd.none)
        SessionUnavailable => return @html.nothing
      }
  }
  let progress = match input.departure {
    SavingBeforeLogin(_) | PreparingLogin(_) | PreparedLogin(_, _) =>
      "Signing in…"
    _ => ""
  }
  let google_sign_in = input.session is NoAccount &&
    input.departure is (Stable | LoginFailed(_) | Redirecting(_))
  @html.div(class="flex min-w-0 flex-wrap items-center gap-1", [
    @html.span(
      hidden=progress == "",
      class="text-xs text-lm-muted",
      attrs=@html.Attrs::build().role("status"),
      @html.text(progress),
    ),
    match input.session {
      Current(_, name) =>
        @html.span(class="min-w-0 flex-1 break-words text-sm text-lm-ink", name)
      Revoking(attempt) | LogoutUnconfirmed(attempt) =>
        @html.span(
          class="min-w-0 flex-1 break-words text-sm text-lm-ink",
          attempt.name(),
        )
      Resolving(_) | NoAccount | SessionUnavailable => @html.nothing
    },
    @html.button(
      type_="button",
      class=if google_sign_in {
        "flex min-h-11 w-full min-w-0 cursor-pointer items-center justify-center gap-2.5 rounded-full border border-lm-rule bg-white px-4 py-2 text-sm font-medium text-lm-ink hover:bg-lm-foundation active:bg-lm-foundation focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lm-accent disabled:cursor-default disabled:opacity-60"
      } else {
        "min-h-8 shrink-0 cursor-pointer rounded-md border border-lm-rule bg-transparent px-2 py-1 text-xs text-lm-ink hover:bg-lm-foundation focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-lm-accent disabled:cursor-default disabled:opacity-60 max-[641px]:min-h-11"
      },
      disabled~,
      on_click=command,
      [
        if google_sign_in {
          @html.img(
            src="./google-g.svg",
            alt="",
            width=18,
            height=18,
            class="shrink-0",
          )
        } else {
          @html.nothing
        },
        @html.text(label),
      ],
    ),
  ])
}

///|
fn account_notice(input : AccountControlsInput) -> @rabbita.Html {
  let message = match input.departure {
    LoginFailed(SaveFailed(_)) =>
      "Couldn’t save changes. You have not left this page. Retry sign-in to save again."
    LoginFailed(AuthenticationFailed) =>
      "Couldn’t sign in with Google. Your documents remain on this device."
    _ =>
      match input.session {
        LogoutUnconfirmed(_) => "Couldn’t confirm sign-out. Retry sign-out."
        _ => return @html.nothing
      }
  }
  @html.p(
    class="m-0 shrink-0 bg-lm-danger-soft px-3 py-2 text-sm text-lm-danger",
    attrs=@html.Attrs::build().role("alert"),
    @html.text(message),
  )
}
