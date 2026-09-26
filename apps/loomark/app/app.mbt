///|
const LEAD_DELAY_MS : Int = 250

///|
fn lead_subscriptions(model : Page, emit : @rabbita.Emit[Msg]) -> @sub.Sub {
  let pending = match model {
    Editing(editing) => editing.documents.pending_edits()
    PreparingNew(preparing) => preparing.documents.pending_edits()
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
  let editor = @editor.MarkdownEditor::MarkdownEditor("loomark-text")
  let initial_compact = compact_viewport(@browser.viewport_width())
  let (model, emit) = @rabbita.create_state_with_init(
    init=emit => initial_state(emit, initial_compact),
    update=(model, msg, emit) => update(model, msg, emit, editor),
    subscriptions=(current, emit) => {
      @sub.batch([
        @sub.on_resize(viewport => emit(ViewportChanged(viewport.width))),
        @sub.on_visibility_change(hidden => emit(VisibilityChanged(hidden))),
        page_restore_subscription(emit(PageRestored)),
        lead_subscriptions(current.page, emit),
      ])
    },
  )
  let page = model.map(model => model.page)
  let editor_input = model.map(model => {
    match model.page {
      Editing(editing) =>
        Some({
          activation: editing.activation,
          disabled: editing.creation is Creating(_) ||
          model.departure.editor_disabled(),
          read_only: editing.deletion_blocks_document_changes(),
          mode: editing.mode,
          preview: editing.preview,
        })
      Loading(_) | PreparingNew(_) | Recovery(_, _) => None
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
                  .hidden(!text_visible),
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
                  disabled=input.disabled,
                  read_only=input.read_only,
                ),
              ),
              @rui.resizable_handle(
                scope~,
                with_handle=true,
                aria_label="Resize editor and preview",
                class="bg-lm-rule data-[orientation=vertical]:!h-auto data-[orientation=vertical]:self-stretch focus-within:bg-lm-accent",
                attrs=@html.Attrs::build().hidden(!split),
                style=if split { [] } else { ["display:none"] },
              ),
              @rui.resizable_panel(
                scope~,
                side=@rui.SecondPanel,
                class="flex min-h-0 min-w-0 overflow-hidden bg-lm-paper",
                attrs=@html.Attrs::build().hidden(!preview_visible),
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
      PreparingNew(preparing) => preparing.compact
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
  let account_view = account.view(account => {
    account_status_section(account, emit)
  })
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
  let document_activity_view = document_activity.view(activity => {
    activity_option_view(activity, emit)
  })
  let selection_view = selection.view(activity => {
    selection_activity_view(activity, emit)
  })
  let sync_status = account_view.view7(
    durability_view, replica_persistence_view, document_sync_view, document_remote_view,
    document_activity_view, selection_view, sync_status_view,
  )
  let membership = page.map(document_membership)
  let remote_seeds = remote_documents.map2(membership, remote_document_seeds)
  let feature_input = page.map2(remote_seeds, (page, remote) => {
    match page {
      Editing(editing) => recent_document_seeds(editing, remote)
      Loading(_) | PreparingNew(_) | Recovery(_, _) => @vector.Vector([])
    }
  })
  let feature_delete_target = page.map(page => {
    match page {
      Editing(editing) =>
        match editing.deletion {
          DeleteConfirmation(id) => Some(id)
          NoDeletion => None
        }
      Loading(_) | PreparingNew(_) | Recovery(_, _) => None
    }
  })
  let sidebar_state = @sidebar.SidebarProviderState::SidebarProviderState(
    initial_compact,
  )
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
  let layout_input = page
    .map5(
      selected_panels,
      sync_status,
      recent_feature.dialog(),
      recent_feature.navigation(),
      (page, editor_panels, sync_status, dialog, recent_navigation) => {
        (page, editor_panels, sync_status, dialog, recent_navigation)
      },
    )
    .map2(account_input, (layout, account) => (layout, account))
  @sidebar.sidebar_provider_with_state(
    state=sidebar_state,
    input=layout_input,
    class="h-dvh min-h-0 [--rui-sidebar-width:clamp(11rem,24vw,17rem)] [--rui-sidebar-width-icon:2.75rem] max-[641px]:[--rui-sidebar-width:100vw]",
    (sidebar, layout) => {
      let (
        (page, editor_panels, sync_status, dialog, recent_navigation),
        account,
      ) = layout
      view(
        sidebar, page, account, emit, editor_panels, sync_status, dialog, recent_navigation,
      )
    },
  )
}
