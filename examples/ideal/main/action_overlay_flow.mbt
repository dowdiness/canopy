///|
fn show_name_prompt(
  model : Model,
  action : @lambda_edits.Action,
) -> (Cmd, Model) {
  let overlay = {
    ..model.overlay,
    mode: NamePrompt(action, value=""),
    error: "",
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
    mode: Submenu(action),
    // Navigating into a submenu is a fresh attempt — clear any stale error so
    // it doesn't linger across the now-visible (all-mode) error surface.
    error: "",
    menu: model.overlay.menu.reset(item_count~),
  }
  (overlay.menu.focus_cmd(), { ..model, overlay, })
}

///|
fn reset_main_menu(model : Model) -> Model {
  let overlay = {
    ..model.overlay,
    mode: MainMenu,
    // Returning to the main menu is a fresh attempt — clear any stale error.
    error: "",
    menu: model.overlay.menu.reset(item_count=model.overlay.actions.length()),
  }
  { ..model, overlay, }
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
