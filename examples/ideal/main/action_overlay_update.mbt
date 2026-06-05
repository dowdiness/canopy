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
