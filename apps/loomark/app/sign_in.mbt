///|
fn sign_in_readiness(model : Model) -> @sign_in.Readiness {
  match model.sync().session() {
    Resolving(_) => CheckingAccount
    Current(_, _) | Revoking(_) | LogoutUnconfirmed(_) => SignedIn
    SessionUnavailable => AccountUnavailable
    NoAccount => {
      guard model.page is Editing(editing) else {
        return @sign_in.EditorUnavailable
      }
      let editor : @sign_in.Editor = if creation_in_progress(editing.creation) {
        Creating
      } else if editing.imports_pending > 0 {
        Importing
      } else if editing.deletion != NoDeletion {
        ConfirmingDelete
      } else {
        Ready
      }
      @sign_in.SignedOut(
        editor~,
        durability=editing.documents.local_durability(
          model.replication.persistence(),
        ),
      )
    }
  }
}

///|
fn interrupt_sign_in(model : Model, msg : Msg) -> Model {
  if is_user_mutating(msg) && model.sign_in.blocks_editing() {
    let transition = model.sign_in.update(
      @sign_in.Interrupted,
      sign_in_readiness(model),
    )
    { ..model, sign_in: transition.state, }
  } else {
    model
  }
}

///|
fn save_changes(model : Model, emit : @rabbita.Emit[Msg]) -> (Model, @cmd.Cmd, Bool) {
  guard model.page is Editing(editing) else {
    abort("sign-in requested saving without an editor")
  }
  let outcome : Result[(@documents.Model, Array[@documents.Action]), String] = Ok(
    editing.documents.save_changes(),
  ) catch {
    @documents.DeleteError::DocumentMissing(_) =>
      Err("A document disappeared before sign-in could save changes. The current text was retained.")
    @documents.DeleteError::OwnershipTransferInProgress(_) =>
      Err("A document is being transferred and cannot be saved for sign-in yet. The current text was retained.")
    @documents.DeleteError::ReplicaMissing(_) =>
      Err("A synchronized document is unavailable. The current text was retained; retry after synchronization recovers.")
  }
  match outcome {
    Err(error) => {
      let interrupted = model.sign_in.update(
        @sign_in.Interrupted,
        sign_in_readiness(model),
      )
      ({ ..model, sign_in: interrupted.state, page: Editing({ ..editing, lifecycle_error: Some(error), }), }, @cmd.none, false)
    }
    Ok((documents, actions)) => {
      let (model, command) = apply_document_actions(
        { ..model, page: Editing({ ..editing, documents, lifecycle_error: None, }), },
        actions,
        emit,
      )
      let saved = documents.snapshot()
      let mut model = model
      let commands = [command]
      // Persistence also owns writes whose document is no longer projected.
      for write in model.replication.persistence().pending_writes() {
        let replica = write.replica()
        if model.replication
          .persistence()
          .status(replica.account(), replica.document_id())
          is @replica_persistence.Retryable(_, _) {
          let (replication, effect) = model.replication.retry_document(
            replica.account(),
            replica.document_id(),
          )
          model = { ..model, replication, }
          if effect is Some(effect) {
            commands.push(run_replication_effect(saved, effect, emit))
          }
        }
      }
      (model, @cmd.batch(commands), true)
    }
  }
}

///|
fn update_sign_in(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  let event : @sign_in.Event = match msg {
    SignIn(event) => event
    AuthenticationReturned(true) => AuthenticationFailed
    PageRestored => PageRestored
    _ => return (model, @cmd.none)
  }
  // Idle sign-in does not need to scan all local writes after each editor event.
  if event is @sign_in.Refresh && !model.sign_in.blocks_editing() {
    return (model, @cmd.none)
  }
  let transition = model.sign_in.update(event, sign_in_readiness(model))
  let mut model = { ..model, sign_in: transition.state, }
  let commands : Array[@cmd.Cmd] = []
  for effect in transition.effects {
    match effect {
      @sign_in.SaveChanges => {
        let (saved, command, can_advance) = save_changes(model, emit)
        commands.push(command)
        if can_advance {
          // Observe only after document actions have updated persistence ownership.
          let (advanced, next) = update_sign_in(
            saved,
            SignIn(@sign_in.Refresh),
            emit,
          )
          model = advanced
          commands.push(next)
        } else {
          model = saved
        }
      }
      RequestAuthorizationUrl(request) =>
        commands.push(
          @account_http.request_authorization_url(
            emit.map(url => SignIn(@sign_in.AuthorizationReceived(request, url))),
          ),
        )
      Navigate(url) =>
        commands.push(@cmd.custom_cmd(_ => load_url(url.value())))
      FocusEditor =>
        if model.page is Editing(editing) {
          commands.push(focus_after_render(editor_focus_id(editing.mode)))
        }
      CheckAccount => {
        let (checked, command) = begin_account_lookup(model, emit)
        model = checked
        commands.push(command)
      }
    }
  }
  (model, @cmd.batch(commands))
}
