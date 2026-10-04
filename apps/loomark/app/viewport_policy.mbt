///|
/// Compute the scroll position from measured geometry without reading live DOM.
/// Preserve the current position when the whole caret line is already visible.
fn caret_scroll_top(
  caret_top : Double,
  caret_bottom : Double,
  scroll_top : Double,
  viewport_height : Double,
  padding_top : Double,
  padding_bottom : Double,
) -> Double {
  if caret_bottom > scroll_top + viewport_height - padding_bottom {
    caret_bottom - viewport_height + padding_bottom
  } else if caret_top < scroll_top + padding_top {
    caret_top - padding_top
  } else {
    scroll_top
  }
}

///|
/// Keyboard resizing follows the visible viewport; pinch zoom remains native.
fn follows_visual_viewport(scale : Double) -> Bool {
  (scale - 1.0).abs() < 0.01
}

///|
/// Hide bottom chrome when the visible viewport no longer reaches the layout
/// bottom. Account for panning; tolerate subpixel rounding of browser metrics.
fn bottom_bar_obscured(
  visible_height : Double,
  visible_top : Double,
  layout_height : Double,
) -> Bool {
  visible_top + visible_height < layout_height - 1.0
}
