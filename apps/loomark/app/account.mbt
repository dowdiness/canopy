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
extern "js" fn restore_focus_after_login_cancel() =
  #| () => {
  #|   const root = document.querySelector('[aria-label="Loomark Markdown Editor"]');
  #|   const editor = root?.querySelector('textarea');
  #|   if (!editor || editor.disabled) return;
  #|   const target = editor.getClientRects().length
  #|     ? editor
  #|     : root.querySelector('[role="tab"][aria-selected="true"]');
  #|   target?.focus({ preventScroll: true });
  #| }

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
  let (label, disabled, command) = match input.departure {
    SavingBeforeLogin(attempt)
    | PreparingLogin(attempt)
    | PreparedLogin(attempt, _) =>
      ("Cancel sign-in", false, emit(LoginCancelled(attempt)))
    Redirecting(_) => ("Opening Google…", true, @cmd.none)
    Stable | LoginFailed(_) =>
      match input.session {
        NoAccount =>
          (
            if input.departure is LoginFailed(_) {
              "Retry sign-in"
            } else {
              "Sign in with Google"
            },
            !input.can_login,
            emit(LoginRequested),
          )
        Current(_, _) => ("Sign out", false, emit(LogoutRequested))
        Revoking(_) => ("Signing out…", true, @cmd.none)
        LogoutUnconfirmed(_) => ("Retry sign-out", false, emit(LogoutRequested))
        Resolving(_) | SessionUnavailable => return @html.nothing
      }
  }
  let progress = match input.departure {
    SavingBeforeLogin(_) => "Saving before sign-in…"
    PreparingLogin(_) | PreparedLogin(_, _) => "Opening Google…"
    _ => ""
  }
  @html.div(class="flex min-w-0 flex-wrap items-center gap-1", [
    @html.span(
      hidden=progress == "",
      class="text-xs text-lm-muted",
      attrs=@html.Attrs::build().role("status"),
      @html.text(progress),
    ),
    @html.button(
      type_="button",
      class="min-h-8 shrink-0 cursor-pointer rounded-md border border-lm-rule bg-transparent px-2 py-1 text-xs text-lm-ink hover:bg-lm-foundation focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-lm-accent disabled:cursor-default disabled:opacity-60 max-[641px]:min-h-11",
      disabled~,
      on_click=command,
      @html.text(label),
    ),
  ])
}

///|
fn account_notice(input : AccountControlsInput) -> @rabbita.Html {
  let message = match input.departure {
    LoginFailed(SaveFailed(_)) =>
      "Changes could not be saved. Retry sign-in to save again. You have not left this page."
    LoginFailed(AuthenticationFailed) =>
      "Google sign-in did not complete. Try again. Your documents remain in this browser."
    _ =>
      match input.session {
        LogoutUnconfirmed(_) =>
          "Sign-out could not be confirmed. Retry sign-out or check your account."
        _ => return @html.nothing
      }
  }
  @html.p(
    class="m-0 shrink-0 bg-lm-danger-soft px-3 py-2 text-sm text-lm-danger",
    attrs=@html.Attrs::build().role("alert"),
    @html.text(message),
  )
}
