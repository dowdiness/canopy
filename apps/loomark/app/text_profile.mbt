///|
fn is_blank(c : Char) -> Bool {
  c == ' ' ||
  c == '\n' ||
  c == '\t' ||
  c == '\r' ||
  c == '\u{3000}' ||
  c == '\u{A0}'
}

///|
/// Code points that render as part of the preceding character: combining
/// marks, variation selectors (including ideographic variants), emoji
/// modifiers, and tags.
fn joins_previous(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 0x0300 && code <= 0x036F) ||
  (code >= 0x1AB0 && code <= 0x1AFF) ||
  (code >= 0x1DC0 && code <= 0x1DFF) ||
  (code >= 0x20D0 && code <= 0x20FF) ||
  code == 0x200D ||
  (code >= 0x3099 && code <= 0x309A) ||
  (code >= 0xFE00 && code <= 0xFE0F) ||
  (code >= 0xFE20 && code <= 0xFE2F) ||
  (code >= 0x1F3FB && code <= 0x1F3FF) ||
  (code >= 0xE0000 && code <= 0xE01EF)
}

///|
/// Measures of settled Document text shown around the editor.
priv struct TextProfile {
  /// Visible characters, excluding spaces and line breaks.
  characters : Int
} derive(Eq)

///|
fn text_profile(text : String) -> TextProfile {
  let mut characters = 0
  let mut after_joiner = false
  for c in text {
    if !is_blank(c) && !joins_previous(c) && !after_joiner {
      characters += 1
    }
    after_joiner = c == '\u{200D}'
  }
  { characters, }
}

///|
fn character_count_label(count : Int) -> String {
  let digits = count.to_string()
  let grouped = StringBuilder()
  for i, c in digits {
    if i > 0 && (digits.length() - i) % 3 == 0 {
      grouped.write_char(',')
    }
    grouped.write_char(c)
  }
  if count == 1 {
    "1 character"
  } else {
    "\{grouped} characters"
  }
}
