///|
pub struct Layout {
  priv reference : TextLines
  priv replacement : LineReplacement?
  priv measurement : Measurement?
}

///|
priv struct Measurement {
  width : Double
  line_height : Double
  lines : LineRange
  range : Range
}

///|
pub fn Layout::Layout(source : TextLines) -> Layout {
  { reference: source, replacement: None, measurement: None, }
}

///|
pub fn Layout::source(self : Layout) -> TextLines {
  match self.replacement {
    None => self.reference
    Some(replacement) => replacement.text_lines
  }
}

///|
pub fn Layout::replace_text(self : Layout, text : String) -> Layout? {
  if self.source().text() == text {
    return None
  }
  // Retained positions belong to reference, not to an intermediate unmeasured
  // edit. Restoring that text also restores the full reusable prefix.
  Some({
    reference: self.reference,
    replacement: self.reference.replace_text(text),
    measurement: self.measurement,
  })
}

///|
pub suberror InvalidSelection {
  OutsideText(start~ : Int, end~ : Int, length~ : Int)
}

///|
pub enum Focus {
  Document(Range)
  Lines(LineFocus)
}

///|
pub struct LineFocus {
  lines : LineRange
  priv layout : Layout
  priv line_count : Int
  priv unchanged_prefix : Int
}

///|
pub fn Layout::focus(
  self : Layout,
  selection_start : Int,
  selection_end : Int,
) -> Focus raise InvalidSelection {
  let source = self.source()
  let lines = source.focus_lines(selection_start, selection_end)
  let line_count = source.lines().length()
  if lines.first == 0 && lines.last == line_count - 1 {
    return Document({ start: 0.0, end: @double.infinity, })
  }
  let unchanged_prefix = match self.replacement {
    None => line_count
    Some(replacement) => replacement.first
  }
  Lines({ lines, layout: self, line_count, unchanged_prefix, })
}

///|
pub struct LineEdit {
  source : TextLines
  first : Int
  removed : Int
  inserted : ArrayView[String]
}

///|
/// The mirror may still contain text from an earlier layout context.
pub fn Layout::edit_from(self : Layout, rendered : TextLines) -> LineEdit? {
  let source = self.source()
  if rendered.text() == source.text() {
    return None
  }
  if rendered.text() == self.reference.text() &&
    self.replacement is Some(replacement) {
    return Some({
      source,
      first: replacement.first,
      removed: replacement.removed,
      inserted: replacement.inserted,
    })
  }
  let before = rendered.lines()
  let after = source.lines()
  let mut first = 0
  while first < before.length() &&
        first < after.length() &&
        before[first] == after[first] {
    first += 1
  }
  let mut old_end = before.length()
  let mut new_end = after.length()
  while old_end > first &&
        new_end > first &&
        before[old_end - 1] == after[new_end - 1] {
    old_end -= 1
    new_end -= 1
  }
  Some({
    source,
    first,
    removed: old_end - first,
    inserted: after[first:new_end],
  })
}
