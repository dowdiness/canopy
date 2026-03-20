///|
using @html {node}

///|
fn view_editor(
  dispatch : @rabbita.Dispatch[Msg],
  model : Model,
) -> @rabbita.Html {
  let mode_str = match model.mode {
    Text => "text"
    Structure => "structure"
  }
  let attrs = @html.Attrs::build()
    .class("editor-container")
    .id("canopy-editor")
    .data_set("mode", mode_str)
    .handler("node-selected", fn(event, _scheduler) {
      match event.to_custom_event() {
        Some(ce) => {
          let detail = ce.get_detail()
          let node_id : String = detail.get_with_string("nodeId")
          ignore(dispatch(NodeSelected(node_id)))
        }
        None => ()
      }
    })
    .handler("request-undo", fn(_event, _scheduler) { ignore(dispatch(Undo)) })
    .handler("request-redo", fn(_event, _scheduler) { ignore(dispatch(Redo)) })
  node("canopy-editor", attrs, [@html.text("")])
}
