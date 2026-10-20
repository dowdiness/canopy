///|
pub struct LineRange {
  first : Int
  last : Int
}

///|
pub struct WritingGroups {
  priv source : @text_lines.TextLines
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
pub fn WritingGroups::WritingGroups(
  source : @text_lines.TextLines,
) -> WritingGroups {
  { source, groups: group_lines(source.lines()), }
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
/// The writing group, or groups, that a selection touches.
pub fn WritingGroups::focus_lines(
  self : WritingGroups,
  selection_start : Int,
  selection_end : Int,
) -> LineRange raise @text_lines.InvalidSelection {
  let selection = self.source.selected_lines(selection_start, selection_end)
  let (first_line, last_line) = match selection {
    Caret(line) => (line, line)
    Span(first~, last~) => (first, last)
  }
  let first = match group_at(self.groups, first_line) {
    Some(group) => group.first
    None if selection is Caret(_) =>
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
pub fn WritingGroups::focus_range(
  self : WritingGroups,
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
    if lines.last == self.source.lines().length() - 1 {
      @double.infinity
    } else {
      bottom
    },
  )
}
