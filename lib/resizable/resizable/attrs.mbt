///|
#cfg(target="js")
let keyboard_step : Int = 8

///|
fn px(value : Int) -> String {
  "\{value}px"
}

///|
fn Edge::cursor(self : Edge) -> String {
  match self {
    East => "ew-resize"
    South => "ns-resize"
    SouthEast => "nwse-resize"
  }
}

///|
fn Edge::aria_label(self : Edge) -> String {
  match self {
    East => "Resize width"
    South => "Resize height"
    SouthEast => "Resize width and height"
  }
}

///|
fn Edge::value_min(self : Edge, constraints : Constraints) -> Int {
  match self {
    South => constraints.min_h
    East | SouthEast => constraints.min_w
  }
}

///|
fn Edge::value_max(self : Edge, constraints : Constraints) -> Int {
  match self {
    South => constraints.max_h
    East | SouthEast => constraints.max_w
  }
}

///|
fn Edge::value_now(self : Edge, model : Model) -> Int {
  match self {
    South => model.h
    East | SouthEast => model.w
  }
}

///|
fn Edge::value_text(self : Edge, model : Model) -> String {
  match self {
    East => "width \{model.w}px"
    South => "height \{model.h}px"
    SouthEast => "width \{model.w}px, height \{model.h}px"
  }
}

///|
fn Edge::orientation(self : Edge) -> String? {
  match self {
    East => Some("vertical")
    South => Some("horizontal")
    SouthEast => None
  }
}

///|
#cfg(target="js")
fn Edge::keydown_nudge(self : Edge, key : String) -> Msg? {
  match (self, key) {
    (East | SouthEast, "ArrowRight") => Some(NudgeBy(dw=keyboard_step, dh=0))
    (East | SouthEast, "ArrowLeft") => Some(NudgeBy(dw=-keyboard_step, dh=0))
    (South | SouthEast, "ArrowDown") => Some(NudgeBy(dw=0, dh=keyboard_step))
    (South | SouthEast, "ArrowUp") => Some(NudgeBy(dw=0, dh=-keyboard_step))
    _ => None
  }
}

///|
fn with_orientation(attrs : @html.Attrs, edge : Edge) -> @html.Attrs {
  match edge.orientation() {
    Some(value) => attrs.aria_orientation(value)
    None => attrs
  }
}

///|
fn Model::value_attrs(
  self : Model,
  attrs : @html.Attrs,
  edge : Edge,
) -> @html.Attrs {
  attrs
  .aria_valuemin(edge.value_min(self.constraints).to_string())
  .aria_valuemax(edge.value_max(self.constraints).to_string())
  .aria_valuenow(edge.value_now(self).to_string())
  .aria_valuetext(edge.value_text(self))
}

///|
fn Model::base_handle_attrs(self : Model, edge : Edge) -> @html.Attrs {
  let attrs = @html.Attrs::build()
    .role("separator")
    .tabindex(0)
    .aria_label(edge.aria_label())
    .style("cursor", edge.cursor())
  self.value_attrs(with_orientation(attrs, edge), edge)
}

///|
pub fn Model::container_attrs(self : Model) -> @html.Attrs {
  let attrs = @html.Attrs::build()
    .style("width", px(self.w))
    .style("height", px(self.h))
  if self.is_resizing() {
    attrs.style("user-select", "none")
  } else {
    attrs
  }
}

///|
#cfg(target="js")
pub fn Model::handle_attrs(
  self : Model,
  edge : Edge,
  dispatch : (Msg) -> @rabbita.Cmd,
) -> @html.Attrs {
  self
  .base_handle_attrs(edge)
  .on_mousedown(event => {
    event.prevent_default()
    dispatch(StartResize(edge~, x=event.get_client_x(), y=event.get_client_y()))
  })
  .on_keydown(event => {
    match edge.keydown_nudge(event.key()) {
      Some(msg) => {
        event.prevent_default()
        dispatch(msg)
      }
      None => @rabbita.none
    }
  })
}

///|
#cfg(not(target="js"))
pub fn Model::handle_attrs(
  self : Model,
  edge : Edge,
  dispatch : (Msg) -> @rabbita.Cmd,
) -> @html.Attrs {
  ignore(dispatch)
  self.base_handle_attrs(edge)
}
