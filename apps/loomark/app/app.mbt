///|
fn delete_dialog(
  model : @rabbita.Val[Model],
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Val[@rabbita.Html] {
  let target = model.map(model => {
    match model {
      Editing(editing) if editing.deletion is DeleteConfirmation(document_id) => {
        let entry_values = recent_entries(editing)
        let entries = entry_values.view()
        match entries.search_by(entry => entry.document_id() == document_id) {
          Some(index) =>
            entries
            .get(index)
            .map(entry => {
              (document_id, document_option_label(entries, index, entry))
            })
          None => None
        }
      }
      Loading(_) | PreparingNew(_, _, _, _) | Editing(_) | Recovery(_, _) =>
        None
    }
  })
  target.switch_by(
    target => {
      match target {
        None => @rabbita.Val::constant(@html.nothing)
        Some((document_id, label)) =>
          @rui.alert_dialog(
            id="loomark-delete-document",
            default_open=true,
            on_open_change=@cmd.Emit(open => {
              if open {
                @cmd.none
              } else {
                emit(DeleteCancelled)
              }
            }),
            scope => {
              @rui.alert_dialog_portal([
                @rui.alert_dialog_content(scope, [
                  @rui.alert_dialog_header([
                    @rui.alert_dialog_title(scope, "Delete \"\{label}\"?"),
                    @rui.alert_dialog_description(
                      scope, "This permanently removes the document from this browser.",
                    ),
                  ]),
                  @rui.alert_dialog_footer([
                    @rui.alert_dialog_cancel(scope, "Cancel"),
                    @rui.alert_dialog_action(
                      scope,
                      on_click=emit(DeleteConfirmed(document_id)),
                      class="[--rui-button-bg:var(--color-lm-danger)] [--rui-button-fg:white]",
                      "Delete document",
                    ),
                  ]),
                ]),
              ])
            },
          )
      }
    },
    by=target => {
      match target {
        Some((document_id, _)) => "confirm-\{document_id}"
        None => "closed"
      }
    },
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
    subscriptions=(_, emit) => {
      @sub.batch([
        @sub.on_resize(viewport => emit(ViewportChanged(viewport.width))),
        @sub.on_visibility_change(hidden => emit(VisibilityChanged(hidden))),
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
                  read_only=deletion_blocks_document_changes(editing),
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
          Loading(_) | PreparingNew(_, _, _, _) | Recovery(_, _) => []
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
      Loading(compact) | PreparingNew(_, _, compact, _) => compact
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
  let dialog = delete_dialog(model, emit)
  let layout_input = model.map3(selected_panels, dialog, (
    model,
    editor_panels,
    dialog,
  ) => (model, editor_panels, dialog))
  @sidebar.sidebar_provider_with_input(
    input=layout_input,
    default_collapsed=initial_compact,
    class="h-dvh min-h-0 [--rui-sidebar-width:clamp(11rem,24vw,17rem)] [--rui-sidebar-width-icon:2.75rem]",
    (sidebar, layout) => {
      let (model, editor_panels, dialog) = layout
      view(sidebar, model, emit, editor_panels, dialog)
    },
  )
}
