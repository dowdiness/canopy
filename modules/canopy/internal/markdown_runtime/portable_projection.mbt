///|
/// Errors returned by the canonical-to-portable Markdown projection core.
pub enum PortableProjectionError {
  InvalidHiddenRange
  OverlappingHiddenRanges
  InvalidCoordinateRange
  InvalidEditRange
  CanonicalAfterSourceMismatch
  NonRepresentable
} derive(Debug, Eq)

///|
/// An immutable canonical-to-portable coordinate projection. Its canonical
/// source and private hidden ranges remain inside the Markdown runtime.
pub struct PortableCoordinateMap {
  priv canonical : String
  priv portable : String
  priv hidden : Array[@loom.Range]
} derive(Debug, Eq)

///|
pub fn PortableCoordinateMap::source(self : Self) -> String {
  self.portable
}

///|
/// Collapse one canonical UTF-16 offset onto its sentinel-free position.
pub fn PortableCoordinateMap::project_offset(
  self : Self,
  offset : Int,
) -> Result[Int, PortableProjectionError] {
  if offset < 0 || offset > self.canonical.length() {
    return Err(PortableProjectionError::InvalidCoordinateRange)
  }
  Ok(offset - hidden_width(self.hidden, 0, offset))
}

///|
/// Project one canonical half-open UTF-16 range without exposing hidden spans.
pub fn PortableCoordinateMap::project_range(
  self : Self,
  start : Int,
  end : Int,
) -> Result[(Int, Int), PortableProjectionError] {
  if start < 0 || end < start || end > self.canonical.length() {
    return Err(PortableProjectionError::InvalidCoordinateRange)
  }
  Ok(
    (
      start - hidden_width(self.hidden, 0, start),
      end - hidden_width(self.hidden, 0, end),
    ),
  )
}

///|
/// Project one accepted canonical edit between two validated coordinate maps.
pub fn PortableCoordinateMap::project_edit(
  self : Self,
  edit : @core.SpanEdit,
  after : PortableCoordinateMap,
) -> Result[@core.SpanEdit, PortableProjectionError] {
  project_markdown_edit(
    self.canonical,
    self.hidden,
    edit,
    after.canonical,
    after.hidden,
  )
}

///|
/// Validate and own one coordinate map without retaining caller-owned arrays.
fn make_portable_coordinate_map(
  canonical : String,
  hidden : ArrayView[@loom.Range],
) -> Result[PortableCoordinateMap, PortableProjectionError] {
  let hidden = match normalize_hidden_ranges(canonical, hidden) {
    Ok(ranges) => ranges
    Err(error) => return Err(error)
  }
  let portable = project_normalized_source(canonical, hidden)
  Ok({ canonical, portable, hidden })
}

///|
/// Project canonical source text by removing the supplied private ranges.
fn project_source(
  source : String,
  hidden_ranges : ArrayView[@loom.Range],
) -> Result[String, PortableProjectionError] {
  let ranges = normalize_hidden_ranges(source, hidden_ranges)
  match ranges {
    Ok(ranges) => Ok(project_normalized_source(source, ranges))
    Err(error) => Err(error)
  }
}

///|
/// Project one accepted canonical edit and verify it against both projected
/// source snapshots. The hidden-range arrays are copied and never mutated.
pub fn project_markdown_edit(
  before : String,
  before_hidden : ArrayView[@loom.Range],
  edit : @core.SpanEdit,
  after : String,
  after_hidden : ArrayView[@loom.Range],
) -> Result[@core.SpanEdit, PortableProjectionError] {
  let before_ranges = match normalize_hidden_ranges(before, before_hidden) {
    Ok(ranges) => ranges
    Err(error) => return Err(error)
  }
  let after_ranges = match normalize_hidden_ranges(after, after_hidden) {
    Ok(ranges) => ranges
    Err(error) => return Err(error)
  }
  let before_length = before.length()
  if edit.start < 0 ||
    edit.delete_len < 0 ||
    edit.start > before_length ||
    edit.delete_len > before_length - edit.start {
    return Err(PortableProjectionError::InvalidEditRange)
  }
  let expected_after = apply_span_edit(before, edit)
  if expected_after != after {
    return Err(PortableProjectionError::CanonicalAfterSourceMismatch)
  }
  let inserted_length = edit.inserted.length()
  if edit.start > after.length() ||
    inserted_length > after.length() - edit.start {
    return Err(PortableProjectionError::CanonicalAfterSourceMismatch)
  }
  let before_portable = project_normalized_source(before, before_ranges)
  let after_portable = project_normalized_source(after, after_ranges)
  let inserted_end = edit.start + inserted_length
  let projected_inserted = project_normalized_interval(
    after,
    after_ranges,
    edit.start,
    inserted_end,
  )
  let projected = @core.SpanEdit::{
    start: edit.start - hidden_width(before_ranges, 0, edit.start),
    delete_len: edit.delete_len -
    hidden_width(before_ranges, edit.start, edit.start + edit.delete_len),
    inserted: projected_inserted,
  }
  if apply_span_edit(before_portable, projected) != after_portable {
    return Err(PortableProjectionError::NonRepresentable)
  }
  Ok(projected)
}

///|
/// Validate, copy, and sort ranges without changing the caller's array.
fn normalize_hidden_ranges(
  source : String,
  hidden_ranges : ArrayView[@loom.Range],
) -> Result[Array[@loom.Range], PortableProjectionError] {
  let ranges = hidden_ranges.map(range => range)
  ranges.sort_by(fn(a, b) { a.start.compare(b.start) })
  let mut previous_end = -1
  for range in ranges {
    if range.start < 0 ||
      range.end <= range.start ||
      range.end > source.length() {
      return Err(PortableProjectionError::InvalidHiddenRange)
    }
    if previous_end >= 0 && range.start < previous_end {
      return Err(PortableProjectionError::OverlappingHiddenRanges)
    }
    previous_end = range.end
  }
  Ok(ranges)
}

///|
/// Assemble a projected source from already validated, sorted ranges.
fn project_normalized_source(
  source : String,
  ranges : Array[@loom.Range],
) -> String {
  let builder = StringBuilder()
  let mut cursor = 0
  for range in ranges {
    if range.start > cursor {
      builder.write_string(source[cursor:range.start].to_owned())
    }
    cursor = range.end
  }
  if cursor < source.length() {
    builder.write_string(source[cursor:].to_owned())
  }
  builder.to_string()
}

///|
/// Assemble only the after-source insertion interval, clipping hidden ranges
/// to that interval so newly inserted sentinels are not carried into output.
fn project_normalized_interval(
  source : String,
  ranges : Array[@loom.Range],
  start : Int,
  end : Int,
) -> String {
  let builder = StringBuilder()
  let mut cursor = start
  for range in ranges {
    if range.end <= start || range.start >= end {
      continue
    }
    let clipped_start = if range.start < start { start } else { range.start }
    let clipped_end = if range.end > end { end } else { range.end }
    if clipped_start > cursor {
      builder.write_string(source[cursor:clipped_start].to_owned())
    }
    cursor = clipped_end
  }
  if cursor < end {
    builder.write_string(source[cursor:end].to_owned())
  }
  builder.to_string()
}

///|
/// Count private characters in the half-open interval [start, end].
fn hidden_width(ranges : Array[@loom.Range], start : Int, end : Int) -> Int {
  ranges.fold(init=0, (total, range) => {
    let clipped_start = if range.start < start { start } else { range.start }
    let clipped_end = if range.end > end { end } else { range.end }
    total +
    (if clipped_end > clipped_start { clipped_end - clipped_start } else { 0 })
  })
}

///|
/// Apply one validated source-coordinate span edit.
fn apply_span_edit(source : String, edit : @core.SpanEdit) -> String {
  let builder = StringBuilder()
  builder.write_string(source[:edit.start].to_owned())
  builder.write_string(edit.inserted)
  builder.write_string(source[edit.start + edit.delete_len:].to_owned())
  builder.to_string()
}
