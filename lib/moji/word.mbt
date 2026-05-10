// UAX #29 word-boundary segmentation. Unicode 15.1.
//
// Public API:
//   - prev_word_boundary(text, pos)   at-or-before
//   - next_word_boundary(text, pos)   at-or-after
//   - word_boundaries(text)           Array[Int]
//
// All `pos` arguments are UTF-16 code-unit offsets. Functions accept any
// `Int` offset, clamping to `[0, text.length()]`.

///|
priv struct WordState {
  prev : WB
  has_prev : Bool
  eff_prev : WB
  has_eff_prev : Bool
  eff_prev_prev : WB
  has_eff_prev_prev : Bool
  ri_odd : Bool
}

///|
fn WordState::start() -> WordState {
  {
    prev: WbOther,
    has_prev: false,
    eff_prev: WbOther,
    has_eff_prev: false,
    eff_prev_prev: WbOther,
    has_eff_prev_prev: false,
    ri_odd: false,
  }
}

///|
fn WordState::advance(self : WordState, wb : WB) -> WordState {
  let ignored = is_wb_ignored(wb) &&
    self.has_prev &&
    !is_wb_hard_break(self.prev)
  if ignored {
    return {
      prev: wb,
      has_prev: true,
      eff_prev: self.eff_prev,
      has_eff_prev: self.has_eff_prev,
      eff_prev_prev: self.eff_prev_prev,
      has_eff_prev_prev: self.has_eff_prev_prev,
      ri_odd: self.ri_odd,
    }
  }
  let ri_next = if wb == WbRI { !self.ri_odd } else { false }
  {
    prev: wb,
    has_prev: true,
    eff_prev: wb,
    has_eff_prev: true,
    eff_prev_prev: self.eff_prev,
    has_eff_prev_prev: self.has_eff_prev,
    ri_odd: ri_next,
  }
}

///|
fn WordState::break_before(
  self : WordState,
  wb : WB,
  is_ep : Bool,
  text : String,
  next_i : Int,
) -> Bool {
  // WB3: CR x LF
  if self.prev == WbCR && wb == WbLF {
    return false
  }
  // WB3a: (Newline | CR | LF) / 
  if is_wb_hard_break(self.prev) {
    return true
  }
  // WB3b: / (Newline | CR | LF)
  if is_wb_hard_break(wb) {
    return true
  }
  // WB3c: ZWJ x Extended_Pictographic. This is raw-adjacent.
  if self.prev == WbZWJ && is_ep {
    return false
  }
  // WB3d: WSegSpace x WSegSpace
  if self.prev == WbWSegSpace && wb == WbWSegSpace {
    return false
  }
  // WB4: X (Extend | Format | ZWJ)
  if is_wb_ignored(wb) && self.has_prev && !is_wb_hard_break(self.prev) {
    return false
  }
  // WB5: AHLetter x AHLetter
  if self.has_eff_prev && is_ahletter(self.eff_prev) && is_ahletter(wb) {
    return false
  }
  // WB6: AHLetter x (MidLetter | MidNumLetQ) AHLetter
  if self.has_eff_prev &&
    is_ahletter(self.eff_prev) &&
    is_midletter_or_midnumletq(wb) &&
    next_effective_is_ahletter(text, next_i) {
    return false
  }
  // WB7: AHLetter (MidLetter | MidNumLetQ) x AHLetter
  if self.has_eff_prev_prev &&
    is_ahletter(self.eff_prev_prev) &&
    is_midletter_or_midnumletq(self.eff_prev) &&
    is_ahletter(wb) {
    return false
  }
  // WB7a: Hebrew_Letter x Single_Quote
  if self.has_eff_prev && self.eff_prev == WbHebrewLetter && wb == WbSingleQuote {
    return false
  }
  // WB7b: Hebrew_Letter x Double_Quote Hebrew_Letter
  if self.has_eff_prev &&
    self.eff_prev == WbHebrewLetter &&
    wb == WbDoubleQuote &&
    next_effective_is_hebrew_letter(text, next_i) {
    return false
  }
  // WB7c: Hebrew_Letter Double_Quote x Hebrew_Letter
  if self.has_eff_prev_prev &&
    self.eff_prev_prev == WbHebrewLetter &&
    self.eff_prev == WbDoubleQuote &&
    wb == WbHebrewLetter {
    return false
  }
  // WB8: Numeric x Numeric
  if self.has_eff_prev && self.eff_prev == WbNumeric && wb == WbNumeric {
    return false
  }
  // WB9: AHLetter x Numeric
  if self.has_eff_prev && is_ahletter(self.eff_prev) && wb == WbNumeric {
    return false
  }
  // WB10: Numeric x AHLetter
  if self.has_eff_prev && self.eff_prev == WbNumeric && is_ahletter(wb) {
    return false
  }
  // WB11: Numeric (MidNum | MidNumLetQ) x Numeric
  if self.has_eff_prev_prev &&
    self.eff_prev_prev == WbNumeric &&
    is_midnum_or_midnumletq(self.eff_prev) &&
    wb == WbNumeric {
    return false
  }
  // WB12: Numeric x (MidNum | MidNumLetQ) Numeric
  if self.has_eff_prev &&
    self.eff_prev == WbNumeric &&
    is_midnum_or_midnumletq(wb) &&
    next_effective_is_numeric(text, next_i) {
    return false
  }
  // WB13: Katakana x Katakana
  if self.has_eff_prev && self.eff_prev == WbKatakana && wb == WbKatakana {
    return false
  }
  // WB13a: (AHLetter | Numeric | Katakana | ExtendNumLet) x ExtendNumLet
  if self.has_eff_prev &&
    is_wordish_or_extendnumlet(self.eff_prev) &&
    wb == WbExtendNumLet {
    return false
  }
  // WB13b: ExtendNumLet x (AHLetter | Numeric | Katakana)
  if self.has_eff_prev && self.eff_prev == WbExtendNumLet && is_wordish(wb) {
    return false
  }
  // WB15/16: pair-bond Regional_Indicators
  if self.ri_odd && wb == WbRI {
    return false
  }
  // WB999: default break
  true
}

///|
fn is_wb_hard_break(wb : WB) -> Bool {
  wb == WbCR || wb == WbLF || wb == WbNewline
}

///|
fn is_wb_ignored(wb : WB) -> Bool {
  wb == WbExtend || wb == WbFormat || wb == WbZWJ
}

///|
fn is_ahletter(wb : WB) -> Bool {
  wb == WbALetter || wb == WbHebrewLetter
}

///|
fn is_midnumletq(wb : WB) -> Bool {
  wb == WbMidNumLet || wb == WbSingleQuote
}

///|
fn is_midletter_or_midnumletq(wb : WB) -> Bool {
  wb == WbMidLetter || is_midnumletq(wb)
}

///|
fn is_midnum_or_midnumletq(wb : WB) -> Bool {
  wb == WbMidNum || is_midnumletq(wb)
}

///|
fn is_wordish(wb : WB) -> Bool {
  is_ahletter(wb) || wb == WbNumeric || wb == WbKatakana
}

///|
fn is_wordish_or_extendnumlet(wb : WB) -> Bool {
  is_wordish(wb) || wb == WbExtendNumLet
}

///|
fn next_effective_wb(text : String, start : Int) -> WB? {
  let len = text.length()
  let mut i = start
  while i < len {
    let (cp, next_i) = decode_codepoint_at(text, i)
    let wb = wb_of(cp)
    if !is_wb_ignored(wb) {
      return Some(wb)
    }
    i = next_i
  }
  None
}

///|
fn next_effective_is_ahletter(text : String, start : Int) -> Bool {
  match next_effective_wb(text, start) {
    Some(wb) => is_ahletter(wb)
    None => false
  }
}

///|
fn next_effective_is_hebrew_letter(text : String, start : Int) -> Bool {
  match next_effective_wb(text, start) {
    Some(wb) => wb == WbHebrewLetter
    None => false
  }
}

///|
fn next_effective_is_numeric(text : String, start : Int) -> Bool {
  match next_effective_wb(text, start) {
    Some(wb) => wb == WbNumeric
    None => false
  }
}

///|
/// All word boundaries in `text`, sorted ascending.
///
/// First element is always `0`; last is always `text.length()`. For empty
/// text, returns `[0]` (single boundary).
pub fn word_boundaries(text : String) -> Array[Int] {
  let out : Array[Int] = []
  out.push(0)
  let len = text.length()
  if len == 0 {
    return out
  }
  let (cp0, init_i) = decode_codepoint_at(text, 0)
  let mut i = init_i
  let mut state = WordState::start().advance(wb_of(cp0))
  while i < len {
    let (cp, next_i) = decode_codepoint_at(text, i)
    let wb = wb_of(cp)
    let ep = is_extended_pictographic(cp)
    if state.break_before(wb, ep, text, next_i) {
      out.push(i)
    }
    state = state.advance(wb)
    i = next_i
  }
  out.push(len)
  out
}

///|
/// Smallest word boundary `>= pos`.
///
/// Returns `0` if `pos <= 0`. Returns `text.length()` if
/// `pos >= text.length()`. Accepts any `Int`, including positions inside
/// surrogate pairs and inside multi-codepoint word segments; never aborts.
pub fn next_word_boundary(text : String, pos : Int) -> Int {
  let len = text.length()
  if pos <= 0 {
    return 0
  }
  if pos >= len {
    return len
  }
  let bs = word_boundaries(text)
  for b in bs {
    if b >= pos {
      return b
    }
  }
  len
}

///|
/// Largest word boundary `<= pos`.
///
/// Returns `0` if `pos <= 0`. Returns `text.length()` if
/// `pos >= text.length()`. Same offset-tolerance contract as
/// `next_word_boundary`.
pub fn prev_word_boundary(text : String, pos : Int) -> Int {
  let len = text.length()
  if pos <= 0 {
    return 0
  }
  if pos >= len {
    return len
  }
  let bs = word_boundaries(text)
  let mut last = 0
  for b in bs {
    if b > pos {
      return last
    }
    last = b
  }
  last
}
