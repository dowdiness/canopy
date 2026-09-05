// Message-family handler functions for update().
// Each handler matches its subset of Msg variants and returns
// Some((Cmd, Model)). Returns None for unmatched variants.

///|
fn sync_after_history_change(model : Model) -> (Cmd, Model) raise {
  let new_model = refresh(model)
  let text = new_model.editor.get_text()
  let cmd = sync_after_local_model_change(new_model, text)
  (cmd, new_model)
}

///|
fn apply_history(
  model : Model,
  direction : HistoryDirection,
) -> (Cmd, Model) raise {
  let changed = match direction {
    UndoHistory => model.editor.undo()
    RedoHistory => model.editor.redo()
  }
  if changed {
    sync_after_history_change(model)
  } else {
    (none, model)
  }
}

///|
fn handle_workspace(
  emit : Emit[Msg],
  msg : Msg,
  model : Model,
) -> (Cmd, Model)? raise {
  let _ = emit
  match msg {
    SetMode(mode) => {
      let mode_str : String = match mode {
        Text => "text"
        Structure => "structure"
      }
      let js_cmd = @rabbita.effect(fn() { js_set_editor_mode(mode_str) })
      let publication_cmd = if mode == Structure && model.mode != Structure {
        publish_proj_node_cmd(model)
      } else {
        none
      }
      let structure_generation = if mode == Structure && model.mode != Structure {
        model.structure_generation + 1
      } else {
        model.structure_generation
      }
      Some(
        (
          @rabbita.batch([js_cmd, publication_cmd]),
          { ..model, mode, structure_generation },
        ),
      )
    }
    TogglePanel(panel) => {
      let ws = model.workspace
      let workspace = match panel {
        Outline => { ..ws, outline_visible: !ws.outline_visible }
        Inspector => { ..ws, inspector_visible: !ws.inspector_visible }
        Bottom => { ..ws, bottom_visible: !ws.bottom_visible }
      }
      let new_model = { ..model, workspace, }
      Some((none, new_model))
    }
    OutlineResize(resize_msg) => {
      let workspace = model.workspace.update_outline_resize(resize_msg)
      Some((none, { ..model, workspace, }))
    }
    DismissPanels => {
      let ws = model.workspace
      let workspace = { ..ws, outline_visible: false, inspector_visible: false }
      Some((none, { ..model, workspace, }))
    }
    SelectBottomTab(tab) => {
      let new_model = { ..model, bottom_tab: tab }
      Some((bottom_tab_focus_cmd(tab), new_model))
    }
    SyncStatusChanged(status) => {
      let sync_status : SyncStatus = match status {
        "connected" => Connected
        "connecting" => Connecting
        "disconnected" => Offline
        "error" => Error
        _ => model.sync_status
      }
      Some((none, { ..model, sync_status, }))
    }
    Undo => Some(apply_history(model, UndoHistory))
    Redo => Some(apply_history(model, RedoHistory))
    _ => None
  }
}

///|
