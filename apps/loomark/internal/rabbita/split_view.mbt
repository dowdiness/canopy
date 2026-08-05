///|
fn split_visible(model : DriverModel) -> Bool {
  model.split_preview_open && model.state.mode() != @core.Preview
}

///|
/// Rebuild the opaque resizable model against the measured group width. The
/// editor Pane may occupy at most half so its flexible Preview peer remains
/// visible, and the ARIA value always equals rendered geometry.
fn SplitResizeState::fit_group(
  self : SplitResizeState,
  group_width : Int,
) -> SplitResizeState {
  let max_width = (group_width / 2).clamp(min=1, max=640)
  let min_width = if max_width < 160 { max_width } else { 160 }
  {
    model: @resizable.Model::new(w=self.model.width(), h=1, constraints={
      min_w: min_width,
      max_w: max_width,
      min_h: 1,
      max_h: 1,
    }),
  }
}

///|
/// Measure only after Rabbita has rendered the group; DOM access remains in
/// the imperative shell and returns the owning width as a typed event.
fn split_measure_command(emit : @cmd.Emit[DriverEvent]) -> @cmd.Cmd {
  after_render(
    scheduler => {
      let measurement = @dom_boundary.measure_element_id("loomark-split")
      scheduler.add(emit(SplitMeasured(measurement.offset_width().to_int())))
    },
    emit,
  )
}

///|
/// Compose the active editing mode without owning document resources.
fn mode_surface(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Html {
  if model.state.mode() == @core.Block {
    @html.div(
      style=["width:100%;min-width:0;display:flex;flex-direction:column"],
      [
        block_format_toolbar(model, emit),
        @html.div(
          id="loomark-surface",
          style=["width:100%;min-width:0;display:flex"],
          editor_surface(model, emit),
        ),
      ],
    )
  } else {
    @html.div(
      id="loomark-surface",
      style=["width:100%;min-width:0;display:flex"],
      editor_surface(model, emit),
    )
  }
}

///|
/// Render the fixed two-surface workspace. Both surfaces observe the same
/// accepted document held by `DriverModel`.
fn application_surface(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Html {
  if split_visible(model) {
    let editor_width = model.split_resize.model.width()
    let handle_attrs = model.split_resize.model
      .handle_attrs(@resizable.East, message => emit(SplitResize(message)))
      .aria_label("Resize editor and Preview")
      .data_set("slot", "resizable-handle")
      .data_set("orientation", "horizontal")
    @html.div(
      id="loomark-split",
      attrs=@html.Attrs::build()
        .data_set("slot", "resizable-panel-group")
        .data_set("orientation", "horizontal"),
      style=["width:100%;min-width:0;display:flex;overflow:hidden"],
      [
        @html.div(
          attrs=@html.Attrs::build()
            .data_set("slot", "resizable-panel")
            .data_set("panel", "editor"),
          style=[
            "width:\{editor_width}px;min-width:0;display:flex;flex:0 0 auto",
          ],
          mode_surface(model, emit),
        ),
        @html.div(
          id="loomark-split-handle",
          attrs=handle_attrs,
          style=[
            "width:1px;flex:0 0 1px;background:var(--rui-border);outline-offset:3px;cursor:col-resize",
          ],
          @html.nothing,
        ),
        @html.div(
          attrs=@html.Attrs::build()
            .data_set("slot", "resizable-panel")
            .data_set("panel", "preview"),
          style=["min-width:0;flex:1;overflow:auto;padding:1rem;border-left:0"],
          preview_document_surface(model),
        ),
      ],
    )
  } else {
    mode_surface(model, emit)
  }
}
