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
  let text_area = @text_area.TextArea::TextArea("loomark-text")
  let preview_engine = @preview.PreviewEngine::PreviewEngine()
  let initial_compact = compact_viewport(@browser.viewport_width())
  let (model, emit) = @rabbita.create_state_with_init(
    init=emit => initial_state(emit, initial_compact),
    update=(model, msg, emit) => {
      update(model, msg, emit, text_area, preview_engine)
    },
    subscriptions=(current, emit) => {
      @sub.batch([
        @sub.on_resize(viewport => emit(ViewportChanged(viewport.width))),
        @sub.on_visibility_change(hidden => emit(VisibilityChanged(hidden))),
        lead_subscriptions(current.page, emit),
      ])
    },
  )
  let page = model.map(model => model.page)
  let editor_input = page.map(page => {
    match page {
      Editing(editing) =>
        Some({
          activation: editing.activation,
          disabled: editing.creation == Creating,
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
                  text_area,
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
                input.preview.view(),
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
  let remote_documents = model.map(model => remote_documents(model.sync))
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
    can_create=page.map(page => {
      match page {
        Editing(editing) => editing.can_activate()
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
  let layout_input = page.map4(
    selected_panels,
    recent_feature.dialog(),
    recent_feature.navigation(),
    (page, editor_panels, dialog, recent_navigation) => {
      (page, editor_panels, dialog, recent_navigation)
    },
  )
  @sidebar.sidebar_provider_with_state(
    state=sidebar_state,
    input=layout_input,
    class="h-dvh min-h-0 [--rui-sidebar-width:clamp(11rem,24vw,17rem)] [--rui-sidebar-width-icon:2.75rem]",
    (sidebar, layout) => {
      let (page, editor_panels, dialog, recent_navigation) = layout
      view(sidebar, page, emit, editor_panels, dialog, recent_navigation)
    },
  )
}
