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
  let trigger_attrs = @html.Attrs::build()
    .class("hidden-trigger")
    .id("canopy-text-sync-trigger")
    .aria_hidden("true")
    .tabindex(-1)
  let main_attrs = @html.Attrs::build()
    .role("main")
    .aria_label("Code editor")
  div(class="editor-wrapper", attrs=main_attrs, [
    node("canopy-editor", attrs, [@html.text("")]),
    // Hidden button clicked by JS when text-changed fires.
    // aria-hidden + tabindex=-1: invisible to screen readers and keyboard.
    button(
      on_click=dispatch(TextChangedFromEditor),
      attrs=trigger_attrs,
      [@html.text("")],
    ),
  ])
}
