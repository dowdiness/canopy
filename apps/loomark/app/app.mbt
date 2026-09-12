///|
const LEAD_DELAY_MS : Int = 250

///|
priv suberror PendingEditSub {
  Apply(String, Int, () -> @rabbita.Cmd)
}

///|
fn start_pending_edit_subscription(
  payload : Error,
  scheduler : &@cmd.Scheduler,
  schedule_timeout : (() -> Unit, Int) -> Int,
  cancel_timeout : (Int) -> Unit,
) -> @sub.RunningSub? {
  guard payload is PendingEditSub::Apply(_, _, command) else { return None }
  let mut tagger = command
  let mut active = true
  let timer = schedule_timeout(
    () => if active { scheduler.add(tagger()) },
    LEAD_DELAY_MS,
  )
  Some({
    unload: _ => {
      active = false
      cancel_timeout(timer)
    },
    update_tagger: next => {
      guard next is PendingEditSub::Apply(_, _, new_emit) else { return }
      tagger = new_emit
    },
  })
}

///|
fn pending_edit_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  let window = @dom.window()
  start_pending_edit_subscription(
    payload,
    scheduler,
    (callback, ms) => window.set_timeout(callback, ms),
    timer => window.clear_timeout(timer),
  )
}

///|
fn lead_subscriptions(model : Model, emit : @rabbita.Emit[Msg]) -> @sub.Sub {
  let records = match model {
    Editing(editing) => editing.documents.records
    PreparingNew(preparing) => preparing.documents.records
    Loading(_) | Recovery(_, _) => []
  }
  @sub.batch(
    records.filter_map(record => {
      match record.edit {
        Waiting(revision) if !delete_is_active(record.delete) =>
          Some(
            @sub.custom_sub(
              "loomark.pending-edit.\{record.document.id()}-\{revision}",
              @sub.Scope::Local,
              PendingEditSub::Apply(record.document.id(), revision, () => {
                emit(ApplyPendingEdit(record.document.id(), revision))
              }),
              pending_edit_sub_loader,
            ),
          )
        _ => None
      }
    }),
  )
}

///|
/// Prototype: manage and switch Loomark documents inside RUI Sidebar.
pub fn app() -> @rabbita.Val[@rabbita.Html] {
  let text_area = @text_area.TextArea::TextArea("loomark-text")
  let preview_engine = @preview.PreviewEngine::PreviewEngine()
  let initial_compact = compact_viewport(@dom.window().inner_width())
  let (model, emit) = @rabbita.create_state_with_init(
    init=emit => initial_state(emit, initial_compact),
    update=(model, msg, emit) => {
      update(model, msg, emit, text_area, preview_engine)
    },
    subscriptions=(current, emit) => {
      @sub.batch([
        @sub.on_resize(viewport => emit(ViewportChanged(viewport.width))),
        @sub.on_visibility_change(hidden => emit(VisibilityChanged(hidden))),
        lead_subscriptions(current, emit),
      ])
    },
  )

  fn editor_panels(
    orientation : @rui.SeparatorOrientation,
  ) -> @rabbita.Val[@rabbita.Html] {
    @rui.resizable_panel_group_with_input(
      id="loomark-editor-panels",
      input=model,
      default_size=50,
      min=25,
      max=75,
      orientation~,
      aria_label="Resize editor and preview",
      class="min-h-0 min-w-0 w-full flex-1",
      (scope, model) => {
        match model {
          Editing(editing) => {
            let split = editing.mode == Split
            let text_visible = editing.mode != Preview
            let preview_visible = editing.mode != Text
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
                  editing.activation,
                  disabled=editing.creation == Creating,
                  read_only=editing.deletion_blocks_document_changes(),
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
                editing.preview.view(),
              ),
            ]
          }
          Loading(_) | PreparingNew(_) | Recovery(_, _) => []
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

  let compact = model.map(model => {
    match model {
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
  let feature_input = model.map(model => {
    match model {
      Editing(editing) => recent_document_seeds(editing)
      Loading(_) | PreparingNew(_) | Recovery(_, _) => @vector.Vector([])
    }
  })
  let feature_delete_target = model.map(model => {
    match model {
      Editing(editing) =>
        match editing.deletion {
          DeleteConfirmation(id) | DeleteDeferred(id) => Some(id)
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
    visible=sidebar_state.visible(),
    can_create=model.map(model => {
      match model {
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
  let layout_input = model.map4(
    selected_panels,
    recent_feature.dialog(),
    recent_feature.navigation(),
    (model, editor_panels, dialog, recent_navigation) => {
      (model, editor_panels, dialog, recent_navigation)
    },
  )
  @sidebar.sidebar_provider_with_state(
    state=sidebar_state,
    input=layout_input,
    class="h-dvh min-h-0 [--rui-sidebar-width:clamp(11rem,24vw,17rem)] [--rui-sidebar-width-icon:2.75rem]",
    (sidebar, layout) => {
      let (model, editor_panels, dialog, recent_navigation) = layout
      view(sidebar, model, emit, editor_panels, dialog, recent_navigation)
    },
  )
}
