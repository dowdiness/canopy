///|
pub struct LineRange {
  first : Int
  last : Int
}

///|
pub struct TextLines {
  priv text : String
  priv lines : ArrayView[String]
  priv starts : ArrayView[Int]
  priv groups : ArrayView[LineRange]
}

///|
priv struct FenceMarker {
  character : Char
  length : Int
}

///|
priv enum FenceLine {
  Bare(FenceMarker)
  Annotated(FenceMarker)
}

///|
fn without_quote_prefix(text : StringView) -> StringView {
  for rest = text {
    let unindented = rest.trim_start(chars=" ")
    if rest.length() - unindented.length() > 3 {
      break rest
    }
    match unindented {
      ['>', .. remaining] => {
        let remaining = match remaining {
          [' ' | '\t', .. rest] => rest
          _ => remaining
        }
        continue remaining
      }
      _ => break rest
    }
  }
}

///|
fn parse_fence(content : StringView) -> FenceLine? {
  let marker_text = content.trim_start(chars=" ")
  guard content.length() - marker_text.length() <= 3 else { return None }
  let (character, repeated) : (Char, StringView) = match marker_text {
    ['`', ..] => ('`', "`")
    ['~', ..] => ('~', "~")
    _ => return None
  }
  let rest = marker_text.trim_start(chars=repeated)
  let length = marker_text.length() - rest.length()
  guard length >= 3 else { return None }
  let marker = { character, length, }
  if rest.trim().is_empty() {
    Some(Bare(marker))
  } else if character == '`' && rest.contains("`") {
    None
  } else {
    Some(Annotated(marker))
  }
}

///|
fn next_fence(open : FenceMarker?, line : FenceLine?) -> FenceMarker? {
  match (open, line) {
    (Some(open), Some(Bare(close))) if close.character == open.character &&
      close.length >= open.length => None
    (None, Some(Bare(marker) | Annotated(marker))) => Some(marker)
    _ => open
  }
}

///|
fn has_code_indent(content : StringView) -> Bool {
  content.has_prefix("    ") || content.has_prefix("\t")
}

///|
fn find_group_end(lines : ArrayView[String], first : Int) -> Int {
  let indented = has_code_indent(without_quote_prefix(lines[first].view()))
  for end = first, fence = None; end < lines.length(); {
    let content = without_quote_prefix(lines[end].view())
    if fence is None && content.trim().is_empty() {
      let next_content = lines[end + 1:].search_by(line => {
        !without_quote_prefix(line.view()).trim().is_empty()
      })
      match next_content {
        Some(offset) if indented &&
          has_code_indent(without_quote_prefix(lines[end + 1 + offset].view())) =>
          continue end + 1 + offset, fence
        _ => break end
      }
    }
    continue end + 1, next_fence(fence, parse_fence(content))
  } nobreak {
    lines.length()
  }
}

///|
fn group_lines(lines : ArrayView[String]) -> ArrayView[LineRange] {
  let groups : Array[LineRange] = []
  for first = 0; first < lines.length(); {
    if without_quote_prefix(lines[first].view()).trim().is_empty() {
      continue first + 1
    }
    let end = find_group_end(lines, first)
    groups.push({ first, last: end - 1, })
    continue end
  }
  groups[:]
}

///|
fn index_lines(text : String, lines : ArrayView[String]) -> TextLines {
  let starts : Array[Int] = []
  lines.fold(init=0, (offset, line) => {
    starts.push(offset)
    offset + line.length() + 1
  })
  |> ignore
  { text, lines, starts: starts[:], groups: group_lines(lines), }
}

///|
pub fn TextLines::TextLines(text : String) -> TextLines {
  let lines = text.split("\n").map(line => line.to_owned()).to_array()
  index_lines(text, lines[:])
}

///|
pub fn TextLines::text(self : TextLines) -> String {
  self.text
}

///|
pub fn TextLines::lines(self : TextLines) -> ArrayView[String] {
  self.lines
}

///|
fn TextLines::line_at(self : TextLines, position : Int) -> Int {
  match self.starts.binary_search(position) {
    Ok(index) => index
    Err(index) => index - 1
  }
}

///|
pub struct TextPosition {
  line : Int
  column : Int
}

///|
/// A position after a line break belongs to the following line.
pub fn TextLines::position(
  self : TextLines,
  offset : Int,
) -> TextPosition raise InvalidSelection {
  guard 0 <= offset && offset <= self.text.length() else {
    raise OutsideText(start=offset, end=offset, length=self.text.length())
  }
  let line = self.line_at(offset)
  { line, column: offset - self.starts[line], }
}

///|
fn group_at(groups : ArrayView[LineRange], line : Int) -> LineRange? {
  match
    groups.binary_search_by(group => {
      if group.last < line {
        -1
      } else if group.first > line {
        1
      } else {
        0
      }
    }) {
    Ok(index) => Some(groups[index])
    Err(_) => None
  }
}

///|
pub suberror InvalidSelection {
  OutsideText(start~ : Int, end~ : Int, length~ : Int)
}

///|
/// The writing group, or groups, that a selection touches.
pub fn TextLines::focus_lines(
  self : TextLines,
  selection_start : Int,
  selection_end : Int,
) -> LineRange raise InvalidSelection {
  guard 0 <= selection_start &&
    selection_start <= selection_end &&
    selection_end <= self.text.length() else {
    raise OutsideText(
      start=selection_start,
      end=selection_end,
      length=self.text.length(),
    )
  }
  let first_line = self.line_at(selection_start)
  let last_line = self.line_at(
    if selection_end > selection_start {
      selection_end - 1
    } else {
      selection_end
    },
  )
  let first = match group_at(self.groups, first_line) {
    Some(group) => group.first
    None if selection_start == selection_end =>
      match
        self.groups.binary_search_by(group => group.first.compare(first_line)) {
        Err(index) if index > 0 => self.groups[index - 1].first
        _ => first_line
      }
    None => first_line
  }
  let last = match group_at(self.groups, last_line) {
    Some(group) => group.last
    None => last_line
  }
  { first, last, }
}

///|
/// The focused content range from the measured top of its first line and
/// bottom of its last; the first and last groups extend over the padding to
/// the document's edges.
pub fn TextLines::focus_range(
  self : TextLines,
  lines : LineRange,
  top~ : Double,
  bottom~ : Double,
) -> Range raise InvalidRange {
  Range(
    if lines.first == 0 {
      0.0
    } else {
      top
    },
    if lines.last == self.lines.length() - 1 {
      @double.infinity
    } else {
      bottom
    },
  )
}
