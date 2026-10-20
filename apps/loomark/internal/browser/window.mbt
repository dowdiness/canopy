///|
pub extern "js" fn window_outer_height(window : @dom.Window) -> Double =
  #| window => window.outerHeight

///|
/// Whether another page embeds this one in a frame.
pub extern "js" fn window_is_framed(window : @dom.Window) -> Bool =
  #| window => window.self !== window.top
