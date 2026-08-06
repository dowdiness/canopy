///|
const SPLIT_STACK_BREAKPOINT : Int = 640

///|
priv enum SplitPresentation {
  SingleSurface
  SideBySide
  Stacked
} derive(Eq)

///|
impl @rabbita_runtime.Enumerate for SplitPresentation with fn tag(self) {
  match self {
    SingleSurface => "single"
    SideBySide => "side-by-side"
    Stacked => "stacked"
  }
}

///|
fn split_visible(model : DriverModel) -> Bool {
  model.split_preview_open
}

///|
fn compact_split_for_width(width : Int) -> Bool {
  width < SPLIT_STACK_BREAKPOINT
}

///|
fn split_presentation(model : DriverModel) -> SplitPresentation {
  if !split_visible(model) {
    SingleSurface
  } else if model.compact_split {
    Stacked
  } else {
    SideBySide
  }
}

///|
/// Compose the active editing mode without owning document resources.
fn mode_view(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Html {
  if model.state.mode() == @core.Block {
    @html.div(
      style=[
        "width:min(calc(100% - 4rem),46rem);margin-inline:auto;min-width:0;display:flex;flex-direction:column;border-left:1px solid var(--rui-border);border-right:1px solid var(--rui-border)",
      ],
      [
        block_format_toolbar(model, emit),
        @html.div(
          id="loomark-active-view",
          style=[
            "width:100%;min-width:0;flex:1;min-height:0;display:flex;overflow-y:auto",
          ],
          editor_view(model, emit),
        ),
      ],
    )
  } else {
    @html.div(
      id="loomark-active-view",
      style=["width:100%;min-width:0;display:flex"],
      editor_view(model, emit),
    )
  }
}

///|
fn single_view(
  model : @rabbita_runtime.Val[DriverModel],
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Val[@rabbita_runtime.Html] {
  model.view(model => mode_view(model, emit))
}

///|
fn resizable_split_view(
  model : @rabbita_runtime.Val[DriverModel],
  emit : @cmd.Emit[DriverEvent],
  orientation : @rui.SeparatorOrientation,
) -> @rabbita_runtime.Val[@rabbita_runtime.Html] {
  @rui.resizable_panel_group_with_input(
    id="loomark-split",
    input=model,
    default_size=50,
    min=25,
    max=75,
    orientation~,
    aria_label="Resize editor and Preview",
    style=["flex:1;min-width:0;min-height:0"],
    (scope, model) => {
      let editor_pane = if model.state.mode() == @core.Preview {
        @html.div(
          id="loomark-active-view",
          style=["width:100%;min-width:0;display:flex"],
          raw_editor_view(model, emit),
        )
      } else {
        mode_view(model, emit)
      }
      @html.fragment([
        @rui.resizable_panel(
          scope~,
          side=@rui.FirstPanel,
          attrs=@html.Attrs::build().data_set("panel", "editor"),
          style=["display:flex;overflow:auto"],
          editor_pane,
        ),
        @rui.resizable_handle(
          scope~,
          with_handle=true,
          aria_label="Resize editor and Preview",
        ),
        @rui.resizable_panel(
          scope~,
          side=@rui.SecondPanel,
          attrs=@html.Attrs::build().data_set("panel", "preview"),
          style=["display:flex;min-height:0;overflow:hidden"],
          preview_document_view(model),
        ),
      ])
    },
  )
}

///|
fn side_by_side_view(
  model : @rabbita_runtime.Val[DriverModel],
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Val[@rabbita_runtime.Html] {
  resizable_split_view(model, emit, @rui.Horizontal)
}

///|
fn stacked_view(
  model : @rabbita_runtime.Val[DriverModel],
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Val[@rabbita_runtime.Html] {
  resizable_split_view(model, emit, @rui.Vertical)
}

///|
/// Select one bounded workspace component while the shared document model stays
/// live as a separate incremental input to every branch.
fn application_view(
  model : @rabbita_runtime.Val[DriverModel],
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Val[@rabbita_runtime.Html] {
  let presentation = model.map(split_presentation)
  presentation.switch(presentation => {
    match presentation {
      SingleSurface => single_view(model, emit)
      SideBySide => side_by_side_view(model, emit)
      Stacked => stacked_view(model, emit)
    }
  })
}
