///|
/// The viewport top for a line asked to sit at `requested`, moved just enough
/// to lie within the readable area. A line already inside stays put.
fn fitted_top(
  requested : Double,
  line_height : Double,
  readable_top : Double,
  readable_bottom : Double,
) -> Double {
  if requested + line_height > readable_bottom {
    readable_bottom - line_height
  } else if requested < readable_top {
    readable_top
  } else {
    requested
  }
}

///|
/// Numeric sample of the textarea's inner box. It has no live DOM reads;
/// scrolling or resizing requires the shell to take another sample.
priv struct TextViewport {
  top : Double
  height : Double
  scroll_top : Double
  padding_top : Double
  scroll_padding_bottom : Double
}

///|
fn TextViewport::content_origin(self : TextViewport) -> Double {
  self.top - self.scroll_top
}

///|
fn TextViewport::readable(self : TextViewport) -> (Double, Double) {
  (
    self.top + self.padding_top,
    self.top + self.height - self.scroll_padding_bottom,
  )
}

///|
/// Requested movement smaller than half a pixel must not cause a scroll write.
priv enum ScrollAdjustment {
  Keep
  Move(Double)
}

///|
fn scroll_adjustment(delta : Double) -> ScrollAdjustment {
  if delta.abs() >= 0.5 {
    Move(delta)
  } else {
    Keep
  }
}

///|
/// A pane that does not scroll has no end to reach.
fn at_scroll_end(top : Double, height : Double, scroll_height : Double) -> Bool {
  top > 0.0 && top + height >= scroll_height - 0.5
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
/// Keep bottom chrome hidden for visual occlusion or estimated keyboard height.
/// Panning restores no space; tolerate subpixel rounding of browser metrics.
fn bottom_bar_obscured(
  visible_height : Double,
  layout_height : Double,
  baseline_height : Double,
) -> Bool {
  visible_height < layout_height - 1.0 ||
  layout_height < baseline_height - 100.0
}

///|
/// Compute the next window-size-adjusted high-water mark from numeric samples.
/// resizes-content shrinks both viewports, so their difference no longer
/// identifies the keyboard. Width changes reset the estimate rather than
/// guessing across rotation or desktop zoom. The shell retains the samples.
fn viewport_baseline_height(
  previous_height : Double,
  previous_outer_height : Double,
  previous_width : Double,
  layout_height : Double,
  outer_height : Double,
  width : Double,
) -> Double {
  if width != previous_width ||
    outer_height <= 0.0 ||
    previous_outer_height <= 0.0 {
    layout_height
  } else {
    Double::max(
      layout_height,
      previous_height + outer_height - previous_outer_height,
    )
  }
}
