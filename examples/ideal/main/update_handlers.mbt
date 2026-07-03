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
fn handle_structural(
  emit : Emit[Msg],
  msg : Msg,
  model : Model,
) -> (Cmd, Model)? {
  let _ = emit
  match msg {
    StructuralEditRequested(op~, node_id~) =>
      if op == "" || node_id == "" {
        Some((none, model))
      } else {
        Some(apply_structural_edit_request(model, op, node_id))
      }
    TreeEdited(op) =>
      match op {
        @lambda_edits.Expand(node_id~) => {
          let hydrate_after_expand = can_hydrate_tree_node(model, node_id)
          let outline_state = if hydrate_after_expand {
            model.outline_state.expand_node(
              node_id,
              model.editor.get_proj_node(),
              model.editor.get_source_map(),
            )
          } else {
            model.outline_state.apply_edit(op.to_generic())
          }
          Some((none, { ..model, outline_state, }))
        }
        @lambda_edits.Collapse(..)
        | @lambda_edits.Select(..)
        | @lambda_edits.SelectRange(..) => {
          let outline_state = model.outline_state.apply_edit(op.to_generic())
          Some((none, { ..model, outline_state, }))
        }
        _ => Some((none, model))
      }
    OutlineStructuralEdit(tree_op) =>
      match
        @lambda.apply_lambda_tree_edit(
          model.editor,
          model.companion,
          tree_op,
          js_now_ms(),
        ) {
        Ok(edits) => {
          push_intent(model, tree_op)
          push_patch(model, tree_op, edits)
          let new_model = refresh({
            ..model,
            next_timestamp: model.next_timestamp + 1,
          })
          let (new_selected, outline_state) = match
            new_model.editor
            .get_source_map()
            .innermost_node_at(new_model.editor.get_cursor()) {
            Some(nid) => {
              let os = new_model.outline_state.apply_edit(
                @canopy_core.GenericTreeOp::Select(node_id=nid),
              )
              (Some(node_id_to_string(nid)), os)
            }
            None => (None, new_model.outline_state)
          }
          let highlight_set = match new_selected {
            Some(s) =>
              match parse_node_id(s) {
                Some(nid) =>
                  @scope.compute_highlight_set(nid, new_model.scope_map)
                None => @immut/hashset.new()
              }
            None => @immut/hashset.new()
          }
          let text = new_model.editor.get_text()
          let cmd = sync_after_local_model_change(new_model, text)
          Some(
            (
              cmd,
              {
                ..new_model,
                selected_node: new_selected,
                outline_state,
                highlight_set,
              },
            ),
          )
        }
        Err(_) => Some((none, model))
      }
    _ => None
  }
}

///|
fn handle_outline(emit : Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model)? {
  let _ = emit
  match msg {
    OutlineNodeClicked(node_id) => {
      let cmd = select_editor_node_cmd(model, node_id)
      let highlight_set = match parse_node_id(node_id) {
        Some(nid) => @scope.compute_highlight_set(nid, model.scope_map)
        None => @immut/hashset.new()
      }
      Some((cmd, { ..model, selected_node: Some(node_id), highlight_set }))
    }
    OutlineNavigate(node_id_str) => {
      let new_selected : String? = if node_id_str == "" {
        None
      } else {
        Some(node_id_str)
      }
      let outline_state = match new_selected {
        Some(s) =>
          match parse_node_id(s) {
            Some(nid) =>
              model.outline_state.apply_edit(
                @canopy_core.GenericTreeOp::Select(node_id=nid),
              )
            None => return None
          }
        None => model.outline_state
      }
      let cmd = match new_selected {
        Some(s) =>
          @rabbita.batch([
            select_editor_node_cmd(model, s),
            scroll_selector_after_render(".outline-panel .tree-row.selected"),
          ])
        None => none
      }
      let highlight_set = match new_selected {
        Some(s) =>
          match parse_node_id(s) {
            Some(nid) => @scope.compute_highlight_set(nid, model.scope_map)
            None => @immut/hashset.new()
          }
        None => @immut/hashset.new()
      }
      Some(
        (
          cmd,
          { ..model, selected_node: new_selected, outline_state, highlight_set },
        ),
      )
    }
    // Drag-and-drop
    OutlineDragStart(node_id) =>
      Some((none, { ..model, drag_source: Some(node_id) }))
    OutlineDragOver(target_id, position) =>
      Some(
        (
          none,
          {
            ..model,
            drop_target_id: Some(target_id),
            drop_position: Some(position),
          },
        ),
      )
    OutlineDragLeave =>
      Some((none, { ..model, drop_target_id: None, drop_position: None }))
    OutlineDragEnd =>
      Some(
        (
          none,
          {
            ..model,
            drag_source: None,
            drop_target_id: None,
            drop_position: None,
          },
        ),
      )
    OutlineDrop(target_id, position) => {
      let source = model.drag_source
      let model = {
        ..model,
        drag_source: None,
        drop_target_id: None,
        drop_position: None,
      }
      match source {
        None => Some((none, model))
        Some(source_id) => {
          let tree_op = @lambda_edits.TreeEditOp::Drop(
            source=source_id,
            target=target_id,
            position~,
          )
          match
            @lambda.apply_lambda_tree_edit(
              model.editor,
              model.companion,
              tree_op,
              js_now_ms(),
            ) {
            Ok(edits) => {
              push_intent(model, tree_op)
              push_patch(model, tree_op, edits)
              let new_model = refresh({
                ..model,
                next_timestamp: model.next_timestamp + 1,
              })
              let text = new_model.editor.get_text()
              let cmd = sync_after_local_model_change(new_model, text)
              Some((cmd, new_model))
            }
            Err(_) => Some((none, model))
          }
        }
      }
    }
    _ => None
  }
}

///|
fn handle_overlay(emit : Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model)? {
  match msg {
    OpenActionOverlayFromOutline => {
      let node_id_str = match model.selected_node {
        Some(s) => s
        None => return None
      }
      let rect_json = js_get_outline_selected_rect()
      Some(open_action_overlay(emit, model, node_id_str, rect_json~))
    }
    OpenActionOverlayForNode(node_id_str)
    | LongPressTriggeredForNode(node_id_str) =>
      Some(open_action_overlay_from_event(emit, model, node_id_str))
    ActionOverlay(overlay_event) =>
      Some(handle_overlay_event(model, overlay_event))
    ActionOverlayEffect(output) => Some(handle_overlay_output(model, output))
    _ => None
  }
}

///|
fn handle_file_io(emit : Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model)? {
  let _ = emit
  match msg {
    LoadExample(example_text) => {
      model.editor.set_text_and_record(example_text, js_now_ms())
      let new_model = refresh({
        ..model,
        next_timestamp: model.next_timestamp + 1,
      })
      let text = new_model.editor.get_text()
      let cmd = sync_after_local_model_change(new_model, text)
      Some((cmd, new_model))
    }
    OpenFile =>
      Some((@rabbita.effect(fn() { @ffi.load_file(model.handle) }), model))
    SaveFile =>
      Some(
        (
          @rabbita.effect(fn() { @ffi.save_file(model.handle, "canopy.lambda") }),
          model,
        ),
      )
    FileLoaded(content) => {
      model.editor.set_text_and_record(content, js_now_ms())
      let new_model = refresh({
        ..model,
        next_timestamp: model.next_timestamp + 1,
      })
      let text = new_model.editor.get_text()
      let cmd = sync_after_local_model_change(new_model, text)
      Some((cmd, new_model))
    }
    _ => None
  }
}

///|
fn handle_structure_mode(
  emit : Emit[Msg],
  msg : Msg,
  model : Model,
) -> (Cmd, Model)? {
  let _ = emit
  match msg {
    StructureNodeSelected(node_id) =>
      if node_id == "" {
        Some((none, model))
      } else {
        let highlight_set = match parse_node_id(node_id) {
          Some(nid) => @scope.compute_highlight_set(nid, model.scope_map)
          None => @immut/hashset.new()
        }
        Some((none, { ..model, selected_node: Some(node_id), highlight_set }))
      }
    StructureStructuralEdit(op~, node_id~) =>
      if op == "" || node_id == "" {
        Some((none, model))
      } else {
        let rebuilt = parse_node_id(node_id).bind(nid => {
          @lambda.structural_edit_op_to_tree_edit(op, nid)
        })
        match rebuilt {
          Some(tree_op) => push_intent(model, tree_op)
          None => push_intent_label(model, "\{op}(node=\{node_id})")
        }
        let new_model = refresh({
          ..model,
          next_timestamp: model.next_timestamp + 1,
        })
        Some((sync_after_external_crdt_change(new_model), new_model))
      }
    ExternalCrdtChanged => {
      let new_model = refresh(model)
      Some((sync_after_external_crdt_change(new_model), new_model))
    }
    _ => None
  }
}

///|
fn handle_codemirror(
  emit : Emit[Msg],
  msg : Msg,
  model : Model,
) -> (Cmd, Model)? {
  let _ = emit
  match msg {
    CmMounted => {
      let new_model = { ..model, mounted: true }
      Some((sync_after_external_crdt_change(new_model), new_model))
    }
    CmDocChanged(text) => {
      model.editor.set_text_and_record(text, js_now_ms())
      let new_model = refresh({
        ..model,
        next_timestamp: model.next_timestamp + 1,
      })
      let actual_text = new_model.editor.get_text()
      let sync_cmd = if actual_text != text {
        @cm.set_doc(model.cm_id, actual_text)
      } else {
        none
      }
      let cmd = @rabbita.batch([
        sync_cmd,
        @rabbita.effect(fn() { js_after_local_text_edit() }),
      ])
      Some((cmd, new_model))
    }
    CmSelectionChanged(range) => {
      js_after_cm_selection_changed(range.from, range.to)
      Some((none, model))
    }
    CmFocusChanged(_) => Some((none, model))
    _ => None
  }
}
