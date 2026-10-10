///|
pub fn calculate_visible_range(
  content_range : Range,
  viewport_range : Range,
) -> Range? {
  content_range
  .intersection(viewport_range)
  .map(visible_range => {
    start: visible_range.start - viewport_range.start,
    end: visible_range.end - viewport_range.start,
  })
}

///|
pub(all) enum Boundary {
  Position(Double)
  LineStart(Int)
  LineEnd(Int)
} derive(Eq, Debug)

///|
pub fn focus_boundaries(
  focused_lines : LineRange,
  line_count : Int,
  unchanged_prefix_lines : Int,
  measured_start : (Int, Double)?,
  measured_end : (Int, Double)?,
) -> (Boundary, Boundary) {
  let start_boundary = if focused_lines.first == 0 {
    Position(0.0)
  } else {
    match measured_start {
      Some((line, position)) if line == focused_lines.first &&
        line <= unchanged_prefix_lines => Position(position)
      _ => LineStart(focused_lines.first)
    }
  }
  let end_boundary = if focused_lines.last == line_count - 1 {
    Position(@double.infinity)
  } else {
    match measured_end {
      Some((line, position)) if line == focused_lines.last &&
        line < unchanged_prefix_lines => Position(position)
      _ => LineEnd(focused_lines.last)
    }
  }
  (start_boundary, end_boundary)
}

///|
pub extend Boundary with Eq::{equal, not_equal}

///|
pub extend Boundary with @moonbitlang/core/debug.Debug::{to_repr}
