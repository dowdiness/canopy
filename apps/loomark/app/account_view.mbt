///|
priv enum AccountIntent {
  RetryAccount
  SignIn(@sign_in.Action)
  LogoutRequested
}

///|
fn account_controls(
  input : AccountControlsInput,
  emit : @rabbita.Emit[AccountIntent],
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
  let (label, disabled, command) = match input.sign_in {
    @sign_in.InProgress(cancel) =>
      ("Cancel sign-in", false, emit(SignIn(cancel)))
    Leaving => ("Signing in…", true, @cmd.none)
    Available(start) => ("Login with Google", false, emit(SignIn(start)))
    Failed(_, retry=Some(retry)) =>
      ("Retry sign-in", false, emit(SignIn(retry)))
    Unavailable | Failed(_, retry=None) =>
      match input.session {
        NoAccount =>
          (
            if input.sign_in is @sign_in.Failed(_, ..) {
              "Retry sign-in"
            } else {
              "Login with Google"
            },
            true,
            @cmd.none,
          )
        Current(_, _) => ("Sign out", false, emit(LogoutRequested))
        Revoking(_) => ("Signing out…", true, @cmd.none)
        LogoutUnconfirmed(_) => ("Retry sign-out", false, emit(LogoutRequested))
        Resolving(_) => ("Checking account…", true, @cmd.none)
        SessionUnavailable => return @html.nothing
      }
  }
  let progress = if input.sign_in is @sign_in.InProgress(_) {
    "Signing in…"
  } else {
    ""
  }
  let google_sign_in = input.session is NoAccount &&
    !(input.sign_in is @sign_in.InProgress(_))
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
        "flex min-h-11 w-full min-w-0 cursor-pointer items-center justify-center gap-2.5 rounded-full border border-lm-rule bg-lm-surface px-4 py-2 text-sm font-medium text-lm-ink hover:bg-lm-foundation active:bg-lm-foundation focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-lm-accent disabled:cursor-default disabled:opacity-60"
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
