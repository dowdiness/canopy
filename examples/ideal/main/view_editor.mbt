///|
using @html {node, nothing}

///|
fn view_editor(_dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  let attrs = @html.Attrs::build().id("canopy-editor")
  let inactive_attrs = @html.Attrs::build()
    .id("canopy-editor")
    .class("inactive-pane")
    .aria_hidden("true")
    .tabindex(-1)
  let cm_attrs = @html.Attrs::build().id("canopy-text-editor")
  let inactive_cm_attrs = @html.Attrs::build()
    .id("canopy-text-editor")
    .class("inactive-pane")
    .aria_hidden("true")
    .tabindex(-1)
  let main_attrs = @html.Attrs::build().role("main").aria_label("Code editor")
  let text_attrs = if model.mode == Text { cm_attrs } else { inactive_cm_attrs }
  let host_attrs = if model.mode == Text { inactive_attrs } else { attrs }
  div(class="editor-wrapper", attrs=main_attrs, [
    div(attrs=text_attrs, nothing),
    node("canopy-editor", host_attrs, [@html.text("")]),
  ])
}
