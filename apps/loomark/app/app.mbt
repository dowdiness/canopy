///|
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
      class="loomark-editor-panels",
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
                class="loomark-pane loomark-text-pane",
                attrs=@html.Attrs::build().hidden(!text_visible),
                style=if split {
                  ["overflow:hidden"]
                } else if text_visible {
                  ["display:block;flex:1 1 100%;overflow:hidden"]
                } else {
                  ["display:none;overflow:hidden"]
                },
                text_area_view(emit, text_area),
              ),
              @rui.resizable_handle(
                scope~,
                with_handle=true,
                aria_label="Resize editor and preview",
                class="loomark-resize-handle",
                attrs=@html.Attrs::build().hidden(!split),
                style=if split { [] } else { ["display:none"] },
              ),
              @rui.resizable_panel(
                scope~,
                side=@rui.SecondPanel,
                class="loomark-pane loomark-preview-pane",
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
  model.view2(selected_panels, (model, editor_panels) => {
    view(model, emit, editor_panels)
  })
}
