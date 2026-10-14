///|
/// Kana and ideographs: Japanese text has no spaces between words.
fn is_east_asian(c : Char) -> Bool {
  let code = c.to_int()
  (code >= 0x3040 && code <= 0x30FF) ||
  (code >= 0x3400 && code <= 0x4DBF) ||
  (code >= 0x4E00 && code <= 0x9FFF) ||
  (code >= 0xF900 && code <= 0xFAFF) ||
  (code >= 0xFF66 && code <= 0xFF9F)
}

///|
/// Letters and digits outside East Asian scripts; punctuation, symbols, and
/// Markdown markers do not start a word.
fn is_word_letter(c : Char) -> Bool {
  let code = c.to_int()
  if code < 0x80 {
    c.is_ascii_alphabetic() || c.is_ascii_digit()
  } else {
    !(code >= 0x2000 && code <= 0x2BFF) && !(code >= 0x3000 && code <= 0x303F)
  }
}

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
  /// Kana marks Japanese rather than Chinese; East Asian characters must
  /// outnumber other words so an English note with a Japanese phrase keeps
  /// its own typography.
  japanese : Bool
} derive(Eq)

///|
fn text_profile(text : String) -> TextProfile {
  let mut characters = 0
  let mut east_asian = 0
  let mut other_words = 0
  let mut kana = false
  let mut in_word = false
  let mut after_joiner = false
  for c in text {
    if is_blank(c) {
      in_word = false
    } else if joins_previous(c) || after_joiner {
      ()
    } else {
      characters += 1
      if is_east_asian(c) {
        east_asian += 1
        kana = kana || c <= '\u{30FF}'
        in_word = false
      } else if !in_word && is_word_letter(c) {
        other_words += 1
        in_word = true
      }
    }
    after_joiner = c == '\u{200D}'
  }
  { characters, japanese: kana && east_asian >= other_words, }
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
