///|
using @html {node}

///|
fn view_editor(
  dispatch : @rabbita.Dispatch[Msg],
  _model : Model,
) -> @rabbita.Html {
  let attrs = @html.Attrs::build()
    .class("editor-container")
    .id("canopy-editor")
  div(class="editor-wrapper", [
    node("canopy-editor", attrs, [@html.text("")]),
    // Hidden button clicked by JS when text-changed fires.
    // Works around Rabbita's handler API not exposing Scheduler.add().
    button(
      id="canopy-text-sync-trigger",
      class="hidden-trigger",
      on_click=dispatch(TextChangedFromEditor),
      [@html.text("")],
    ),
  ])
}
