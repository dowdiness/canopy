// Message-family handler functions for update().
// Each handler matches its subset of Msg variants and returns
// Some((Cmd, Model)). Returns None for unmatched variants.

///|
fn handle_workspace(
  emit : Emit[Msg],
  msg : Msg,
  model : Model,
) -> (Cmd, Model)? {
  let _ = emit
  match msg {
    SetMode(mode) => {
      let mode_str : String = match mode {
        Text => "text"
        Structure => "structure"
      }
      let js_cmd = @rabbita.effect(fn() { js_set_editor_mode(mode_str) })
      Some((js_cmd, { ..model, mode, }))
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
    Undo => {
      let did_undo = model.editor.undo()
      if did_undo {
        let new_model = refresh(model)
        let text = new_model.editor.get_text()
        let cmd = sync_after_local_model_change(new_model, text)
        Some((cmd, new_model))
      } else {
        Some((none, model))
      }
    }
    Redo => {
      let did_redo = model.editor.redo()
      if did_redo {
        let new_model = refresh(model)
        let text = new_model.editor.get_text()
        let cmd = sync_after_local_model_change(new_model, text)
        Some((cmd, new_model))
      } else {
        Some((none, model))
      }
    }
    _ => None
  }
}

///|
