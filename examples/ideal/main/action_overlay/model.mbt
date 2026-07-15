///|
pub(all) enum OverlayMode {
  MainMenu
  Submenu(@lambda_edits.Action)
  NamePrompt(@lambda_edits.Action, value~ : String)
}

///|
pub struct OverlayState {
  priv mode : OverlayMode
  priv actions : Array[@lambda_edits.Action]
  priv kind : @ast.Term
  priv error : OverlayError?
  priv anchor_top : Int
  priv anchor_left : Int
  priv menu : @menu.Model
}

///|
pub fn OverlayState::OverlayState(
  mode~ : OverlayMode,
  actions~ : Array[@lambda_edits.Action],
  kind~ : @ast.Term,
  error~ : OverlayError?,
  anchor_top~ : Int,
  anchor_left~ : Int,
  menu~ : @menu.Model,
) -> OverlayState {
  { mode, actions: actions.copy(), kind, error, anchor_top, anchor_left, menu }
}

///|
pub fn OverlayState::overlay_mode(self : OverlayState) -> OverlayMode {
  self.mode
}

///|
pub fn OverlayState::overlay_actions(
  self : OverlayState,
) -> Array[@lambda_edits.Action] {
  self.actions.copy()
}

///|
pub fn OverlayState::overlay_kind(self : OverlayState) -> @ast.Term {
  self.kind
}

///|
pub fn OverlayState::overlay_error(self : OverlayState) -> OverlayError? {
  self.error
}

///|
pub fn OverlayState::anchor_top_px(self : OverlayState) -> Int {
  self.anchor_top
}

///|
pub fn OverlayState::anchor_left_px(self : OverlayState) -> Int {
  self.anchor_left
}

///|
pub fn OverlayState::menu_model(self : OverlayState) -> @menu.Model {
  self.menu
}

///|
pub fn OverlayState::with_error(
  self : OverlayState,
  error : OverlayError?,
) -> OverlayState {
  { ..self, error, }
}

///|
pub fn OverlayState::is_open(self : OverlayState) -> Bool {
  match self.mode {
    MainMenu | Submenu(_) | NamePrompt(_, ..) => true
  }
}
