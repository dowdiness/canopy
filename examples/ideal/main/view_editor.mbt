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
  if model.use_cm_binding {
    let text_attrs = if model.mode == Text { cm_attrs } else { hidden_cm_attrs }
    let host_attrs = if model.mode == Text { hidden_attrs } else { attrs }
    div(class="editor-wrapper", attrs=main_attrs, [
      div(attrs=text_attrs, nothing),
      node("canopy-editor", host_attrs, [@html.text("")]),
      // Hidden buttons clicked by JS for non-text-mode paths.
      // aria-hidden + tabindex=-1 keeps them out of a11y flow.
      hidden_trigger(
        dispatch,
        SyncStatusChanged(""),
        "canopy-sync-status-trigger",
      ),
      hidden_trigger(
        dispatch,
        OpenActionOverlay,
        "canopy-action-overlay-trigger",
      ),
      hidden_trigger(
        dispatch,
        ActionKeyPressed(""),
        "canopy-action-key-trigger",
      ),
      hidden_trigger(dispatch, LongPressTriggered, "canopy-long-press-trigger"),
      hidden_trigger(dispatch, EditorTextChanged, "canopy-editor-text-changed"),
      hidden_trigger(
        dispatch,
        EditorNodeSelected(""),
        "canopy-editor-node-selected",
      ),
      hidden_trigger(
        dispatch,
        EditorStructuralEdit(op="", node_id=""),
        "canopy-editor-structural-edit",
      ),
    ])
  } else {
    div(class="editor-wrapper", attrs=main_attrs, [
      node("canopy-editor", attrs, [@html.text("")]),
      // Hidden buttons clicked by JS when the Web Component forwards events
      // back into Rabbita. aria-hidden + tabindex=-1 keeps them out of a11y flow.
      hidden_trigger(
        dispatch,
        SyncStatusChanged(""),
        "canopy-sync-status-trigger",
      ),
      hidden_trigger(
        dispatch,
        OpenActionOverlay,
        "canopy-action-overlay-trigger",
      ),
      hidden_trigger(
        dispatch,
        ActionKeyPressed(""),
        "canopy-action-key-trigger",
      ),
      hidden_trigger(dispatch, LongPressTriggered, "canopy-long-press-trigger"),
      // Protocol-based triggers (Phase 4) — replacing global-state bridge
      hidden_trigger(dispatch, EditorTextChanged, "canopy-editor-text-changed"),
      hidden_trigger(
        dispatch,
        EditorNodeSelected(""),
        "canopy-editor-node-selected",
      ),
      hidden_trigger(
        dispatch,
        EditorStructuralEdit(op="", node_id=""),
        "canopy-editor-structural-edit",
      ),
    ])
  }
}
