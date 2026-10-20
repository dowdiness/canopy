///|
priv struct FocusMeasurement {
  lines : @writing_focus.LineRange
  range : @writing_focus.Range
}

///|
/// All cached values belong to this source and layout. A text change keeps
/// only the fact that a caret was previously measured, not its old coordinates.
priv struct WritingSnapshot {
  source : @text_lines.TextLines
  reflow_revision : Int
  groups : @writing_focus.WritingGroups?
  focus : FocusMeasurement?
  caret : @writing_focus.CaretHistory
}

///|
/// None means not yet measured, rather than independently missing source,
/// revision, and cache fields.
priv struct WritingMeasurement {
  area : @text_layout.TextArea
  mut snapshot : WritingSnapshot?
}

///|
fn WritingMeasurement::WritingMeasurement(
  area : @dom.HTMLTextAreaElement,
) -> WritingMeasurement {
  { area: @text_layout.TextArea(area), snapshot: None, }
}

///|
/// Pure transition: reuse a matching generation or create its replacement.
fn writing_snapshot(
  previous : WritingSnapshot?,
  measured : @text_layout.MeasuredText,
) -> (WritingSnapshot, Bool) {
  let source = measured.source
  let reflow_revision = measured.reflow_revision
  match previous {
    Some(previous) if physical_equal(previous.source, source) &&
      previous.reflow_revision == reflow_revision => (previous, false)
    _ => {
      let groups = match previous {
        Some(previous) if physical_equal(previous.source, source) =>
          previous.groups
        _ => None
      }
      let caret = match previous {
        Some(previous) if previous.reflow_revision == reflow_revision =>
          match previous.caret {
            Unmeasured => @writing_focus.Unmeasured
            OtherText | SameText(_) => OtherText
          }
        _ => @writing_focus.Unmeasured
      }
      ({ source, reflow_revision, groups, focus: None, caret, }, true)
    }
  }
}

///|
/// A completed frame contains values only. Callers cannot pair a textarea
/// with an earlier snapshot or ask for deferred geometry reads.
priv struct WritingGeometry {
  metrics : @text_layout.TextMetrics
  layer_left : Double
  focus : @writing_focus.Range?
  caret : (@writing_focus.Caret, @writing_focus.CaretCause)?
  viewport : @writing_focus.Range
  changed : Bool
}

///|
fn WritingMeasurement::measure(
  self : WritingMeasurement,
  dims~ : Bool,
) -> WritingGeometry raise {
  let area = self.area.element
  let measured = @text_layout.measure(self.area)
  let selection_start = area.get_selection_start()
  let selection_end = area.get_selection_end()
  let end = @writing_focus.selection_end(
    selection_start,
    selection_end,
    backward=area.get_selection_direction() == "backward",
    editable_focus=area.matches(":focus:read-write"),
  )
  let scroll_top = area.get_scroll_top()
  let (snapshot, changed) = writing_snapshot(self.snapshot, measured)
  let (snapshot, focus) = if dims {
    let (snapshot, range) = snapshot.locate_focus(
      self.area,
      selection_start,
      selection_end,
    )
    (snapshot, Some(range))
  } else {
    (snapshot, None)
  }
  let (snapshot, caret) = match end {
    Endpoint(_) => (snapshot, None)
    Collapsed(offset) => {
      let (snapshot, caret, cause) = snapshot.locate_caret(
        self.area,
        measured.metrics,
        offset,
      )
      let at : @writing_focus.Caret = { x: caret.x, y: caret.y, scroll_top, }
      (snapshot, Some((at, cause)))
    }
  }
  self.snapshot = Some(snapshot)
  {
    metrics: measured.metrics,
    layer_left: area.get_offset_left() + measured.metrics.padding_left,
    focus,
    caret,
    viewport: @writing_focus.Range(
      scroll_top,
      scroll_top + area.get_client_height(),
    ),
    changed,
  }
}

///|
fn WritingSnapshot::locate_focus(
  self : WritingSnapshot,
  area : @text_layout.TextArea,
  selection_start : Int,
  selection_end : Int,
) -> (WritingSnapshot, @writing_focus.Range) raise {
  let groups = match self.groups {
    Some(groups) => groups
    None => @writing_focus.WritingGroups(self.source)
  }
  let lines = groups.focus_lines(selection_start, selection_end)
  match self.focus {
    Some(focus) if focus.lines.first == lines.first &&
      focus.lines.last == lines.last => (self, focus.range)
    _ => {
      let (top, bottom) = @text_layout.measure_line_bounds(
        area,
        lines.first,
        lines.last,
      )
      let range = groups.focus_range(lines, top~, bottom~)
      ({ ..self, groups: Some(groups), focus: Some({ lines, range, }), }, range)
    }
  }
}

///|
fn WritingSnapshot::locate_caret(
  self : WritingSnapshot,
  area : @text_layout.TextArea,
  metrics : @text_layout.TextMetrics,
  offset : Int,
) -> (WritingSnapshot, @writing_focus.MeasuredCaret, @writing_focus.CaretCause) raise {
  let cause = match @writing_focus.caret_measure(self.caret, offset) {
    Cached(measured) => return (self, measured, Navigation)
    Measure(cause) => cause
  }
  let position = @text_layout.measure_caret(area, offset)
  let measured : @writing_focus.MeasuredCaret = {
    offset,
    x: @writing_focus.drawn_caret_x(
      position.x - metrics.padding_left,
      layer_width=metrics.content_width,
      half_width=CARET_WIDTH / 2.0,
    ),
    y: position.y,
  }
  ({ ..self, caret: SameText(measured), }, measured, cause)
}
