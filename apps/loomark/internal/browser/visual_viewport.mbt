///|
pub extern "js" fn visual_viewport_scale(
  viewport : @dom.VisualViewport,
) -> Double =
  #| viewport => viewport.scale
