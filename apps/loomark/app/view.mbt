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
  let icon_class = "pointer-events-none block size-4"
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
    class="loomark-mode-button",
    attrs=@html.Attrs::build().aria_label(name),
    style=[
      "width:2.25rem;height:2.25rem;min-height:2.25rem;flex:none;padding:0",
    ],
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
    Unavailable => @html.nothing
    SyncUnavailable =>
      sync_status_button("Retry document connection", RetryAccount, emit)
  }
}

///|
fn local_durability_view(durability : LocalDurability) -> @rabbita.Html {
  match durability {
    NotStarted => sync_status_label("Write to save on this device")
    Saving => sync_status_label("Saving on this device", compact="Saving")
    Stored => sync_status_label("Saved on this device", compact="Saved")
    NotStored => sync_status_label("Not saved")
  }
}

///|
fn save_indicator(
  durability : LocalDurability?,
  persistence : @replica_persistence.Status?,
) -> @rabbita.Html {
  let (label, icon) = match durability {
    None | Some(NotStarted) => return @html.nothing
    Some(NotStored) => ("Not saved", @view.unsaved_icon("block size-4"))
    Some(Saving) if persistence is Some(Retryable(_, _)) =>
      ("Not saved", @view.unsaved_icon("block size-4"))
    Some(Saving) => ("Saving on this device", @view.saving_icon("block size-4"))
    Some(Stored) => ("Saved on this device", @view.saved_icon("block size-4"))
  }
  @html.span(
    class="loomark-save-status inline-flex h-9 shrink-0 items-center",
    title=label,
    attrs=@html.Attrs::build().role("status").aria_label(label),
    [icon, @html.span(class="loomark-save-caption", label)],
  )
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
      if account is Unavailable {
        @html.nothing
      } else {
        @html.span(
          class="text-lm-rule max-[641px]:hidden",
          attrs=@html.Attrs::build().aria_hidden("true"),
          "·",
        )
      },
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
    class="flex min-w-0 flex-1 flex-nowrap items-center justify-end gap-1 overflow-x-auto text-xs text-lm-muted [scrollbar-width:none]",
    attrs=@html.Attrs::build().role("status").aria_live("polite"),
    [account, durability, persistence, sync, remote, activity, opening],
  )
}

///|
fn file_actions(
  input_id : String,
  import_disabled : Bool,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let action_class = "flex min-h-9 min-w-0 cursor-pointer items-center justify-center gap-2 rounded-md border border-lm-rule bg-lm-surface px-2 py-1.5 text-xs text-lm-muted transition-colors duration-150 hover:bg-lm-accent-soft hover:text-lm-accent focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-lm-accent max-[641px]:min-h-11"
  @html.div(class="grid min-w-0 grid-cols-2 gap-2", [
    @html.label(
      class="relative \{action_class} has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-1 has-[:focus-visible]:outline-lm-accent",
      title="Import Markdown",
      for_=input_id,
      [
        @view.upload_icon("pointer-events-none block size-4 shrink-0"),
        @html.span("Import"),
        @html.input(
          input_type=File,
          id=input_id,
          class="sr-only",
          on_files=emit.map(files => ImportFilesSelected(files)),
          attrs=@html.Attrs::build()
            .aria_label("Import Markdown")
            .disabled(import_disabled),
        ),
      ],
    ),
    @html.button(
      type_="button",
      class=action_class,
      title="Export Markdown",
      attrs=@html.Attrs::build().aria_label("Export Markdown"),
      on_click=emit(ExportRequested),
      [
        @view.download_icon("pointer-events-none block size-4 shrink-0"),
        @html.span("Export"),
      ],
    ),
  ])
}

///|
fn sidebar_tools(
  scope : @sidebar.SidebarScope,
  editing : EditingState,
  account : AccountControlsInput,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @sidebar.sidebar_footer(class="border-t border-lm-rule", [
    examples_bar(
      emit,
      editing.activation,
      @sidebar.sidebar_collapse(scope),
      disabled=editing.creation is Creating(_) ||
        account.departure.editor_disabled(),
    ),
    file_actions("loomark-import", account.departure.editor_disabled(), emit),
  ])
}

///|
fn mode_bar(
  editing : EditingState,
  account : AccountControlsInput,
  sync_status : @rabbita.Html,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.header(
    class="loomark-topbar flex h-12 shrink-0 items-center justify-end gap-1 px-6 max-[520px]:h-[52px] max-[520px]:px-3",
    [
      @html.button(
        type_="button",
        class="loomark-icon",
        title="New document",
        attrs=@html.Attrs::build()
          .aria_label("New document")
          .disabled(
            !editing.can_activate() || account.departure.editor_disabled(),
          ),
        on_click=emit(CreateRequested),
        @view.square_pen_icon("block size-4"),
      ),
      @html.button(
        type_="button",
        class="loomark-icon",
        title="More actions",
        attrs=@html.Attrs::build()
          .id("loomark-more-actions")
          .aria_label("More actions")
          .aria_controls("loomark-more-actions-content")
          .aria_expanded(if editing.menu_open { "true" } else { "false" }),
        on_click=emit(MenuToggled),
        @view.more_icon("block size-4"),
      ),
      if editing.menu_open {
        @html.div(id="loomark-more-actions-content", class="loomark-menu", [
          @html.div(class="loomark-menu-status", sync_status),
          @html.div(
            class="flex flex-col gap-1 border-b border-lm-rule px-1 pb-2",
            [
              @html.span(class="text-xs font-medium text-lm-ink", "Account"),
              account_controls(account, emit),
            ],
          ),
          file_actions(
            "loomark-menu-import",
            account.departure.editor_disabled(),
            emit,
          ),
        ])
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn document_sidebar_trigger(
  scope : @sidebar.SidebarScope,
  compact : Bool,
) -> @rabbita.Html {
  let focus = compact && @sidebar.sidebar_is_collapsed(scope)
  @sidebar.sidebar_trigger(
    scope,
    mobile=false,
    controls="loomark-document-sidebar",
    aria_label="Toggle documents",
    class="loomark-sidebar-trigger fixed left-3 z-50 active:opacity-50 max-[520px]:left-2",
    on_click=if focus {
      @sidebar.sidebar_focus("loomark-document-sidebar")
    } else {
      @cmd.none
    },
    @view.panel_icon("block size-4 shrink-0"),
  )
}

///|
fn text_area_view(
  emit : @rabbita.Emit[Msg],
  editor : @editor.MarkdownEditor,
  activation : Activation,
  placeholder? : String,
  disabled? : Bool,
  read_only? : Bool,
) -> @rabbita.Html {
  @html.div(
    class="loomark-source-frame h-full min-h-0 w-full min-w-0",
    Map([
      (
        "activation-\{activation.generation}",
        editor.input_view(
          "Text",
          input => emit(InputChanged(activation.generation, input)),
          composing => {
            if composing {
              emit(CompositionStarted(activation.generation))
            } else {
              emit(CompositionEnded(activation.generation))
            }
          },
          disabled?,
          read_only?,
          rows=24,
          placeholder?,
          autofocus=true,
          class="loomark-source m-0 block h-full min-h-0 w-full min-w-0 resize-none rounded-none border-0 bg-transparent font-lm-mono text-base text-lm-ink caret-lm-accent outline-0 [tab-size:2]",
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
fn example_creation_failure_view(
  activation : Activation,
  text : String,
  failure : @source_repository.CreateFailure,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let reason = match failure {
    @source_repository.CreateFailure::DocumentIdentityUnavailable =>
      "This browser cannot create a document identity."
  }
  failure_notice(
    "The example document could not be created. " + reason,
    "Try again",
    emit(ExampleSelected(activation, text)),
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
  sync_attention : @rabbita.Html,
  replica_persistence : @replica_persistence.Status?,
  delete_dialog : @rabbita.Html,
  recent_navigation : @rabbita.Html,
) -> @rabbita.Html {
  @html.div(
    id="loomark-root",
    class="flex h-full min-h-0 w-full min-w-0 overflow-hidden bg-lm-foundation font-lm-ui text-lm-ink scheme-light selection:bg-lm-accent-soft",
    attrs=@html.Attrs::build()
      .role("region")
      .aria_label("Loomark Markdown Editor"),
    [
      match model {
        Loading(_) | PreparingNew(_) =>
          @html.div(
            class="grid min-h-full place-items-center text-lm-muted [&_p]:m-0",
            [@html.p("Loading document")],
          )
        Recovery(failure, _) | NewPreparationFailed(_, failure) => {
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
        Editing(editing) => {
          let editor_inert = editing.compact &&
            !@sidebar.sidebar_is_collapsed(sidebar)
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
                class="loomark-sidebar [--rui-sidebar:var(--color-lm-foundation)] [--rui-sidebar-foreground:var(--color-lm-ink)] [--rui-sidebar-border:var(--color-lm-rule)] [--rui-sidebar-accent:var(--color-lm-accent-soft)] [--rui-sidebar-accent-foreground:var(--color-lm-accent)]",
                [
                  recent_navigation,
                  sidebar_tools(sidebar, editing, account, emit),
                ],
              ),
              document_sidebar_trigger(sidebar, editing.compact),
              @html.div(
                id="loomark-editor",
                class="relative flex h-full min-h-0 min-w-0 flex-1 flex-col overflow-hidden bg-lm-paper",
                attrs=@html.Attrs::build().inert(editor_inert),
                [
                  mode_bar(editing, account, sync_status, emit),
                  account_notice(account),
                  mode_content(editing.mode, editor_panels),
                  @html.footer(
                    class="loomark-footer flex h-16 shrink-0 items-center justify-between gap-2 px-3 max-[520px]:px-2",
                    [
                      @html.div(
                        class="loomark-footer-status flex min-w-0 flex-1 items-center gap-2",
                        [
                          save_indicator(
                            local_durability(editing, editing.activation.key),
                            replica_persistence,
                          ),
                          @html.div(
                            class="loomark-sync-attention min-w-0",
                            sync_attention,
                          ),
                        ],
                      ),
                      @html.div(
                        class="loomark-bottom-actions flex shrink-0 items-center gap-2",
                        [
                          @rui.tabs_root(
                            value=mode_name(editing.mode).to_lower(),
                            style=["width:auto"],
                            @rui.tabs_list(
                              orientation=@rui.TabsHorizontal,
                              variant=@rui.TabsDefault,
                              aria_label="Editor mode",
                              [
                                mode_tab(Text, editing.mode, emit),
                                mode_tab(Split, editing.mode, emit),
                                mode_tab(Preview, editing.mode, emit),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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
                    (_, ExampleCreationFailed(text, failure)) =>
                      example_creation_failure_view(
                        editing.activation,
                        text,
                        failure,
                        emit,
                      )
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
        }
      },
      delete_dialog,
    ],
  )
}
