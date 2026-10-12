///|
pub enum Bounds {
  Known(Range)
  Lines(LineBounds)
  LineStart(Boundary)
  LineEnd(Boundary)
}

///|
/// Reuse covers styles and width only; mirror text may still need updating.
pub enum LayoutSync {
  Reuse
  CopyStyles(Double)
}

///|
pub struct LineBounds {
  lines : LineRange
  priv focus : LineFocus
  priv width : Double
  layout_sync : LayoutSync
}

///|
priv enum Endpoint {
  Start(Double)
  End(Double)
}

///|
pub struct Boundary {
  line : Int
  priv known : Endpoint
  priv focus : LineFocus
  priv width : Double
  layout_sync : LayoutSync
}

///|
pub fn LineFocus::bounds(
  self : LineFocus,
  width : Double,
) -> Bounds raise InvalidRange {
  let reusable = match self.layout.measurement {
    Some(measurement) if measurement.width == width => Some(measurement)
    _ => None
  }
  let start = if self.lines.first == 0 {
    Some(0.0)
  } else {
    match reusable {
      Some(measurement) if measurement.lines.first == self.lines.first &&
        self.lines.first <= self.unchanged_prefix =>
        Some(measurement.range.start)
      _ => None
    }
  }
  let end = if self.lines.last == self.line_count - 1 {
    Some(@double.infinity)
  } else {
    match reusable {
      // Infinity belongs to the reference's document end, not to a line end.
      Some(measurement) if measurement.lines.last <
        self.layout.reference.lines().length() - 1 &&
        measurement.lines.last == self.lines.last &&
        self.lines.last < self.unchanged_prefix => Some(measurement.range.end)
      _ => None
    }
  }
  let layout_sync = if reusable is Some(_) { Reuse } else { CopyStyles(width) }
  match (start, end) {
    (Some(start), Some(end)) => {
      let range = match reusable {
        Some(measurement) if measurement.range.start == start &&
          measurement.range.end == end => measurement.range
        _ => Range(start, end)
      }
      Known(range)
    }
    (None, None) =>
      Lines({ lines: self.lines, focus: self, width, layout_sync, })
    (None, Some(end)) =>
      LineStart({
        line: self.lines.first,
        known: End(end),
        focus: self,
        width,
        layout_sync,
      })
    (Some(start), None) =>
      LineEnd({
        line: self.lines.last,
        known: Start(start),
        focus: self,
        width,
        layout_sync,
      })
  }
}

///|
pub fn LineBounds::between(
  self : LineBounds,
  start : Double,
  end : Double,
) -> (Range, Layout) raise InvalidRange {
  self.focus.measured(self.width, Range(start, end))
}

///|
pub fn Boundary::at(
  self : Boundary,
  position : Double,
) -> (Range, Layout) raise InvalidRange {
  let range = match self.known {
    Start(start) => Range(start, position)
    End(end) => Range(position, end)
  }
  self.focus.measured(self.width, range)
}

///|
fn LineFocus::measured(
  self : LineFocus,
  width : Double,
  range : Range,
) -> (Range, Layout) {
  let next : Layout = {
    reference: self.layout.source(),
    replacement: None,
    measurement: Some({ width, lines: self.lines, range, }),
  }
  (range, next)
}
