///|
pub fn viewport_width() -> Double {
  @dom.window().inner_width()
}

///|
pub extern "js" fn window_outer_height(window : @dom.Window) -> Double =
  #| window => window.outerHeight
