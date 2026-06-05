///|
fn open_action_overlay_from_event(
  model : Model,
  node_id_str : String,
) -> (Cmd, Model) {
  let new_model = open_action_overlay(model, node_id_str)
  if new_model.overlay.visible {
    (new_model.overlay.menu.focus_cmd(), new_model)
  } else {
    (none, new_model)
  }
}

///|
fn closed_overlay() -> OverlayState {
  {
    visible: false,
    actions: [],
    node_context: None,
    submenu: None,
    pending_action: None,
    name_value: "",
    name_error: "",
    anchor_top: 0,
    anchor_left: 0,
    menu: @menu.Model::new(id="ideal-action-overlay-menu", item_count=0),
  }
}

///|
/// Parse the bounding rect JSON from js_get_selected_node_rect into (top, left).
fn parse_anchor_rect(json_str : String) -> (Int, Int) {
  let json = @json.parse(json_str) catch { _ => return (0, 0) }
  let (raw_top, raw_left) = match json {
    Json::Object(m) => {
      let top = match m.get("bottom") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      let left = match m.get("left") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      (top, left)
    }
    _ => (0, 0)
  }
  // Clamp to viewport so the overlay doesn't extend offscreen.
  // Estimated panel size: 320px wide, 300px tall (conservative).
  let viewport_json = js_get_viewport_size()
  let vp = @json.parse(viewport_json) catch { _ => return (raw_top, raw_left) }
  match vp {
    Json::Object(m) => {
      let vw = match m.get("width") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 1024
      }
      let vh = match m.get("height") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 768
      }
      let panel_w = 320
      let panel_h = 300
      let clamped_left = if raw_left + panel_w > vw {
        (vw - panel_w - 8).max(8)
      } else {
        raw_left
      }
      let clamped_top = if raw_top + panel_h > vh {
        (vh - panel_h - 8).max(8)
      } else {
        raw_top
      }
      (clamped_top, clamped_left)
    }
    _ => (raw_top, raw_left)
  }
}

///|
/// Open the action overlay for the given node ID string.
fn open_action_overlay(
  model : Model,
  node_id_str : String,
  rect_json? : String = js_get_selected_node_rect(),
) -> Model {
  if node_id_str == "" {
    return model
  }
  let ctx = match
    detect_action_context(model.editor, model.companion, node_id_str) {
    Some(c) => c
    None => return model
  }
  let proj_ctx = to_proj_context(ctx)
  let actions = @lambda_edits.get_actions_for_node(ctx.kind, proj_ctx)
  if actions.is_empty() {
    return model
  }
  let (anchor_top, anchor_left) = parse_anchor_rect(rect_json)
  js_set_overlay_open(true)
  {
    ..model,
    overlay: {
      visible: true,
      actions,
      node_context: Some(ctx),
      submenu: None,
      pending_action: None,
      name_value: "",
      name_error: "",
      anchor_top,
      anchor_left,
      menu: model.overlay.menu.reset(item_count=actions.length()),
    },
  }
}

///|
fn close_action_overlay(model : Model) -> (Cmd, Model) {
  js_set_overlay_open(false)
  (none, { ..model, overlay: closed_overlay() })
}

///|
fn show_name_prompt(
  model : Model,
  action : @lambda_edits.Action,
) -> (Cmd, Model) {
  let overlay = {
    ..model.overlay,
    pending_action: Some(action),
    name_value: "",
    name_error: "",
    menu: model.overlay.menu.reset(item_count=0),
  }
  (focus_selector_after_render(".name-prompt-input"), { ..model, overlay, })
}

///|
fn overlay_context_kind(model : Model) -> @ast.Term {
  match model.overlay.node_context {
    Some(ctx) => ctx.kind
    None => @ast.Term::Unit
  }
}

///|
fn submenu_choices(
  model : Model,
  action : @lambda_edits.Action,
) -> Array[(String, String)] {
  get_submenu_choices(action.id, overlay_context_kind(model))
}

///|
fn open_submenu(
  model : Model,
  action : @lambda_edits.Action,
  item_count : Int,
) -> (Cmd, Model) {
  let overlay = {
    ..model.overlay,
    submenu: Some(action),
    menu: model.overlay.menu.reset(item_count~),
  }
  (overlay.menu.focus_cmd(), { ..model, overlay, })
}

///|
fn reset_main_menu(model : Model) -> Model {
  let overlay = {
    ..model.overlay,
    submenu: None,
    menu: model.overlay.menu.reset(item_count=model.overlay.actions.length()),
  }
  { ..model, overlay, }
}

///|
/// Execute an action: build the tree edit op and apply it.
/// Returns (Cmd, Model) after execution.
fn execute_action(
  model : Model,
  action : @lambda_edits.Action,
  choice : String,
  name : String,
) -> (Cmd, Model) {
  let ctx = match model.overlay.node_context {
    Some(c) => c
    None => return (none, model)
  }
  match build_tree_edit_op(action.id, ctx, choice, name) {
    Ok(Some(op)) =>
      match
        @lambda.apply_lambda_tree_edit(
          model.editor,
          model.companion,
          op,
          js_now_ms(),
        ) {
        Ok(edits) => {
          push_intent(model, op)
          push_patch(model, op, edits)
          js_set_overlay_open(false)
          let new_model = refresh({
            ..model,
            next_timestamp: model.next_timestamp + 1,
            overlay: closed_overlay(),
          })
          let text = new_model.editor.get_text()
          let cmd = sync_after_local_model_change(new_model, text)
          (cmd, new_model)
        }
        Err(err) => {
          let overlay = { ..model.overlay, name_error: err.message() }
          (none, { ..model, overlay, })
        }
      }
    Ok(None) => show_name_prompt(model, action)
    Err(msg) => {
      let overlay = { ..model.overlay, name_error: msg }
      (none, { ..model, overlay, })
    }
  }
}

///|
/// Dispatch an action immediately, open a submenu for choice-based actions,
/// or open the name prompt for input-requiring actions.
fn dispatch_or_prompt(
  model : Model,
  action : @lambda_edits.Action,
) -> (Cmd, Model) {
  if action.needs_input {
    show_name_prompt(model, action)
  } else {
    let choices = submenu_choices(model, action)
    match choices {
      [] => execute_action(model, action, "", "")
      _ => open_submenu(model, action, choices.length())
    }
  }
}

///|
fn execute_submenu_choice(
  model : Model,
  action : @lambda_edits.Action,
  index : Int,
) -> (Cmd, Model)? {
  let choices = submenu_choices(model, action)
  if index >= 0 && index < choices.length() {
    let (_, value) = choices[index]
    Some(execute_action(model, action, value, ""))
  } else {
    None
  }
}

///|
fn close_submenu(model : Model) -> (Cmd, Model) {
  let model = reset_main_menu(model)
  (model.overlay.menu.focus_cmd(), model)
}

///|
fn handle_action_text_key(model : Model, key : String) -> (Cmd, Model) {
  match model.overlay.submenu {
    Some(sub_action) => {
      let idx = @string.parse_int(key) catch { _ => -1 }
      let idx = idx - 1 // "1" → 0, "2" → 1, etc.
      match execute_submenu_choice(model, sub_action, idx) {
        Some(result) => result
        None => close_submenu(model)
      }
    }
    None =>
      // If in name prompt mode, let the view handle input.
      if model.overlay.pending_action is Some(_) {
        (none, model)
      } else {
        // Match mnemonic: find the action whose mnemonic matches the key.
        let matched = model.overlay.actions
          .iter()
          .find_first(fn(a) { a.mnemonic == key })
        match matched {
          Some(action) => dispatch_or_prompt(model, action)
          None => (none, model)
        }
      }
  }
}

///|
fn handle_navigation_menu_msg(
  model : Model,
  menu_msg : @menu.Msg,
) -> (Cmd, Model) {
  let overlay = { ..model.overlay, menu: model.overlay.menu.update(menu_msg) }
  let model = { ..model, overlay, }
  if menu_msg.requests_focus() {
    (model.overlay.menu.focus_cmd(), model)
  } else {
    (none, model)
  }
}

///|
fn handle_action_menu_msg(model : Model, menu_msg : @menu.Msg) -> (Cmd, Model) {
  match menu_msg {
    @menu.Activate(index) =>
      match model.overlay.submenu {
        Some(sub_action) =>
          match execute_submenu_choice(model, sub_action, index) {
            Some(result) => result
            None => (none, model)
          }
        None =>
          if index >= 0 && index < model.overlay.actions.length() {
            dispatch_or_prompt(model, model.overlay.actions[index])
          } else {
            (none, model)
          }
      }
    @menu.Close => close_action_overlay(model)
    @menu.Key(key) => handle_action_text_key(model, key)
    @menu.FocusNext
    | @menu.FocusPrevious
    | @menu.FocusFirst
    | @menu.FocusLast
    | @menu.FocusItem(_) => handle_navigation_menu_msg(model, menu_msg)
  }
}

///|
fn handle_action_key(model : Model, key : String) -> (Cmd, Model) {
  match model.overlay.menu.keydown_msg(key) {
    Some(menu_msg) => handle_action_menu_msg(model, menu_msg)
    None => (none, model)
  }
}
