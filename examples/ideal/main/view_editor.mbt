///|
using @html {node}

///|
fn view_editor(
  dispatch : @rabbita.Dispatch[Msg],
  _model : Model,
) -> @rabbita.Html {
  let attrs = @html.Attrs::build().id("canopy-editor")
  let main_attrs = @html.Attrs::build().role("main").aria_label("Code editor")
  div(class="editor-wrapper", attrs=main_attrs, [
    node("canopy-editor", attrs, [@html.text("")]),
    // Hidden buttons clicked by JS when the Web Component forwards events
    // back into Rabbita. aria-hidden + tabindex=-1 keeps them out of a11y flow.
    @html.button(
      on_click=dispatch(TextChangedFromEditor),
      attrs=@html.Attrs::build()
        .class("hidden-trigger")
        .id("canopy-text-sync-trigger")
        .aria_hidden("true")
        .tabindex(-1),
      [@html.text("")],
    ),
    @html.button(
      on_click=dispatch(NodeSelected("")),
      attrs=@html.Attrs::build()
        .class("hidden-trigger")
        .id("canopy-node-selected-trigger")
        .aria_hidden("true")
        .tabindex(-1),
      [@html.text("")],
    ),
    @html.button(
      on_click=dispatch(StructuralEditRequested(op="", node_id="")),
      attrs=@html.Attrs::build()
        .class("hidden-trigger")
        .id("canopy-structural-edit-trigger")
        .aria_hidden("true")
        .tabindex(-1),
      [@html.text("")],
    ),
    @html.button(
      on_click=dispatch(Undo),
      attrs=@html.Attrs::build()
        .class("hidden-trigger")
        .id("canopy-undo-trigger")
        .aria_hidden("true")
        .tabindex(-1),
      [@html.text("")],
    ),
    @html.button(
      on_click=dispatch(Redo),
      attrs=@html.Attrs::build()
        .class("hidden-trigger")
        .id("canopy-redo-trigger")
        .aria_hidden("true")
        .tabindex(-1),
      [@html.text("")],
    ),
    @html.button(
      on_click=dispatch(SyncStatusChanged("")),
      attrs=@html.Attrs::build()
        .class("hidden-trigger")
        .id("canopy-sync-status-trigger")
        .aria_hidden("true")
        .tabindex(-1),
      [@html.text("")],
    ),
    @html.button(
      on_click=dispatch(OpenActionOverlay),
      attrs=@html.Attrs::build()
        .class("hidden-trigger")
        .id("canopy-action-overlay-trigger")
        .aria_hidden("true")
        .tabindex(-1),
      [@html.text("")],
    ),
    @html.button(
      on_click=dispatch(ActionKeyPressed("")),
      attrs=@html.Attrs::build()
        .class("hidden-trigger")
        .id("canopy-action-key-trigger")
        .aria_hidden("true")
        .tabindex(-1),
      [@html.text("")],
    ),
    @html.button(
      on_click=dispatch(LongPressTriggered),
      attrs=@html.Attrs::build()
        .class("hidden-trigger")
        .id("canopy-long-press-trigger")
        .aria_hidden("true")
        .tabindex(-1),
      [@html.text("")],
    ),
  ])
}
