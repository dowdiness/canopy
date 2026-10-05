///|
/// Compute the scroll position from measured geometry without reading live DOM.
/// Preserve the current position when the whole caret line is already visible.
fn caret_scroll_top(
  caret_top : Double,
  line_height : Double,
  scroll_top : Double,
  viewport_height : Double,
  padding_top : Double,
  padding_bottom : Double,
) -> Double {
  let caret_bottom = caret_top + line_height
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

///|
/// Keep the same relative reading position in the other Split pane.
/// No write is needed for non-scrolling panes or a subpixel difference.
fn split_scroll_top(
  source_top : Double,
  source_height : Double,
  source_client_height : Double,
  target_top : Double,
  target_height : Double,
  target_client_height : Double,
) -> Double? {
  let source_distance = source_height - source_client_height
  let target_distance = target_height - target_client_height
  if source_distance > 0.0 && target_distance > 0.0 {
    let next = source_top / source_distance * target_distance
    if (target_top - next).abs() >= 1.0 {
      Some(next)
    } else {
      None
    }
  } else {
    None
  }
}
