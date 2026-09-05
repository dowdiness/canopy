///|
using @html {node, nothing}

///|
fn view_editor(_dispatch : @rabbita.Emit[Msg], model : Model) -> @rabbita.Html {
  // Mount-only selection input; snapshot publications never replay focus.
  let selected_node = model.selected_node.unwrap_or("")
  let attrs = @html.Attrs::build()
    .id("canopy-editor")
    .data_set("selected-node", selected_node)
  let inactive_attrs = @html.Attrs::build()
    .id("canopy-editor")
    .class("inactive-pane")
    .aria_hidden("true")
    .tabindex(-1)
    .data_set("selected-node", selected_node)
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
