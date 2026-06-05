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
fn Model::base_trigger_attrs(self : Model) -> @html.Attrs {
  @html.Attrs::build()
  .aria_haspopup("menu")
  .aria_expanded(bool_attr(self.is_open()))
  .aria_controls(self.id)
}

///|
#cfg(target="js")
pub fn Model::trigger_attrs(
  self : Model,
  on_open : (Point) -> @rabbita.Cmd,
) -> @html.Attrs {
  self
  .base_trigger_attrs()
  .on_contextmenu(event => {
    event.prevent_default()
    on_open(
      Point(
        x=Float::from_int(event.get_client_x()),
        y=Float::from_int(event.get_client_y()),
      ),
    )
  })
}

///|
#cfg(not(target="js"))
pub fn Model::trigger_attrs(
  self : Model,
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
pub fn Model::panel_attrs(
  self : Model,
  dispatch : (Msg) -> @rabbita.Cmd,
) -> @html.Attrs {
  let attrs = self.menu.panel_attrs(menu_msg => {
    dispatch(Msg::from_menu_msg(menu_msg))
  })
  match self.anchor {
    Some(point) =>
      attrs
      .style("position", "fixed")
      .style("left", px(point.x))
      .style("top", px(point.y))
    None => attrs
  }
}

///|
/// Attributes for one context-menu item.
pub fn Model::item_attrs(
  self : Model,
  index : Int,
  dispatch : (Msg) -> @rabbita.Cmd,
) -> @html.Attrs {
  self.menu.item_attrs(index, menu_msg => dispatch(Msg::from_menu_msg(menu_msg)))
}
