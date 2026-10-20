///|
priv struct CaretMeasurement {
  source : @text_lines.TextLines
  measured : @writing_focus.MeasuredCaret
}

///|
priv struct FocusMeasurement {
  source : @text_lines.TextLines
  lines : @writing_focus.LineRange
  range : @writing_focus.Range
}

///|
/// Feature-owned caches only. The measuring surface and its lifetime belong
/// to text_layout; Markdown groups are built only when dimming needs them.
priv struct WritingMeasurement {
  mut source : @text_lines.TextLines?
  mut reflow_revision : Int?
  mut groups : @writing_focus.WritingGroups?
  mut focus : FocusMeasurement?
  mut caret : CaretMeasurement?
}

///|
fn WritingMeasurement::WritingMeasurement() -> WritingMeasurement {
  {
    source: None,
    reflow_revision: None,
    groups: None,
    focus: None,
    caret: None,
  }
}

///|
fn WritingMeasurement::measure(
  self : WritingMeasurement,
  area : @dom.HTMLTextAreaElement,
  layer : @dom.HTMLElement,
) -> (@text_layout.MeasuredText, Bool) {
  let measured = @text_layout.measure(area)
  let text_changed = match self.source {
    Some(source) => !physical_equal(source, measured.source)
    None => true
  }
  let reflowed = match self.reflow_revision {
    Some(revision) => revision != measured.reflow_revision
    None => true
  }
  if text_changed {
    self.groups = None
  }
  if reflowed {
    self.focus = None
    self.caret = None
  }
  self.source = Some(measured.source)
  self.reflow_revision = Some(measured.reflow_revision)
  let style = layer.get_style()
  style.set_property(
    "--loomark-text-line-height",
    "\{measured.metrics.line_height}px",
  )
  style.set_property(
    "left",
    "\{area.get_offset_left() + measured.metrics.padding_left}px",
  )
  style.set_property("width", "\{measured.metrics.content_width}px")
  (measured, text_changed || reflowed)
}

///|
fn WritingMeasurement::locate_focus(
  self : WritingMeasurement,
  area : @dom.HTMLTextAreaElement,
  measured : @text_layout.MeasuredText,
  selection_start : Int,
  selection_end : Int,
) -> @writing_focus.Range raise {
  let source = measured.source
  let groups = match self.groups {
    Some(groups) => groups
    None => {
      let groups = @writing_focus.WritingGroups(source)
      self.groups = Some(groups)
      groups
    }
  }
  let lines = groups.focus_lines(selection_start, selection_end)
  match self.focus {
    Some(focus) if physical_equal(focus.source, source) &&
      focus.lines.first == lines.first &&
      focus.lines.last == lines.last => focus.range
    _ => {
      let (top, bottom) = @text_layout.measure_line_bounds(
        area,
        lines.first,
        lines.last,
      )
      let range = groups.focus_range(lines, top~, bottom~)
      self.focus = Some({ source, lines, range, })
      range
    }
  }
}

///|
fn WritingMeasurement::locate_caret(
  self : WritingMeasurement,
  area : @dom.HTMLTextAreaElement,
  measured_text : @text_layout.MeasuredText,
  offset : Int,
) -> (@writing_focus.MeasuredCaret, @writing_focus.CaretCause) raise {
  let source = measured_text.source
  let history : @writing_focus.CaretHistory = match self.caret {
    None => Unmeasured
    Some(caret) if physical_equal(caret.source, source) =>
      SameText(caret.measured)
    Some(_) => OtherText
  }
  let cause = match @writing_focus.caret_measure(history, offset) {
    Cached(measured) => return (measured, Navigation)
    Measure(cause) => cause
  }
  let position = @text_layout.measure_caret(area, offset)
  let measured : @writing_focus.MeasuredCaret = {
    offset,
    x: @writing_focus.drawn_caret_x(
      position.x - measured_text.metrics.padding_left,
      layer_width=measured_text.metrics.content_width,
      half_width=CARET_WIDTH / 2.0,
    ),
    y: position.y,
  }
  self.caret = Some({ source, measured, })
  (measured, cause)
}
