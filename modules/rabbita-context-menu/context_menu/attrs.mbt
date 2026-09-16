///|
fn px(value : Float) -> String {
  value.to_string() + "px"
}

///|
fn bool_attr(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
fn[T] Model::base_trigger_attrs(self : Model[T]) -> @html.Attrs {
  @html.Attrs::build()
  .aria_haspopup("menu")
  .aria_expanded(bool_attr(self.is_open()))
  .aria_controls(self.id)
}

///|
#cfg(target="js")
extern "js" fn mouse_event_client_x(event : @dom.MouseEvent) -> Double = "(event) => event.clientX"

///|
#cfg(target="js")
extern "js" fn mouse_event_client_y(event : @dom.MouseEvent) -> Double = "(event) => event.clientY"

///|
#cfg(target="js")
fn Point::from_mouse_event(event : @dom.MouseEvent) -> Point {
  Point(
    x=Float::from_double(mouse_event_client_x(event)),
    y=Float::from_double(mouse_event_client_y(event)),
  )
}

///|
#cfg(target="js")
pub fn[T] Model::trigger_attrs(
  self : Model[T],
  on_open : (Point) -> @rabbita.Cmd,
) -> @html.Attrs {
  self
  .base_trigger_attrs()
  .on_contextmenu(event => {
    event.prevent_default()
    on_open(Point::from_mouse_event(event))
  })
}

///|
#cfg(not(target="js"))
pub fn[T] Model::trigger_attrs(
  self : Model[T],
  on_open : (Point) -> @rabbita.Cmd,
) -> @html.Attrs {
  ignore(on_open)
  self.base_trigger_attrs()
}

///|
/// Attributes for the context-menu panel.
///
/// The panel is positioned with fixed `left`/`top` styles when the model is
/// open. Consumers may append styling and labeling attributes after this call.
pub fn[T] Model::panel_attrs(
  self : Model[T],
  dispatch : (Msg) -> @rabbita.Cmd,
) -> @html.Attrs {
  match self.state {
    Closed => @html.Attrs::build()
    Open(anchor~, menu~, ..) => {
      let attrs = menu.panel_attrs(menu_msg => {
        dispatch(Msg::from_menu_msg(menu_msg))
      })
      attrs
      .style("position", "fixed")
      .style("left", px(anchor.x))
      .style("top", px(anchor.y))
    }
  }
}

///|
/// Attributes for one context-menu item.
pub fn[T] Model::item_attrs(
  self : Model[T],
  index : Int,
  dispatch : (Msg) -> @rabbita.Cmd,
) -> @html.Attrs {
  match self.state {
    Closed => @html.Attrs::build()
    Open(menu~, ..) =>
      menu.item_attrs(index, menu_msg => dispatch(Msg::from_menu_msg(menu_msg)))
  }
}
