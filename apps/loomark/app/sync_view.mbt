///|
priv enum SyncIntent {
  RetryAccount
  StartSync(@documents.StartSync)
  AcceptRemote(@documents.AcceptRemote)
  RetrySaving(@replica_persistence.Retry)
  RetrySync(@sync.Retry)
  RetrySelection(@sync.SelectionRetry)
}

///|
fn sync_status_label(text : String) -> @rabbita.Html {
  @html.span(hidden=text.is_empty(), class="min-w-0 px-1.5 py-1", text)
}

///|
fn sync_status_button(
  text : String,
  message : SyncIntent?,
  emit : @rabbita.Emit[SyncIntent],
) -> @rabbita.Html {
  @html.button(
    type_="button",
    hidden=message is None,
    class="min-h-8 shrink-0 cursor-pointer rounded-md border border-lm-rule bg-transparent px-2 py-1 text-xs text-lm-muted transition-colors duration-150 hover:bg-lm-foundation hover:text-lm-ink focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-lm-accent max-[641px]:min-h-11",
    on_click?=message.map(message => emit(message)),
    text,
  )
}

///|
fn account_status_view(
  status : AccountStatus,
  emit : @rabbita.Emit[SyncIntent],
) -> @rabbita.Html {
  match status {
    Checking
    | SignedOut
    | SignedIn(_)
    | SigningOut(_)
    | SignOutUnconfirmed(_)
    | Unavailable => @html.nothing
    SyncUnavailable =>
      sync_status_button("Retry document connection", Some(RetryAccount), emit)
  }
}

///|
fn local_durability_view(durability : LocalDurability) -> @rabbita.Html {
  match durability {
    NotStarted | Saving | Stored => @html.nothing
    NotStored => sync_status_label("Not saved on this device")
  }
}

///|
fn save_indicator(
  durability : LocalDurability?,
  persistence : @replica_persistence.Status?,
) -> @rabbita.Html {
  let (label, icon) = match durability {
    None | Some(NotStarted) =>
      (
        "",
        @html.span(
          hidden=true,
          attrs=@html.Attrs::build().aria_hidden("true"),
          @html.nothing,
        ),
      )
    Some(NotStored) => ("Not saved", @view.unsaved_icon("block size-4"))
    Some(Saving) if persistence is Some(Retryable(_, _)) =>
      ("Not saved", @view.unsaved_icon("block size-4"))
    Some(Saving) => ("Saving on this device", @view.saving_icon("block size-4"))
    Some(Stored) => ("Saved on this device", @view.saved_icon("block size-4"))
  }
  @html.span(
    class="loomark-save-status inline-flex h-9 shrink-0 items-center",
    title=label,
    attrs=@html.Attrs::build()
      .role("status")
      .aria_live("polite")
      .aria_atomic("true")
      .aria_label(label),
    [icon, @html.span(class="loomark-save-caption", label)],
  )
}

///|
fn remote_state_view(
  remote : @documents.RemoteState,
  emit : @rabbita.Emit[SyncIntent],
) -> @rabbita.Html {
  match remote {
    @documents.RemoteState::Current | LocalAhead | RemoteAhead | Concurrent =>
      @html.nothing
    Diverged => sync_status_label("Conflicting changes")
    DeletedRemotely => sync_status_label("Deletion pending")
    UpdateAvailable(action) =>
      sync_status_button("Open update", Some(AcceptRemote(action)), emit)
    DeletionAvailable(action) =>
      sync_status_button(
        "Remove deleted document",
        Some(AcceptRemote(action)),
        emit,
      )
    Unavailable => @html.nothing
  }
}

///|
fn replica_persistence_view(
  persistence : @replica_persistence.Status,
  emit : @rabbita.Emit[SyncIntent],
) -> @rabbita.Html {
  match persistence {
    @replica_persistence.Status::Current | Persisting => @html.nothing
    Retryable(action, _) =>
      @html.div(class="flex flex-col items-start gap-1", [
        sync_status_label("Sync information was not saved on this device."),
        sync_status_button("Retry saving", Some(RetrySaving(action)), emit),
      ])
  }
}

///|
fn activity_view(
  activity : @sync.Activity,
  durability : LocalDurability?,
  emit : @rabbita.Emit[SyncIntent],
) -> @rabbita.Html {
  match activity {
    @sync.Activity::Idle | Working => @html.nothing
    Retryable(action) =>
      @html.div(class="flex flex-col items-start gap-1", [
        sync_status_label(
          if durability is Some(Stored) {
            "Saved on this device. Sync failed."
          } else {
            "Sync failed."
          },
        ),
        sync_status_button("Retry sync", Some(RetrySync(action)), emit),
      ])
    Blocked => sync_status_label("Sync paused")
  }
}

///|
fn selection_activity_view(
  activity : @sync.SelectionActivity,
  emit : @rabbita.Emit[SyncIntent],
) -> @rabbita.Html {
  match activity {
    @sync.SelectionActivity::Idle | Working => @html.nothing
    Retryable(action) =>
      sync_status_button("Retry opening", Some(RetrySelection(action)), emit)
  }
}

///|
fn render_document_sync(
  sync : DocumentSync,
  emit : @rabbita.Emit[SyncIntent],
) -> @rabbita.Html {
  match sync {
    DeviceOnly | Unavailable | Linking | Linked => @html.nothing
    SyncAvailable(action) =>
      sync_status_button("Sync", Some(StartSync(action)), emit)
  }
}

///|
fn local_durability_option_view(durability : LocalDurability?) -> @rabbita.Html {
  match durability {
    None => @html.nothing
    Some(durability) => local_durability_view(durability)
  }
}

///|
fn document_sync_option_view(
  sync : DocumentSync?,
  emit : @rabbita.Emit[SyncIntent],
) -> @rabbita.Html {
  match sync {
    None => @html.nothing
    Some(sync) => render_document_sync(sync, emit)
  }
}

///|
fn replica_persistence_option_view(
  persistence : @replica_persistence.Status?,
  emit : @rabbita.Emit[SyncIntent],
) -> @rabbita.Html {
  match persistence {
    None => @html.nothing
    Some(persistence) => replica_persistence_view(persistence, emit)
  }
}

///|
fn remote_state_option_view(
  remote : @documents.RemoteState?,
  emit : @rabbita.Emit[SyncIntent],
) -> @rabbita.Html {
  match remote {
    None => @html.nothing
    Some(remote) => remote_state_view(remote, emit)
  }
}

///|
fn activity_option_view(
  activity : @sync.Activity?,
  durability : LocalDurability?,
  emit : @rabbita.Emit[SyncIntent],
) -> @rabbita.Html {
  match activity {
    None => @html.nothing
    Some(activity) => activity_view(activity, durability, emit)
  }
}

///|
fn sync_status_view(
  account : @rabbita.Html,
  durability : @rabbita.Html,
  persistence : @rabbita.Html,
  sync : @rabbita.Html,
  remote : @rabbita.Html,
  activity : @rabbita.Html,
  opening : @rabbita.Html,
) -> @rabbita.Html {
  @html.div(
    class="loomark-menu-attention flex min-w-0 flex-col items-start gap-1 text-xs text-lm-muted empty:hidden",
    attrs=@html.Attrs::build().role("status").aria_live("polite"),
    [account, durability, persistence, sync, remote, activity, opening],
  )
}
