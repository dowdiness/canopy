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
/// How the default positioning command handles viewport collision.
pub(all) enum CollisionStrategy {
  NoCollisionHandling
  ClampToViewport
} derive(Eq)

///|
/// Positioning options for `Model::position_cmd`.
pub struct Positioning {
  priv offset_x : Float
  priv offset_y : Float
  priv viewport_margin : Float
  priv collision : CollisionStrategy
} derive(Eq)

///|
/// Create positioning options for a context-menu panel.
pub fn Positioning::Positioning(
  offset_x? : Float = 0.0F,
  offset_y? : Float = 0.0F,
  viewport_margin? : Float = 8.0F,
  collision? : CollisionStrategy = ClampToViewport,
) -> Positioning {
  { offset_x, offset_y, viewport_margin, collision }
}

///|
/// Default positioning: no visual offset and viewport clamping with 8px margin.
pub fn Positioning::default() -> Positioning {
  Positioning()
}

///|
#cfg(target="js")
fn CollisionStrategy::code(self : CollisionStrategy) -> Int {
  match self {
    NoCollisionHandling => 0
    ClampToViewport => 1
  }
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
  priv close_focus_id : String?
}

///|
/// Why a document-level dismissable-layer subscription requested close.
pub(all) enum DismissReason {
  PointerOutside
  EscapeKey
}

///|
/// Context-menu behavior messages emitted by panel, item attrs, and subscriptions.
pub(all) enum Msg {
  FocusNext
  FocusPrevious
  FocusFirst
  FocusLast
  FocusItem(Int)
  Activate(Int)
  Close
  Dismiss(DismissReason)
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
    Close | Dismiss(_) => @menu.Close
    Key(key) => @menu.Key(key)
  }
}

///|
/// Create a closed context-menu model for a stable panel id.
pub fn Model::new(id~ : String) -> Model {
  {
    id,
    menu: @menu.Model::new(id~, item_count=0),
    anchor: None,
    close_focus_id: None,
  }
}

///|
/// Return focus to `id` for close paths where the consumer requests it.
pub fn Model::with_close_focus_id(self : Model, id : String) -> Model {
  { ..self, close_focus_id: Some(id) }
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
/// Navigation messages update roving focus. `Activate`, `Close`, and `Dismiss`
/// close the context menu; consumers should still inspect those messages to
/// perform domain actions or notify their host shell.
pub fn Model::update(self : Model, msg : Msg) -> Model {
  match msg {
    Activate(_) | Close | Dismiss(_) => self.close()
    Key(_) => self
    FocusNext | FocusPrevious | FocusFirst | FocusLast | FocusItem(_) =>
      { ..self, menu: self.menu.update(msg.to_menu_msg()) }
  }
}

///|
/// Whether handling this message should be followed by `Model::focus_cmd()`.
pub fn Msg::requests_focus(self : Msg) -> Bool {
  match self {
    FocusNext | FocusPrevious | FocusFirst | FocusLast => true
    FocusItem(_) | Activate(_) | Close | Dismiss(_) | Key(_) => false
  }
}

///|
/// Whether handling this menu-closing message should restore focus to the
/// configured close-focus origin.
pub fn Msg::requests_close_focus(self : Msg) -> Bool {
  match self {
    Activate(_) | Close | Dismiss(EscapeKey) => true
    FocusNext
    | FocusPrevious
    | FocusFirst
    | FocusLast
    | FocusItem(_)
    | Dismiss(PointerOutside)
    | Key(_) => false
  }
}

///|
/// Focus the active menu item after the current render flush.
pub fn Model::focus_cmd(self : Model) -> @rabbita.Cmd {
  self.menu.focus_cmd()
}

///|
/// Focus the active menu item within a scoped root after the current render flush.
/// This only scopes item focus; positioning and dismissal still expect a
/// document-visible panel id.
pub fn Model::focus_cmd_within(self : Model, root_id~ : String) -> @rabbita.Cmd {
  self.menu.focus_cmd_within(root_id~)
}
