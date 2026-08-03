// Word-navigation policy over moji's raw UAX #29 word boundaries.
// Design: docs/plans/2026-07-05-word-navigation-policy.md (experimental —
// see the spec's disposal inventory before extending this file).

///|
priv enum WordNavClass {
  Whitespace
  WordLike
  Other
} derive(Eq)

///|
/// Classify a raw UAX word segment `[start, end)` by its first
/// non-default-ignorable codepoint. Segments made entirely of
/// default-ignorable codepoints classify as `Whitespace` so invisible
/// format characters never become stop targets.
fn classify_segment(text : String, start : Int, end : Int) -> WordNavClass {
  let mut i = start
  while i < end {
    let (cp, next_i) = @moji.decode_codepoint_at(text, i)
    if !@moji.is_default_ignorable_code_point(cp) {
      guard cp.to_char() is Some(ch) else { return Other }
      if ch.is_whitespace() {
        return Whitespace
      }
      return match @moji.wb_of(cp) {
        WbALetter | WbHebrewLetter | WbKatakana | WbNumeric | WbExtendNumLet =>
          WordLike
        _ => Other
      }
    }
    i = next_i
  }
  Whitespace
}

///|
/// Classified stop units: raw UAX segments with adjacent `Other` segments
/// merged, so a punctuation run or CJK stretch is one navigable unit.
fn word_nav_units(text : String) -> Array[(WordNavClass, Int, Int)] {
  let bounds = @moji.word_boundaries(text)
  let units : Array[(WordNavClass, Int, Int)] = []
  for i in 0..<(bounds.length() - 1) {
    let start = bounds[i]
    let end = bounds[i + 1]
    let kind = classify_segment(text, start, end)
    match units.last() {
      Some((Other, merged_start, _)) if kind == Other =>
        units[units.length() - 1] = (Other, merged_start, end)
      _ => units.push((kind, start, end))
    }
  }
  units
}

///|
/// End of the first non-whitespace unit strictly right of `pos`
/// (VS Code-style Ctrl+Right), post-snapped to a grapheme boundary
/// because UAX word boundaries can fall inside grapheme clusters
/// (e.g. GCB=Prepend codepoints).
fn next_word_stop(text : String, pos : Int) -> Int {
  for unit in word_nav_units(text) {
    let (kind, _, end) = unit
    if kind != Whitespace && end > pos {
      return @moji.next_grapheme_boundary(text, end)
    }
  }
  text.length()
}

///|
/// Start of the last non-whitespace unit strictly left of `pos`
/// (VS Code-style Ctrl+Left), post-snapped like `next_word_stop`.
fn prev_word_stop(text : String, pos : Int) -> Int {
  let units = word_nav_units(text)
  for i = units.length() - 1; i >= 0; i = i - 1 {
    let (kind, start, _) = units[i]
    if kind != Whitespace && start < pos {
      return @moji.prev_grapheme_boundary(text, start)
    }
  }
  0
}
