///|
fn mode_name(mode : EditorMode) -> String {
  match mode {
    Text => "Text"
    Preview => "Preview"
    Split => "Split"
  }
}

///|
fn mode_dom_id(mode : EditorMode) -> String {
  "loomark-mode-\{mode_name(mode).to_lower()}"
}

///|
fn mode_tab(
  mode : EditorMode,
  selected_mode : EditorMode,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let name = mode_name(mode)
  let icon_class = "pointer-events-none block size-4.5 transition-colors duration-150 group-hover:text-[oklch(0.145_0_0)]"
  let icon = match mode {
    Text => @view.text_mode_icon(icon_class)
    Preview => @view.preview_mode_icon(icon_class)
    Split => @view.split_mode_icon(icon_class)
  }
  @rui.tabs_trigger(
    value=name.to_lower(),
    selected=mode == selected_mode,
    controls="loomark-editor-panel",
    id=mode_dom_id(mode),
    on_value_change=@cmd.Emit(_ => emit(ModeSelected(mode))),
    title=name,
    class="group",
    attrs=@html.Attrs::build().aria_label(name),
    style=["width:2rem;height:2rem;min-height:2rem;flex:none;padding:0"],
    icon,
  )
}

///|
fn mode_content(mode : EditorMode, content : @rabbita.Html) -> @rabbita.Html {
  @rui.tabs_content(
    value=mode_name(mode).to_lower(),
    selected=true,
    labelledby=mode_dom_id(mode),
    id="loomark-editor-panel",
    class="min-h-0 min-w-0 flex-1 flex-col overflow-hidden",
    style=["display:flex"],
    content,
  )
}

///|
fn sync_status_label(text : String, compact? : String = text) -> @rabbita.Html {
  @html.span(class="min-w-0 truncate px-1.5 py-1", title=text, [
    @html.span(class="max-[641px]:hidden", text),
    @html.span(class="min-[642px]:hidden", compact),
  ])
}

///|
fn sync_status_button(
  text : String,
  message : Msg,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.button(
    type_="button",
    class="min-h-8 shrink-0 cursor-pointer rounded-md border border-lm-rule bg-transparent px-2 py-1 text-xs text-lm-muted transition-colors duration-150 hover:bg-[oklch(0.955_0.003_255)] hover:text-lm-ink focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-lm-accent max-[641px]:min-h-11",
    on_click=emit(message),
    text,
  )
}

///|
fn account_status_view(
  status : AccountStatus,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match status {
    Checking => sync_status_label("Checking account", compact="Checking")
    SignedOut => sync_status_label("Signed out")
    SignedIn(name) => sync_status_label(name)
    SigningOut(name) | SignOutUnconfirmed(name) => sync_status_label(name)
    Unavailable => sync_status_button("Retry account", RetryAccount, emit)
    SyncUnavailable => sync_status_button("Retry sync", RetryAccount, emit)
  }
}

///|
fn local_durability_view(durability : LocalDurability) -> @rabbita.Html {
  match durability {
    Saving => sync_status_label("Saving on this device", compact="Saving")
    Stored => sync_status_label("Saved on this device", compact="Saved")
    NotStored => sync_status_label("Not saved")
  }
}

///|
fn remote_state_view(
  remote : @documents.RemoteState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match remote {
    @documents.RemoteState::Current => sync_status_label("Synced")
    LocalAhead => sync_status_label("Local changes")
    RemoteAhead => sync_status_label("Update pending")
    Concurrent => sync_status_label("Checking changes")
    Diverged => sync_status_label("Conflict")
    DeletedRemotely => sync_status_label("Deletion pending")
    UpdateAvailable(action) =>
      sync_status_button("Open update", AcceptRemote(action), emit)
    DeletionAvailable(action) =>
      sync_status_button("Remove deleted document", AcceptRemote(action), emit)
    Unavailable => @html.nothing
  }
}

///|
fn replica_persistence_view(
  persistence : @replica_persistence.Status,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match persistence {
    @replica_persistence.Status::Current => @html.nothing
    Persisting => sync_status_label("Saving sync state", compact="Saving sync")
    Retryable(action, _) =>
      sync_status_button("Retry saving", RetrySaving(action), emit)
  }
}

///|
fn activity_view(
  activity : @sync.Activity,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match activity {
    @sync.Activity::Idle => @html.nothing
    Working => sync_status_label("Syncing")
    Retryable(action) =>
      sync_status_button("Retry sync", RetrySync(action), emit)
    Blocked => sync_status_label("Sync paused")
  }
}

///|
fn selection_activity_view(
  activity : @sync.SelectionActivity,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match activity {
    @sync.SelectionActivity::Idle => @html.nothing
    Working => sync_status_label("Opening")
    Retryable(action) =>
      sync_status_button("Retry opening", RetrySelection(action), emit)
  }
}

///|
fn render_document_sync(
  sync : DocumentSync,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match sync {
    DeviceOnly | Unavailable => @html.nothing
    SyncAvailable(action) => sync_status_button("Sync", StartSync(action), emit)
    Linking => sync_status_label("Preparing sync", compact="Preparing")
    Linked => @html.nothing
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
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match sync {
    None => @html.nothing
    Some(sync) => render_document_sync(sync, emit)
  }
}

///|
fn replica_persistence_option_view(
  persistence : @replica_persistence.Status?,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match persistence {
    None => @html.nothing
    Some(persistence) => replica_persistence_view(persistence, emit)
  }
}

///|
fn remote_state_option_view(
  remote : @documents.RemoteState?,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match remote {
    None => @html.nothing
    Some(remote) => remote_state_view(remote, emit)
  }
}

///|
fn activity_option_view(
  activity : @sync.Activity?,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match activity {
    None => @html.nothing
    Some(activity) => activity_view(activity, emit)
  }
}

///|
fn account_status_section(
  account : AccountStatus,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.div(
    class=match account {
      SignedIn(_) => "contents max-[820px]:hidden"
      Checking
      | SignedOut
      | SigningOut(_)
      | SignOutUnconfirmed(_)
      | Unavailable
      | SyncUnavailable => "contents"
    },
    [
      account_status_view(account, emit),
      @html.span(
        class="text-lm-rule max-[641px]:hidden",
        attrs=@html.Attrs::build().aria_hidden("true"),
        "·",
      ),
    ],
  )
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
    class="flex min-w-0 flex-wrap items-center justify-center gap-1 text-xs text-lm-muted max-[641px]:order-3 max-[641px]:w-full",
    attrs=@html.Attrs::build().role("status").aria_live("polite"),
    [account, durability, persistence, sync, remote, activity, opening],
  )
}

///|
fn mode_bar(
  scope : @sidebar.SidebarScope,
  editing : EditingState,
  account : AccountControlsInput,
  sync_status : @rabbita.Html,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let toolbar_control_spacing = if @sidebar.sidebar_is_collapsed(scope) {
    "pl-9"
  } else {
    ""
  }
  @html.header(
    class="relative flex min-h-11 shrink-0 flex-wrap items-center justify-between gap-2 border-b border-lm-rule bg-lm-surface px-3 py-1 max-[641px]:px-2 max-[641px]:py-0",
    [
      @html.div(
        class="flex min-w-0 items-center gap-2 \{toolbar_control_spacing}",
        [
          @sidebar.sidebar_trigger(
            scope,
            mobile=false,
            controls="loomark-document-sidebar",
            aria_label="Toggle documents",
            class="fixed top-[0.5625rem] left-3 z-20 active:opacity-50 max-[641px]:left-2",
            @view.panel_icon("block size-4 shrink-0"),
          ),
          @rui.tabs_root(
            value=mode_name(editing.mode).to_lower(),
            style=["width:auto"],
            @rui.tabs_list(
              orientation=@rui.TabsHorizontal,
              variant=@rui.TabsDefault,
              aria_label="Editor mode",
              [
                mode_tab(Text, editing.mode, emit),
                mode_tab(Preview, editing.mode, emit),
                mode_tab(Split, editing.mode, emit),
              ],
            ),
          ),
        ],
      ),
      sync_status,
      @html.div(class="flex min-w-0 flex-wrap items-center gap-1", [
        examples_bar(
          emit,
          editing.activation,
          disabled=editing.creation is Creating(_) ||
            account.departure.editor_disabled(),
        ),
        @html.label(
          class="relative flex min-h-8 w-8 shrink-0 cursor-pointer items-center justify-center rounded-md border border-lm-rule bg-transparent p-0 text-lm-muted transition-colors duration-150 hover:bg-[oklch(0.955_0.003_255)] hover:text-lm-ink has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-1 has-[:focus-visible]:outline-lm-accent max-[641px]:min-h-11",
          title="Import Markdown",
          for_="loomark-import",
          [
            @view.upload_icon("pointer-events-none block size-4"),
            @html.input(
              input_type=File,
              id="loomark-import",
              class="sr-only",
              on_files=emit.map(files => ImportFilesSelected(files)),
              attrs=@html.Attrs::build()
                .aria_label("Import Markdown")
                .disabled(account.departure.editor_disabled()),
            ),
          ],
        ),
        @html.button(
          type_="button",
          class="flex min-h-8 w-8 shrink-0 cursor-pointer items-center justify-center rounded-md border border-lm-rule bg-transparent p-0 text-lm-muted transition-colors duration-150 hover:bg-[oklch(0.955_0.003_255)] hover:text-lm-ink focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-lm-accent max-[641px]:min-h-11",
          title="Export Markdown",
          attrs=@html.Attrs::build().aria_label("Export Markdown"),
          on_click=emit(ExportRequested),
          @view.download_icon("pointer-events-none block size-4"),
        ),
        account_controls(account, emit),
      ]),
    ],
  )
}

///|
fn text_area_view(
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
  activation : Activation,
  disabled? : Bool,
  read_only? : Bool,
) -> @rabbita.Html {
  @html.div(
    class="h-full min-h-0 w-full min-w-0",
    Map([
      (
        "activation-\{activation.generation}",
        @html.textarea(
          rows=24,
          autofocus=true,
          disabled?,
          read_only?,
          class="m-0 block h-full min-h-0 w-full min-w-0 resize-none rounded-none border-0 bg-transparent px-[max(3rem,calc((100%_-_44rem)_/_2))] pt-8 pb-16 font-lm-mono text-base leading-[1.65] text-lm-ink caret-lm-accent outline-0 [tab-size:2] max-[641px]:px-3 max-[641px]:pt-6 max-[641px]:pb-12",
          attrs=text_area.attach(
            @html.Attrs::build().aria_label("Text"),
            change => emit(TextChanged(activation.generation, change)),
            composing => {
              if composing {
                emit(CompositionStarted(activation.generation))
              } else {
                emit(CompositionEnded(activation.generation))
              }
            },
          ),
          @html.nothing,
        ),
      ),
    ]),
  )
}

///|
fn import_failure_view(emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  failure_notice(
    "The Markdown file could not be imported.",
    "Dismiss",
    emit(DismissImportFailure),
  )
}

///|
fn creation_failure_view(
  failure : @source_repository.CreateFailure,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let reason = match failure {
    @source_repository.CreateFailure::DocumentIdentityUnavailable =>
      "This browser cannot create a document identity."
  }
  failure_notice(
    "A new document could not be created. " + reason,
    "Retry creating",
    emit(CreateRequested),
  )
}

///|
fn delete_failure_view(
  document_id : @documents.Key,
  failure : @source_repository.DeleteFailure,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let reason = match failure {
    InvalidSource => "The document is no longer available."
    StorageUnavailable => "Browser storage is unavailable."
    QuotaExceeded => "Browser storage is full."
    WriteFailed => "Browser storage failed while deleting the document."
  }
  @html.div(
    class="flex min-h-12 shrink-0 items-center justify-between gap-4 bg-lm-danger-soft px-4 py-2.5 text-sm text-lm-danger",
    attrs=@html.Attrs::build().role("alert"),
    [
      @html.p("The document was not deleted. " + reason),
      @html.div(class="flex shrink-0 gap-2", [
        @html.button(
          class="min-h-8 rounded-md border border-current px-2.5 py-1",
          on_click=emit(RetryDelete(document_id)),
          "Try again",
        ),
        @html.button(
          class="min-h-8 rounded-md border border-current px-2.5 py-1",
          on_click=emit(DismissDeleteFailure(document_id)),
          "Dismiss",
        ),
      ]),
    ],
  )
}

///|
fn delete_persistence_failure_view(
  document_id : @documents.Key,
  failure : @source_repository.ReplicaFailure,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let reason = match failure {
    InvalidReplica => "The synchronized document state is invalid."
    StorageUnavailable => "Browser storage is unavailable."
    QuotaExceeded => "Browser storage is full."
    WriteFailed => "Browser storage failed while saving the deletion."
  }
  failure_notice(
    "The deletion was not saved. " + reason,
    "Try again",
    emit(RetryDelete(document_id)),
  )
}

///|
fn save_failure_view(
  failure : @source_repository.SaveFailure,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let reason = match failure {
    @source_repository.SaveFailure::InvalidSource =>
      " The document identity is invalid."
    @source_repository.SaveFailure::StorageUnavailable =>
      " Browser storage is unavailable."
    @source_repository.SaveFailure::QuotaExceeded => " Browser storage is full."
    @source_repository.SaveFailure::WriteFailed =>
      " Browser storage failed while writing the document."
  }
  failure_notice(
    "Changes are not saved in this browser." + reason,
    "Retry saving",
    emit(RetrySave),
  )
}

///|
fn view(
  sidebar : @sidebar.SidebarScope,
  model : Page,
  account : AccountControlsInput,
  emit : @rabbita.Emit[Msg],
  editor_panels : @rabbita.Html,
  sync_status : @rabbita.Html,
  delete_dialog : @rabbita.Html,
  recent_navigation : @rabbita.Html,
) -> @rabbita.Html {
  @html.div(
    id="loomark-root",
    class="flex h-dvh min-h-0 w-full min-w-0 overflow-hidden bg-lm-foundation font-lm-ui text-lm-ink scheme-light selection:bg-[oklch(0.78_0.08_276/0.45)]",
    attrs=@html.Attrs::build()
      .role("region")
      .aria_label("Loomark Markdown Editor"),
    [
      match model {
        Loading(_) | PreparingNew(_) =>
          @html.div(
            class="grid min-h-dvh place-items-center text-lm-muted [&_p]:m-0",
            [@html.p("Loading document")],
          )
        Recovery(failure, _) => {
          let message = match failure {
            @source_repository.OpenFailure::StorageUnavailable =>
              "Browser storage is unavailable."
            @source_repository.OpenFailure::ReadFailed =>
              "Browser storage failed while reading the document."
          }
          @html.div(
            class="mx-auto w-[min(calc(100%-2rem),36rem)] pt-[max(4rem,20vh)] pb-8 [&_h1]:mt-0 [&_h1]:mb-3 [&_h1]:text-xl [&_h1]:leading-[1.3] [&_p]:m-0 [&_p]:leading-[1.6] [&_p]:text-lm-muted",
            [@html.h1("Document recovery"), @html.p(message)],
          )
        }
        Editing(editing) =>
          @html.div(
            class="flex h-full min-h-0 min-w-0 flex-1 opacity-100 transition-opacity duration-[140ms] ease-[cubic-bezier(0.23,1,0.32,1)] starting:opacity-[0.92] motion-reduce:duration-[80ms] motion-reduce:ease-[ease]",
            [
              @sidebar.sidebar(
                sidebar,
                id="loomark-document-sidebar",
                mobile=false,
                side=@sidebar.SidebarLeft,
                variant=@sidebar.SidebarDefault,
                collapsible=@sidebar.SidebarOffcanvas,
                aria_label="Documents",
                class="[--rui-sidebar:var(--color-lm-foundation)] [--rui-sidebar-foreground:var(--color-lm-ink)] [--rui-sidebar-border:var(--color-lm-rule)] [--rui-sidebar-accent:var(--color-lm-accent-soft)] [--rui-sidebar-accent-foreground:var(--color-lm-accent)]",
                recent_navigation,
              ),
              @html.div(
                class="flex h-full min-h-0 min-w-0 flex-1 flex-col overflow-hidden bg-lm-paper",
                [
                  mode_bar(sidebar, editing, account, sync_status, emit),
                  account_notice(account),
                  mode_content(editing.mode, editor_panels),
                  match
                    (
                      editing.documents.save_status(editing.activation.key),
                      editing.creation,
                    ) {
                    (Some(@documents.SaveStatus::SaveFailed(failure)), _) if !(account.departure
                      is LoginFailed(SaveFailed(_))) =>
                      save_failure_view(failure, emit)
                    (_, CreationFailed(failure)) =>
                      creation_failure_view(failure, emit)
                    _ =>
                      match
                        editing.documents.delete_status(editing.activation.key) {
                        Some(@documents.DeleteStatus::DeleteFailed(failure)) =>
                          delete_failure_view(
                            editing.activation.key,
                            failure,
                            emit,
                          )
                        Some(
                          @documents.DeleteStatus::DeletePersistenceFailed(
                            failure
                          )
                        ) =>
                          delete_persistence_failure_view(
                            editing.activation.key,
                            failure,
                            emit,
                          )
                        _ => @html.nothing
                      }
                  },
                  if editing.import_failed {
                    import_failure_view(emit)
                  } else {
                    @html.nothing
                  },
                ],
              ),
            ],
          )
      },
      delete_dialog,
    ],
  )
}
