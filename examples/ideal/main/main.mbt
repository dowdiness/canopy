///|
using @html {button, div, span, text}

///|
using @rabbita {type Cmd, type Dispatch, type Html, none}

///|
let deferred_refresh_ms = 16

///|
fn init_model() -> Model {
  let init_text = "let id = \\x.x in let apply = \\f.\\x.f x in apply id 42"
  let editor = @editor.SyncEditor::new("local")
  editor.set_text(init_text)
  let outline_state = @proj.TreeEditorState::from_projection(
    editor.get_proj_node(),
    editor.get_source_map(),
  )
  {
    editor,
    outline_state,
    mode: Text,
    workspace: {
      outline_visible: false,
      inspector_visible: false,
      bottom_visible: false,
    },
    cursor: None,
    selected_node: None,
    diagnostics_open: false,
    next_timestamp: 1,
    projection_dirty: false,
    refresh_scheduled: false,
    bottom_tab: Problems,
  }
}

///|
fn refresh(model : Model) -> Model {
  let outline_state = model.outline_state.refresh(
    model.editor.get_proj_node(),
    model.editor.get_source_map(),
  )
  { ..model, outline_state, projection_dirty: false, refresh_scheduled: false }
}

///|
fn view_toolbar(dispatch : Dispatch[Msg], model : Model) -> Html {
  div(class="toolbar", [
    span(class="toolbar-title", [text("Canopy Editor")]),
    div(class="toolbar-spacer", [text("")]),
    button(
      class=if model.mode == Text { "tab active" } else { "tab" },
      on_click=dispatch(SetMode(Text)),
      [text("Text")],
    ),
    button(
      class=if model.mode == Structure { "tab active" } else { "tab" },
      on_click=dispatch(SetMode(Structure)),
      [text("Structure")],
    ),
    div(class="toolbar-spacer", [text("")]),
    button(class="toolbar-btn", on_click=dispatch(Undo), [text("Undo")]),
    button(class="toolbar-btn", on_click=dispatch(Redo), [text("Redo")]),
  ])
}

///|
fn update(dispatch : Dispatch[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  match msg {
    SetMode(mode) =>
      // TODO: send mode to Web Component via raw_effect
      (none, { ..model, mode, })
    TogglePanel(panel) => {
      let ws = model.workspace
      let workspace = match panel {
        Outline => { ..ws, outline_visible: !ws.outline_visible }
        Inspector => { ..ws, inspector_visible: !ws.inspector_visible }
        Bottom => { ..ws, bottom_visible: !ws.bottom_visible }
      }
      (none, { ..model, workspace, })
    }
    SelectBottomTab(tab) => (none, { ..model, bottom_tab: tab })
    NodeSelected(node_id) => (none, { ..model, selected_node: Some(node_id) })
    StructuralEditRequested(op~, node_id~) => {
      // TODO: apply tree edit to CRDT, then reconcile
      ignore(op)
      ignore(node_id)
      (none, model)
    }
    RefreshProjection =>
      if model.projection_dirty {
        (none, refresh(model))
      } else {
        (none, { ..model, refresh_scheduled: false })
      }
    Undo => {
      ignore(model.editor.undo())
      let cmd = @rabbita.effect(fn() { js_reconcile_editor() })
      (cmd, refresh(model))
    }
    Redo => {
      ignore(model.editor.redo())
      let cmd = @rabbita.effect(fn() { js_reconcile_editor() })
      (cmd, refresh(model))
    }
    LoadExample(example_text) => {
      model.editor.set_text(example_text)
      let cmd = @rabbita.effect(fn() { js_reconcile_editor() })
      (cmd, refresh(model))
    }
    OutlineNodeClicked(_node_id) =>
      // TODO: send selectedNode to Web Component
      (none, model)
  }
}

///|
fn view(dispatch : Dispatch[Msg], model : Model) -> Html {
  div(class="app-shell", [
    view_toolbar(dispatch, model),
    div(class="workspace", [view_editor(dispatch, model)]),
  ])
}

///|
fn main {
  let app = @rabbita.cell(model=init_model(), update~, view~)
  @rabbita.new(app).mount("app")
}
