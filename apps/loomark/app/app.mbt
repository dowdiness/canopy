///|
priv suberror TextAreaResizeSubscription {
  RevealResizedCaret
}

///|
/// Both the activation key and the responsive panel branch can replace the
/// textarea. Resolve its node after rendering and release the old observation.
fn text_area_resize_subscription(activation : Int, compact : Bool) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.text-area-resize(\{activation},\{compact})",
    @sub.Scope::Local,
    TextAreaResizeSubscription::RevealResizedCaret,
    (_, scheduler) => {
      let mut active = true
      let mut stop : (() -> Unit)? = None
      scheduler.add(
        @cmd.custom_cmd(kind=@cmd.after_render, _ => {
          guard active &&
            @dom.document().get_element_by_id(EDITOR_TEXT_ID).to_option()
            is Some(element) &&
            element.to_html_text_area_element() is Some(area) else {
            return
          }
          stop = Some(
            observe_text_area_resize(area) catch {
              @js.JsError(error) => {
                @js.global()
                .get("console")
                .call("error", [
                  @js.any("Loomark could not observe the text area:"),
                  error,
                ])
                |> ignore
                return
              }
            },
          )
        }),
      )
      Some({
        unload: _ => {
          active = false
          if stop is Some(stop) {
            stop()
          }
        },
        update_tagger: _ => (),
      })
    },
  )
}

///|
priv suberror SplitScrollSubscription {
  Follow(@editor.EditorState)
}

///|
/// Resolve this render's pair once. Activation and breakpoint changes replace
/// nodes; mode and scroll-owner changes also release the old connection.
fn split_scroll_subscription(
  source : String,
  target : String,
  activation : Int,
  compact : Bool,
  preview : @editor.EditorState,
) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.split-scroll(\{source},\{target},\{activation},\{compact})",
    @sub.Scope::Local,
    SplitScrollSubscription::Follow(preview),
    (payload, scheduler) => {
      guard payload is SplitScrollSubscription::Follow(preview) else {
        return None
      }
      let mut active = true
      let mut previous_preview = preview
      let mut connection : (() -> Unit, () -> Unit)? = None
      fn sync_after_render() {
        scheduler.add(
          @cmd.custom_cmd(kind=@cmd.after_render, _ => {
            guard active && connection is Some((sync, _)) else { return }
            sync()
          }),
        )
      }
      scheduler.add(
        @cmd.custom_cmd(kind=@cmd.after_render, _ => {
          guard active &&
            @dom.document().get_element_by_id(source).to_option() is Some(from) &&
            @dom.document().get_element_by_id(target).to_option() is Some(to) else {
            return
          }
          let connected = connect_split_scroll(from, to, sync_after_render)
          connection = Some(connected)
          // A scroll can precede this after-render connection when its owner
          // changes. Catch up from live geometry once the listener is attached.
          let (sync, _) = connected
          sync()
        }),
      )
      Some({
        unload: _ => {
          active = false
          if connection is Some((_, stop)) {
            stop()
          }
          connection = None
        },
        update_tagger: payload => {
          guard payload is SplitScrollSubscription::Follow(next) else { return }
          if previous_preview != next {
            previous_preview = next
            sync_after_render()
          }
        },
      })
    },
  )
}

///|
const LEAD_DELAY_MS : Int = 250

///|
fn lead_subscriptions(model : Page, emit : @rabbita.Emit[Msg]) -> @sub.Sub {
  let pending = match model {
    Editing(editing) => editing.documents.pending_edits()
    PreparingNew(preparing) | NewPreparationFailed(preparing, _) =>
      preparing.documents.pending_edits()
    Loading(_) | Recovery(_, _) => []
  }
  @sub.batch(
    pending.map(item => {
      let (key, revision) = item
      let lifecycle_key = key.lifecycle_key()
      @timeout.after(
        "loomark.pending-edit.\{lifecycle_key}-\{revision}",
        LEAD_DELAY_MS,
        emit(ApplyPendingEdit(key, revision)),
      )
    }),
  )
}

///|
/// Prototype: manage and switch Loomark documents inside RUI Sidebar.
pub fn app() -> @rabbita.Val[@rabbita.Html] {
  if @local_tabs.enabled() {
    return @local_tabs.app()
  }
  let editor = @editor.MarkdownEditor::MarkdownEditor(EDITOR_TEXT_ID)
  let initial_compact = compact_viewport(@browser.viewport_width())
  // Resolve stable browser handles once at the composition boundary.
  let window = @dom.window()
  let viewport_subscription = if window.get_visual_viewport() is Some(viewport) &&
    @dom.document().get_document_element() is Some(root) &&
    root.to_html_element() is Some(root) {
    visual_viewport_subscription(window, viewport, root)
  } else {
    @sub.none
  }
  let (model, emit) = @rabbita.create_state_with_init(
    init=emit => initial_state(emit, initial_compact),
    update=(model, msg, emit) => update(model, msg, emit, editor),
    subscriptions=(current, emit) => {
      @sub.batch([
        viewport_subscription,
        match current.page {
          Editing(editing) =>
            text_area_resize_subscription(
              editing.activation.generation,
              editing.compact,
            )
          _ => @sub.none
        },
        @sub.on_resize(viewport => emit(ViewportChanged(viewport.width))),
        @sub.on_visibility_change(hidden => emit(VisibilityChanged(hidden))),
        @sub.on_key_down(key => {
          if key.key() == "Escape" {
            emit(EscapePressed)
          } else {
            @cmd.none
          }
        }),
        page_restore_subscription(emit(PageRestored)),
        lead_subscriptions(current.page, emit),
        match current.page {
          Editing(editing) if editing.mode == Split =>
            match current.scroll_owner {
              TextPane =>
                split_scroll_subscription(
                  "loomark-text",
                  "loomark-preview-scroll",
                  editing.activation.generation,
                  editing.compact,
                  editing.preview,
                )
              PreviewPane =>
                split_scroll_subscription(
                  "loomark-preview-scroll",
                  "loomark-text",
                  editing.activation.generation,
                  editing.compact,
                  editing.preview,
                )
            }
          _ => @sub.none
        },
      ])
    },
  )
  let page = model.map(model => model.page)
  let editor_input = model.map(model => {
    match model.page {
      Editing(editing) =>
        Some({
          activation: editing.activation,
          placeholder: if local_durability(editing, editing.activation.key)
            is Some(NotStarted) {
            Some("Start writing…")
          } else {
            None
          },
          disabled: editing.creation is Creating(_) ||
          model.departure.editor_disabled(),
          read_only: editing.deletion_blocks_document_changes(),
          mode: editing.mode,
          preview: editing.preview,
        })
      Loading(_)
      | PreparingNew(_)
      | NewPreparationFailed(_, _)
      | Recovery(_, _) => None
    }
  })

  fn editor_panels(
    orientation : @rui.SeparatorOrientation,
  ) -> @rabbita.Val[@rabbita.Html] {
    @rui.resizable_panel_group_with_input(
      id="loomark-editor-panels",
      input=editor_input,
      default_size=50,
      min=25,
      max=75,
      orientation~,
      aria_label="Resize editor and preview",
      class="min-h-0 min-w-0 w-full flex-1",
      (scope, input) => {
        match input {
          Some(input) => {
            let split = input.mode == Split
            let text_visible = input.mode != Preview
            let preview_visible = input.mode != Text
            [
              @rui.resizable_panel(
                scope~,
                side=@rui.FirstPanel,
                class="flex min-h-0 min-w-0 overflow-hidden bg-lm-paper",
                attrs=@html.Attrs::build()
                  .id("loomark-text-pane")
                  .hidden(!text_visible)
                  .on_wheel(_ => emit(ScrollClaimed(TextPane)))
                  .on_pointerdown(_ => emit(ScrollClaimed(TextPane)))
                  .on_keydown(_ => emit(ScrollClaimed(TextPane))),
                style=if split {
                  ["overflow:hidden"]
                } else if text_visible {
                  ["display:block;flex:1 1 100%;overflow:hidden"]
                } else {
                  ["display:none;overflow:hidden"]
                },
                text_area_view(
                  emit,
                  editor,
                  input.activation,
                  placeholder?=input.placeholder,
                  disabled=input.disabled,
                  read_only=input.read_only,
                ),
              ),
              @rui.resizable_handle(
                scope~,
                with_handle=true,
                aria_label="Resize editor and preview",
                class="loomark-divider",
                attrs=@html.Attrs::build().hidden(!split),
                style=if split { [] } else { ["display:none"] },
              ),
              @rui.resizable_panel(
                scope~,
                side=@rui.SecondPanel,
                class="flex min-h-0 min-w-0 overflow-hidden bg-lm-paper",
                attrs=@html.Attrs::build()
                  .hidden(!preview_visible)
                  .on_wheel(_ => emit(ScrollClaimed(PreviewPane)))
                  .on_pointerdown(_ => emit(ScrollClaimed(PreviewPane)))
                  .on_keydown(_ => emit(ScrollClaimed(PreviewPane))),
                style=if split {
                  ["overflow:hidden"]
                } else if preview_visible {
                  ["display:block;flex:1 1 100%;overflow:hidden"]
                } else {
                  ["display:none;overflow:hidden"]
                },
                editor.preview_view(input.preview, id="loomark-preview-scroll"),
              ),
            ]
          }
          None => []
        }
      },
    )
  }

  fn wide_editor_panels() -> @rabbita.Val[@rabbita.Html] {
    editor_panels(@rui.Horizontal)
  }

  fn compact_editor_panels() -> @rabbita.Val[@rabbita.Html] {
    editor_panels(@rui.Vertical)
  }

  let compact = page.map(page => {
    match page {
      Loading(compact) => compact
      PreparingNew(preparing) | NewPreparationFailed(preparing, _) =>
        preparing.compact
      Editing(editing) => editing.compact
      Recovery(_, compact) => compact
    }
  })
  let selected_panels = compact.switch_by(
    compact => {
      if compact {
        compact_editor_panels()
      } else {
        wide_editor_panels()
      }
    },
    by=compact => if compact { "compact" } else { "wide" },
  )
  let remote_documents = model.map(model => remote_documents(model.sync()))
  let account = model.map(model => account_status(model.sync()))
  let durability = model.map(document_durability)
  let replica_persistence = model.map(document_replica_persistence)
  let document_sync = model.map(document_sync)
  let document_remote = model.map(document_remote_state)
  let document_activity = model.map(document_sync_activity)
  let selection = model.map(selection_activity)
  let account_view = account.view(account => account_status_view(account, emit))
  let durability_view = durability.view(durability => {
    local_durability_option_view(durability)
  })
  let replica_persistence_view = replica_persistence.view(persistence => {
    replica_persistence_option_view(persistence, emit)
  })
  let document_sync_view = document_sync.view(sync => {
    document_sync_option_view(sync, emit)
  })
  let document_remote_view = document_remote.view(remote => {
    remote_state_option_view(remote, emit)
  })
  let document_activity_view = document_activity.view2(durability, (
    activity,
    durability,
  ) => activity_option_view(activity, durability, emit))
  let selection_view = selection.view(activity => {
    selection_activity_view(activity, emit)
  })
  let sync_status = account_view.view7(
    durability_view, replica_persistence_view, document_sync_view, document_remote_view,
    document_activity_view, selection_view, sync_status_view,
  )
  let sync_attention = document_remote.map3(
    replica_persistence,
    document_activity,
    (remote, persistence, activity) => {
      let attention = match remote {
        Some(@documents.RemoteState::UpdateAvailable(action)) =>
          sync_status_button("Open update", AcceptRemote(action), emit)
        Some(@documents.RemoteState::DeletionAvailable(action)) =>
          sync_status_button(
            "Remove deleted document",
            AcceptRemote(action),
            emit,
          )
        Some(@documents.RemoteState::Diverged) =>
          sync_status_label("Conflicting changes")
        Some(@documents.RemoteState::DeletedRemotely) =>
          sync_status_label("Deletion pending")
        _ =>
          match persistence {
            Some(@replica_persistence.Status::Retryable(action, _)) =>
              sync_status_button("Retry saving", RetrySaving(action), emit)
            _ =>
              match activity {
                Some(@sync.Activity::Retryable(action)) =>
                  sync_status_button("Retry sync", RetrySync(action), emit)
                _ => @html.nothing
              }
          }
      }
      (attention, persistence)
    },
  )
  let membership = page.map(document_membership)
  let remote_seeds = remote_documents.map2(membership, remote_document_seeds)
  let feature_input = page.map2(remote_seeds, (page, remote) => {
    match page {
      Editing(editing) => recent_document_seeds(editing, remote)
      Loading(_)
      | PreparingNew(_)
      | NewPreparationFailed(_, _)
      | Recovery(_, _) => @vector.Vector([])
    }
  })
  let feature_delete_target = page.map(page => {
    match page {
      Editing(editing) =>
        match editing.deletion {
          DeleteConfirmation(id) => Some(id)
          NoDeletion => None
        }
      Loading(_)
      | PreparingNew(_)
      | NewPreparationFailed(_, _)
      | Recovery(_, _) => None
    }
  })
  let sidebar_state = @sidebar.SidebarProviderState::SidebarProviderState(true)
  let recent_feature = @recent_documents.build(
    input=feature_input,
    lifecycle_key=key => key.lifecycle_key(),
    visible=sidebar_state.visible(),
    can_create=model.map(model => {
      match model.page {
        Editing(editing) =>
          editing.can_activate() && !model.departure.editor_disabled()
        _ => false
      }
    }),
    compact~,
    delete_target=feature_delete_target,
    on_intent=@cmd.Emit(intent => {
      match intent {
        Create => emit(CreateRequested)
        Select(id) => emit(DocumentSelected(id))
        RequestDelete(id) => emit(DeleteRequested(id))
        CancelDelete => emit(DeleteCancelled)
        ConfirmDelete(id) => emit(DeleteConfirmed(id))
      }
    }),
    close_after_action=sidebar_state.collapse(),
  )
  let account_input = model.map(account_controls_input)
  let status_views = sync_status.map2(sync_attention, (status, attention) => {
    (status, attention)
  })
  let layout_input = page
    .map5(
      selected_panels,
      status_views,
      recent_feature.dialog(),
      recent_feature.navigation(),
      (page, editor_panels, statuses, dialog, recent_navigation) => {
        (page, editor_panels, statuses, dialog, recent_navigation)
      },
    )
    .map2(account_input, (layout, account) => (layout, account))
  @sidebar.sidebar_provider_with_state(
    state=sidebar_state,
    input=layout_input,
    class="loomark-viewport [--rui-sidebar-width:clamp(11rem,24vw,17rem)] [--rui-sidebar-width-icon:2.75rem] max-[720px]:[--rui-sidebar-width:100vw]",
    (sidebar, layout) => {
      let (
        (
          page,
          editor_panels,
          (sync_status, (sync_attention, persistence)),
          dialog,
          recent_navigation,
        ),
        account,
      ) = layout
      view(
        sidebar, page, account, emit, editor_panels, sync_status, sync_attention,
        persistence, dialog, recent_navigation,
      )
    },
  )
}
