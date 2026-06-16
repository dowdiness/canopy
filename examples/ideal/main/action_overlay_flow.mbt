///|
pub(all) enum OverlayMsg {
  Menu(@menu.Msg)
  KeyPressed(String)
  NameInput(String)
  NameSubmit
  NameCancel
}

///|
enum OverlayEffect {
  NoOverlayEffect
  FocusMenu
  FocusNamePrompt
  ExecuteAction(@lambda_edits.Action, choice~ : String, name~ : String)
  CloseOverlay
}

///|
struct OverlayUpdate {
  state : OverlayState
  effect : OverlayEffect
}

///|
fn overlay_update(
  state : OverlayState,
  effect : OverlayEffect,
) -> OverlayUpdate {
  { state, effect }
}

///|
fn OverlayState::show_name_prompt(
  self : OverlayState,
  action : @lambda_edits.Action,
) -> OverlayUpdate {
  overlay_update(
    {
      ..self,
      mode: NamePrompt(action, value=""),
      error: "",
      menu: self.menu.reset(item_count=0),
    },
    FocusNamePrompt,
  )
}

///|
fn OverlayState::context_kind(self : OverlayState) -> @ast.Term {
  match self.node_context {
    Some(ctx) => ctx.kind
    None => @ast.Term::Unit
  }
}

///|
fn OverlayState::submenu_choices(
  self : OverlayState,
  action : @lambda_edits.Action,
) -> Array[(String, String)] {
  get_submenu_choices(action.id, self.context_kind())
}

///|
fn OverlayState::open_submenu(
  self : OverlayState,
  action : @lambda_edits.Action,
  item_count : Int,
) -> OverlayUpdate {
  overlay_update(
    {
      ..self,
      mode: Submenu(action),
      // Navigating into a submenu is a fresh attempt — clear any stale error so
      // it doesn't linger across the now-visible (all-mode) error surface.
      error: "",
      menu: self.menu.reset(item_count~),
    },
    FocusMenu,
  )
}

///|
fn OverlayState::reset_main_menu(self : OverlayState) -> OverlayState {
  {
    ..self,
    mode: MainMenu,
    // Returning to the main menu is a fresh attempt — clear any stale error.
    error: "",
    menu: self.menu.reset(item_count=self.actions.length()),
  }
}

///|
fn OverlayState::close_submenu(self : OverlayState) -> OverlayUpdate {
  overlay_update(self.reset_main_menu(), FocusMenu)
}

///|
fn OverlayState::dispatch_or_prompt(
  self : OverlayState,
  action : @lambda_edits.Action,
) -> OverlayUpdate {
  if action.needs_input {
    self.show_name_prompt(action)
  } else {
    let choices = self.submenu_choices(action)
    match choices {
      [] => overlay_update(self, ExecuteAction(action, choice="", name=""))
      _ => self.open_submenu(action, choices.length())
    }
  }
}

///|
fn OverlayState::execute_submenu_choice(
  self : OverlayState,
  action : @lambda_edits.Action,
  index : Int,
) -> OverlayUpdate? {
  let choices = self.submenu_choices(action)
  if index >= 0 && index < choices.length() {
    let (_, value) = choices[index]
    Some(overlay_update(self, ExecuteAction(action, choice=value, name="")))
  } else {
    None
  }
}

///|
fn OverlayState::handle_text_key(
  self : OverlayState,
  key : String,
) -> OverlayUpdate {
  match self.mode {
    Submenu(sub_action) => {
      let parsed = @string.parse_int(key) catch { _ => 0 }
      let idx = parsed - 1 // "1" → 0, "2" → 1, etc.
      match self.execute_submenu_choice(sub_action, idx) {
        Some(result) => result
        None => self.close_submenu()
      }
    }
    // In name prompt mode, let the view handle input.
    NamePrompt(_, ..) => overlay_update(self, NoOverlayEffect)
    MainMenu => {
      // Match mnemonic: find the action whose mnemonic matches the key.
      let matched = self.actions.iter().find_first(fn(a) { a.mnemonic == key })
      match matched {
        Some(action) => self.dispatch_or_prompt(action)
        None => overlay_update(self, NoOverlayEffect)
      }
    }
    Closed => overlay_update(self, NoOverlayEffect)
  }
}

///|
fn OverlayState::handle_menu_msg(
  self : OverlayState,
  menu_msg : @menu.Msg,
) -> OverlayUpdate {
  match menu_msg {
    @menu.Activate(index) =>
      match self.mode {
        Submenu(sub_action) =>
          match self.execute_submenu_choice(sub_action, index) {
            Some(result) => result
            None => overlay_update(self, NoOverlayEffect)
          }
        _ =>
          if index >= 0 && index < self.actions.length() {
            self.dispatch_or_prompt(self.actions[index])
          } else {
            overlay_update(self, NoOverlayEffect)
          }
      }
    @menu.Close => overlay_update(self, CloseOverlay)
    @menu.Key(key) => self.handle_text_key(key)
    @menu.FocusNext
    | @menu.FocusPrevious
    | @menu.FocusFirst
    | @menu.FocusLast
    | @menu.FocusItem(_) => {
      let next = { ..self, menu: self.menu.update(menu_msg) }
      let effect = if menu_msg.requests_focus() {
        FocusMenu
      } else {
        NoOverlayEffect
      }
      overlay_update(next, effect)
    }
  }
}

///|
fn OverlayState::handle_name_input(
  self : OverlayState,
  value : String,
) -> OverlayUpdate {
  match self.mode {
    NamePrompt(action, ..) =>
      overlay_update(
        { ..self, mode: NamePrompt(action, value~), error: "" },
        NoOverlayEffect,
      )
    _ => overlay_update(self, NoOverlayEffect)
  }
}

///|
fn OverlayState::handle_name_submit(self : OverlayState) -> OverlayUpdate {
  match self.mode {
    NamePrompt(action, value~) => {
      let name = value.trim().to_owned()
      if name == "" {
        overlay_update(
          { ..self, error: "Enter a name to continue" },
          NoOverlayEffect,
        )
      } else {
        overlay_update(self, ExecuteAction(action, choice="", name~))
      }
    }
    _ => overlay_update(self, NoOverlayEffect)
  }
}

///|
fn OverlayState::update(self : OverlayState, msg : OverlayMsg) -> OverlayUpdate {
  match msg {
    Menu(menu_msg) => self.handle_menu_msg(menu_msg)
    KeyPressed(key) =>
      if key == "" {
        overlay_update(self, NoOverlayEffect)
      } else {
        match self.menu.keydown_msg(key) {
          Some(menu_msg) => self.handle_menu_msg(menu_msg)
          None => overlay_update(self, NoOverlayEffect)
        }
      }
    NameInput(value) => self.handle_name_input(value)
    NameSubmit => self.handle_name_submit()
    NameCancel => overlay_update(self, CloseOverlay)
  }
}
