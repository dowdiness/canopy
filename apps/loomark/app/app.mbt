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
      @sub.on_resize(viewport => emit(ViewportChanged(viewport.width)))
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
                if editing.creation == Creating {
                  text_area_view(
                    emit,
                    text_area,
                    editing.activation,
                    disabled=true,
                  )
                } else {
                  text_area_view(emit, text_area, editing.activation)
                },
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
                preview_view(editing.preview),
              ),
            ]
          }
          Loading(_) | Recovery(_, _) => []
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
  let layout_input = model.map2(selected_panels, (model, editor_panels) => {
    (model, editor_panels)
  })
  @rui.sidebar_provider_with_input(
    input=layout_input,
    default_collapsed=initial_compact,
    class="h-dvh min-h-0 [--rui-sidebar-width:clamp(11rem,24vw,17rem)] [--rui-sidebar-width-icon:2.75rem]",
    (sidebar, layout) => {
      let (model, editor_panels) = layout
      view(sidebar, model, emit, editor_panels)
    },
  )
}
