///|
#cfg(target="js")
extern "js" fn apply_panel_position(
  id : String,
  anchor_x : Double,
  anchor_y : Double,
  offset_x : Double,
  offset_y : Double,
  viewport_margin : Double,
  collision : Int,
) -> Unit =
  #| (id, anchorX, anchorY, offsetX, offsetY, viewportMargin, collision) => {
  #|   const el = document.getElementById(id);
  #|   if (!el) return;
  #|
  #|   let left = anchorX + offsetX;
  #|   let top = anchorY + offsetY;
  #|
  #|   if (collision === 1) {
  #|     const rect = el.getBoundingClientRect();
  #|     const width = Number.isFinite(rect.width) ? rect.width : 0;
  #|     const height = Number.isFinite(rect.height) ? rect.height : 0;
  #|     const margin = Math.max(0, viewportMargin);
  #|     const maxLeft = Math.max(margin, window.innerWidth - width - margin);
  #|     const maxTop = Math.max(margin, window.innerHeight - height - margin);
  #|     left = Math.min(Math.max(margin, left), maxLeft);
  #|     top = Math.min(Math.max(margin, top), maxTop);
  #|   }
  #|
  #|   el.style.position = "fixed";
  #|   el.style.left = `${left}px`;
  #|   el.style.top = `${top}px`;
  #| }

///|
/// Position the open panel after render using the supplied strategy.
///
/// `Point` anchors are client/viewport coordinates. The command measures the
/// rendered panel and applies viewport clamping when requested.
#cfg(target="js")
pub fn Model::position_cmd(
  self : Model,
  positioning? : Positioning = Positioning::default(),
) -> @rabbita.Cmd {
  match self.anchor {
    Some(anchor) =>
      @cmd.custom_cmd(
        _ => {
          apply_panel_position(
            self.id,
            anchor.x.to_double(),
            anchor.y.to_double(),
            positioning.offset_x.to_double(),
            positioning.offset_y.to_double(),
            positioning.viewport_margin.to_double(),
            positioning.collision.code(),
          )
        },
        kind=@cmd.after_render,
      )
    None => @rabbita.none
  }
}

///|
#cfg(not(target="js"))
pub fn Model::position_cmd(
  self : Model,
  positioning? : Positioning = Positioning::default(),
) -> @rabbita.Cmd {
  ignore((self, positioning))
  @rabbita.none
}
