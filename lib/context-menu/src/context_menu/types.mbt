///|
/// Viewport/client-space anchor for an open context menu.
pub(all) struct Point {
  x : Float
  y : Float
} derive(Eq)

///|
/// Create a context-menu anchor point from client coordinates.
pub fn Point::Point(x~ : Float, y~ : Float) -> Point {
  { x, y }
}

///|
/// Headless context-menu behavior state.
///
/// The consumer owns item data, rendering, and action execution. This model
/// owns open/closed state, the client-space anchor point, and the embedded
/// `@menu.Model` used for ARIA, roving focus, and keyboard behavior.
pub struct Model {
  priv id : String
  priv menu : @menu.Model
  priv anchor : Point?
}

///|
/// Context-menu behavior messages emitted by panel and item attrs.
pub(all) enum Msg {
  FocusNext
  FocusPrevious
  FocusFirst
  FocusLast
  FocusItem(Int)
  Activate(Int)
  Close
  Key(String)
}

///|
fn Msg::from_menu_msg(msg : @menu.Msg) -> Msg {
  match msg {
    @menu.FocusNext => FocusNext
    @menu.FocusPrevious => FocusPrevious
    @menu.FocusFirst => FocusFirst
    @menu.FocusLast => FocusLast
    @menu.FocusItem(index) => FocusItem(index)
    @menu.Activate(index) => Activate(index)
    @menu.Close => Close
    @menu.Key(key) => Key(key)
  }
}

///|
fn Msg::to_menu_msg(self : Msg) -> @menu.Msg {
  match self {
    FocusNext => @menu.FocusNext
    FocusPrevious => @menu.FocusPrevious
    FocusFirst => @menu.FocusFirst
    FocusLast => @menu.FocusLast
    FocusItem(index) => @menu.FocusItem(index)
    Activate(index) => @menu.Activate(index)
    Close => @menu.Close
    Key(key) => @menu.Key(key)
  }
}

///|
/// Create a closed context-menu model for a stable panel id.
pub fn Model::new(id~ : String) -> Model {
  { id, menu: @menu.Model::new(id~, item_count=0), anchor: None }
}

///|
/// Whether the context menu is currently open.
pub fn Model::is_open(self : Model) -> Bool {
  self.anchor is Some(_)
}

///|
/// The current client-space anchor when the context menu is open.
pub fn Model::anchor(self : Model) -> Point? {
  self.anchor
}

///|
/// Open the context menu at `anchor` and reset focus for `item_count` items.
pub fn Model::open(self : Model, anchor~ : Point, item_count~ : Int) -> Model {
  { ..self, anchor: Some(anchor), menu: self.menu.reset(item_count~) }
}

///|
/// Close the context menu and clear menu item focus state.
pub fn Model::close(self : Model) -> Model {
  { ..self, anchor: None, menu: self.menu.reset(item_count=0) }
}

///|
/// Apply one context-menu behavior message.
///
/// Navigation messages update roving focus. `Activate` and `Close` close the
/// context menu; consumers should still inspect those messages to perform
/// domain actions or notify their host shell.
pub fn Model::update(self : Model, msg : Msg) -> Model {
  match msg {
    Activate(_) | Close => self.close()
    Key(_) => self
    FocusNext | FocusPrevious | FocusFirst | FocusLast | FocusItem(_) =>
      { ..self, menu: self.menu.update(msg.to_menu_msg()) }
  }
}

///|
/// Whether handling this message should be followed by `Model::focus_cmd()`.
pub fn Msg::requests_focus(self : Msg) -> Bool {
  self.to_menu_msg().requests_focus()
}

///|
/// Focus the active menu item after the current render flush.
pub fn Model::focus_cmd(self : Model) -> @rabbita.Cmd {
  self.menu.focus_cmd()
}
