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
/// The top of the line box holding a glyph whose middle is `middle`, both
/// measured from the top of the text's border box. Glyph boxes sit inside
/// their line by half the leading, and taller fallback glyphs reach out of it,
/// but their middle stays within it.
fn line_box_top(
  middle : Double,
  padding_top : Double,
  line_height : Double,
) -> Double {
  padding_top + ((middle - padding_top) / line_height).floor() * line_height
}

///|
/// The character whose box locates the line of `offset`, and how many lines
/// below that character's line `offset` lies. Line breaks have no box, so an
/// empty line counts from the nearest character before it, or after it at the
/// start of the text. `None` when the text has no characters to measure.
fn line_reference(text : String, offset : Int) -> (Int, Int)? {
  let offset = offset.clamp(min=0, max=text.length())
  fn is_break(index : Int) -> Bool {
    text.code_unit_at(index) == '\n'
  }

  if offset < text.length() && !is_break(offset) {
    return Some((offset, 0))
  }
  let mut lines = 0
  for index = offset - 1; index >= 0; index = index - 1 {
    if !is_break(index) {
      return Some((index, lines))
    }
    lines += 1
  }
  lines = 0
  for index = offset; index < text.length(); index = index + 1 {
    if !is_break(index) {
      return Some((index, -lines))
    }
    lines += 1
  }
  None
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
