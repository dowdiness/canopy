///|
pub struct Range {
  start : Double
  end : Double
}

///|
pub suberror InvalidRange {
  UnorderedEndpoints(start~ : Double, end~ : Double)
}

///|
pub fn Range::Range(start : Double, end : Double) -> Range raise InvalidRange {
  guard start <= end else { raise UnorderedEndpoints(start~, end~) }
  { start, end, }
}

///|
pub fn Range::intersection(self : Range, other : Range) -> Range? {
  let start = if self.start > other.start { self.start } else { other.start }
  let end = if self.end < other.end { self.end } else { other.end }
  if start < end {
    Some({ start, end, })
  } else {
    None
  }
}
