///|
/// Viewport/client-space anchor for an open context menu.
pub(all) struct Point {
  x : Float
  y : Float
} derive(Eq)

///|
/// Create a context-menu anchor point from client coordinates.
pub fn Point::Point(x~ : Float, y~ : Float) -> Point {
  { x, y, }
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
  { offset_x, offset_y, viewport_margin, collision, }
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
/// The model owns the copied items while open, the client-space anchor, and
/// the embedded `@menu.Model` used for ARIA, roving focus, and keyboard
/// behavior. Closed models retain none of those open-only values.
priv enum ModelState[T] {
  Closed
  Open(anchor~ : Point, items~ : Array[T], menu~ : @menu.Model)
} derive(Eq)

///|
pub struct Model[T] {
  priv id : String
  priv state : ModelState[T]
  priv close_focus_id : String?
} derive(Eq)

///|
pub(all) enum DismissReason {
  PointerOutside
  EscapeKey
}

///|
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
///
/// Supply a type annotation when no subsequent `open` call constrains `T`.
pub fn[T] Model::new(id~ : String) -> Model[T] {
  { id, state: Closed, close_focus_id: None, }
}

///|
pub fn[T] Model::with_close_focus_id(self : Model[T], id : String) -> Model[T] {
  { ..self, close_focus_id: Some(id), }
}

///|
/// Whether the context menu is currently open.
pub fn[T] Model::is_open(self : Model[T]) -> Bool {
  self.state is Open(..)
}

///|
/// The current client-space anchor when the context menu is open.
/// Closed models intentionally expose no anchor.
pub fn[T] Model::anchor(self : Model[T]) -> Point? {
  match self.state {
    Closed => None
    Open(anchor~, ..) => Some(anchor)
  }
}

///|
/// Read-only view of the items owned by the open context menu.
/// The view cannot mutate the model's private owned array.
pub fn[T] Model::items(self : Model[T]) -> ArrayView[T] {
  match self.state {
    Closed => ([] : Array[T])[:]
    Open(items~, ..) => items[:]
  }
}

///|
/// Resolve a raw UI index against the currently owned items.
/// Invalid indices and closed models return `None`.
pub fn[T] Model::item(self : Model[T], index : Int) -> T? {
  match self.state {
    Closed => None
    Open(items~, ..) => items.get(index)
  }
}

///|
/// Open the context menu at `anchor`, copying `items` into private storage.
/// Focus starts at the first item when the supplied view is non-empty.
pub fn[T] Model::open(
  self : Model[T],
  anchor~ : Point,
  items~ : ArrayView[T],
) -> Model[T] {
  let owned_items = items.to_owned()
  {
    ..self,
    state: Open(
      anchor~,
      items=owned_items,
      menu=@menu.Model::new(id=self.id, item_count=owned_items.length()),
    ),
  }
}

///|
/// Close the context menu, discarding its items, anchor, and focus state.
pub fn[T] Model::close(self : Model[T]) -> Model[T] {
  { ..self, state: Closed, }
}

///|
pub fn[T] Model::update(self : Model[T], msg : Msg) -> Model[T] {
  match msg {
    Activate(_) | Close | Dismiss(_) => self.close()
    Key(_) => self
    FocusNext | FocusPrevious | FocusFirst | FocusLast | FocusItem(_) =>
      match self.state {
        Closed => self
        Open(anchor~, items~, menu~) =>
          {
            ..self,
            state: Open(anchor~, items~, menu=menu.update(msg.to_menu_msg())),
          }
      }
  }
}

///|
pub fn Msg::requests_focus(self : Msg) -> Bool {
  match self {
    FocusNext | FocusPrevious | FocusFirst | FocusLast => true
    FocusItem(_) | Activate(_) | Close | Dismiss(_) | Key(_) => false
  }
}

///|
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
pub fn[T] Model::focus_cmd(self : Model[T]) -> @rabbita.Cmd {
  match self.state {
    Closed => @rabbita.none
    Open(menu~, ..) => menu.focus_cmd()
  }
}

///|
pub fn[T] Model::focus_cmd_within(
  self : Model[T],
  root_id~ : String,
) -> @rabbita.Cmd {
  match self.state {
    Closed => @rabbita.none
    Open(menu~, ..) => menu.focus_cmd_within(root_id~)
  }
}
