///|
using @html {node, nothing}

///|
fn hidden_trigger(
  dispatch : @rabbita.Emit[Msg],
  msg : Msg,
  id : String,
) -> @rabbita.Html {
  @html.button(
    on_click=dispatch(msg),
    attrs=@html.Attrs::build()
      .class("hidden-trigger")
      .id(id)
      .aria_hidden("true")
      .tabindex(-1),
    [@html.text("")],
  )
}

///|
fn view_editor(dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let attrs = @html.Attrs::build().id("canopy-editor")
  let hidden_attrs = @html.Attrs::build()
    .id("canopy-editor")
    .class("hidden-trigger")
    .aria_hidden("true")
    .tabindex(-1)
  let cm_attrs = @html.Attrs::build().id("canopy-text-editor")
  let hidden_cm_attrs = @html.Attrs::build()
    .id("canopy-text-editor")
    .class("hidden-trigger")
    .aria_hidden("true")
    .tabindex(-1)
  let main_attrs = @html.Attrs::build().role("main").aria_label("Code editor")
  let text_attrs = if model.mode == Text { cm_attrs } else { hidden_cm_attrs }
  let host_attrs = if model.mode == Text { hidden_attrs } else { attrs }
  div(class="editor-wrapper", attrs=main_attrs, [
    div(attrs=text_attrs, nothing),
    node("canopy-editor", host_attrs, [@html.text("")]),
    // Hidden buttons clicked by JS for undo/redo paths not yet moved to DOM
    // custom-event subscriptions.
    // aria-hidden + tabindex=-1 keeps them out of a11y flow.
    hidden_trigger(dispatch, Undo, "canopy-editor-undo-trigger"),
    hidden_trigger(dispatch, Redo, "canopy-editor-redo-trigger"),
  ])
}
