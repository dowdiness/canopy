///|
fn initial_outline_resize() -> @resizable.Model {
  let (viewport_width, _) = viewport_size()
  let outline_width = if viewport_width <= 1024 { 180 } else { 220 }
  @resizable.Model::new(w=outline_width, h=1, constraints={
    min_w: 160,
    max_w: 360,
    min_h: 1,
    max_h: 1,
  })
}

///|
fn initial_workspace_layout() -> WorkspaceLayout {
  {
    outline_visible: true,
    inspector_visible: true,
    bottom_visible: false,
    outline_resize: initial_outline_resize(),
  }
}

///|
fn WorkspaceLayout::update_outline_resize(
  self : WorkspaceLayout,
  resize_msg : @resizable.Msg,
) -> WorkspaceLayout {
  { ..self, outline_resize: self.outline_resize.update(resize_msg) }
}

///|
fn WorkspaceLayout::outline_width_px(self : WorkspaceLayout) -> String {
  "\{self.outline_resize.width()}px"
}
