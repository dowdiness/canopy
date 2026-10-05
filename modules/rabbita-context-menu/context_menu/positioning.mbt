///|
#cfg(target="js")
fn clamp_panel_coordinate(
  anchor : Double,
  offset : Double,
  panel_extent : Double,
  viewport_extent : Double,
  viewport_margin : Double,
) -> Double {
  let position = anchor + offset
  let extent = if panel_extent.is_nan() || panel_extent.is_inf() {
    0.0
  } else {
    panel_extent
  }
  // Unlike JavaScript Math.min/max, Double::min/max ignore a single NaN.
  // Preserve the existing positioning contract rather than accepting it.
  if position.is_nan() {
    return position
  }
  if viewport_margin.is_nan() {
    return viewport_margin
  }
  let margin = Double::max(0.0, viewport_margin)
  let available = viewport_extent - extent - margin
  if available.is_nan() {
    return available
  }
  Double::min(Double::max(margin, position), Double::max(margin, available))
}

///|
#cfg(target="js")
fn apply_panel_position(
  panel : @dom.Element,
  anchor_x : Double,
  anchor_y : Double,
  offset_x : Double,
  offset_y : Double,
  viewport_margin : Double,
  collision : CollisionStrategy,
) -> Unit {
  let (left, top) = match collision {
    NoCollisionHandling => (anchor_x + offset_x, anchor_y + offset_y)
    ClampToViewport => {
      let rect = panel.get_bounding_client_rect()
      let window = @dom.window()
      (
        clamp_panel_coordinate(
          anchor_x,
          offset_x,
          rect.get_width(),
          window.inner_width(),
          viewport_margin,
        ),
        clamp_panel_coordinate(
          anchor_y,
          offset_y,
          rect.get_height(),
          window.inner_height(),
          viewport_margin,
        ),
      )
    }
  }
  match panel.to_html_element() {
    Some(element) => {
      let style = element.get_style()
      style.set("position", "fixed")
      style.set("left", "\{left}px")
      style.set("top", "\{top}px")
    }
    None => ()
  }
}

///|
/// Position the open panel after render using the supplied strategy.
///
/// `Point` anchors are client/viewport coordinates. The command measures the
/// rendered panel and applies viewport clamping when requested.
#cfg(target="js")
pub fn[T] Model::position_cmd(
  self : Model[T],
  positioning? : Positioning = Positioning::default(),
) -> @rabbita.Cmd {
  match self.anchor() {
    Some(anchor) => {
      let id = self.id
      @cmd.custom_cmd(
        _ => {
          match @dom.document().get_element_by_id(id).to_option() {
            Some(panel) if panel.get_is_connected() =>
              apply_panel_position(
                panel,
                anchor.x.to_double(),
                anchor.y.to_double(),
                positioning.offset_x.to_double(),
                positioning.offset_y.to_double(),
                positioning.viewport_margin.to_double(),
                positioning.collision,
              )
            _ => ()
          }
        },
        kind=@cmd.after_render,
      )
    }
    None => @rabbita.none
  }
}

///|
#cfg(not(target="js"))
pub fn[T] Model::position_cmd(
  self : Model[T],
  positioning? : Positioning = Positioning::default(),
) -> @rabbita.Cmd {
  ignore((self, positioning))
  @rabbita.none
}
