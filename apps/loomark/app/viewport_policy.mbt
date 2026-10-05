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
/// Remove pinch scaling, not keyboard occlusion, from the available height.
fn viewport_layout_height(visible_height : Double, scale : Double) -> Double {
  visible_height * scale
}

///|
/// Follow normal viewport pans, but leave zoom panning browser-owned.
/// A recovered height must not retain an offset beyond the layout bottom.
fn viewport_layout_top(
  visible_top : Double,
  scale : Double,
  previous_top : Double,
  layout_height : Double,
  height : Double,
) -> Double {
  if (scale - 1.0).abs() < 0.01 {
    visible_top
  } else {
    let available_top = if height < layout_height {
      layout_height - height
    } else {
      0.0
    }
    previous_top.clamp(min=0.0, max=available_top)
  }
}

///|
/// Keep bottom chrome hidden while the visible height is reduced.
/// Panning restores no space; tolerate subpixel rounding of browser metrics.
fn bottom_bar_obscured(visible_height : Double, layout_height : Double) -> Bool {
  visible_height < layout_height - 1.0
}

///|
/// resizes-content shrinks both viewports, so their difference no longer
/// identifies the keyboard. Keep a window-size-adjusted high-water mark.
/// This is a heuristic: width changes reset it rather than guessing across
/// rotation or desktop zoom, and small browser-toolbar changes are ignored.
priv struct ViewportBaseline {
  mut height : Double
  mut outer_height : Double
  mut width : Double
}

///|
fn ViewportBaseline::update(
  self : ViewportBaseline,
  layout_height : Double,
  outer_height : Double,
  width : Double,
) -> Bool {
  if width != self.width || outer_height <= 0.0 || self.outer_height <= 0.0 {
    self.height = layout_height
  } else {
    self.height = Double::max(
      layout_height,
      self.height + outer_height - self.outer_height,
    )
  }
  self.outer_height = outer_height
  self.width = width
  // A visibility threshold, never a correction to the editor's actual height.
  layout_height < self.height - 100.0
}
