// UAX #29 grapheme-cluster segmentation. Unicode 15.1.
//
// Public API:
//   - prev_grapheme_boundary(text, pos)   at-or-before
//   - next_grapheme_boundary(text, pos)   at-or-after
//   - is_grapheme_boundary(text, pos)
//   - grapheme_clusters(text)             Iter[(start, end)]
//   - grapheme_boundaries(text)           Array[Int]   (escape hatch for cached point queries)
//
// All `pos` arguments are UTF-16 code-unit offsets. Functions accept any
// `Int` offset, clamping to `[0, text.length()]`.

///|
priv enum EpState {
  EpA // not in EP context
  EpB // saw EP, possibly followed by GCB-Extend
  EpC // saw EP Extend* ZWJ — ready to glue with next EP via GB11
} derive(Eq)

///|
priv enum IncbState {
  IcsNone
  IcsConsonant
  IcsLinker
} derive(Eq)

///|
priv struct State {
  prev_gcb : GCB
  ep : EpState
  ri_odd : Bool
  incb : IncbState
}

///|
fn State::start() -> State {
  // `prev_gcb` is meaningful only after the first codepoint is consumed;
  // the walker never queries break_before before that.
  { prev_gcb: Other, ep: EpA, ri_odd: false, incb: IcsNone }
}

///|
fn State::advance(self : State, gcb : GCB, is_ep : Bool, icb : InCB) -> State {
  let ep_next = match self.ep {
    EpA => if is_ep { EpB } else { EpA }
    EpB =>
      if gcb == Extend {
        EpB
      } else if gcb == ZWJ {
        EpC
      } else if is_ep {
        EpB
      } else {
        EpA
      }
    EpC => if is_ep { EpB } else { EpA }
  }
  let ri_next = if gcb == RI { !self.ri_odd } else { false }
  let incb_next : IncbState = match icb {
    IcbConsonant => IcsConsonant
    IcbLinker =>
      if self.incb == IcsConsonant || self.incb == IcsLinker {
        IcsLinker
      } else {
        IcsNone
      }
    IcbExtend =>
      if self.incb == IcsConsonant || self.incb == IcsLinker {
        self.incb
      } else {
        IcsNone
      }
    IcbNone => IcsNone
  }
  { prev_gcb: gcb, ep: ep_next, ri_odd: ri_next, incb: incb_next }
}

///|
/// Decide whether a grapheme break must be inserted between the previous
/// codepoint (encoded in `self`) and a current codepoint with the given
/// properties. Rule order matters: GB3/4/5 win before GB9/9a/9b.
fn State::break_before(
  self : State,
  gcb : GCB,
  is_ep : Bool,
  icb : InCB,
) -> Bool {
  // GB3: CR × LF
  if self.prev_gcb == CR && gcb == LF {
    return false
  }
  // GB4: (Control|CR|LF) ÷
  if self.prev_gcb == Control || self.prev_gcb == CR || self.prev_gcb == LF {
    return true
  }
  // GB5: ÷ (Control|CR|LF)
  if gcb == Control || gcb == CR || gcb == LF {
    return true
  }
  // GB6: L × (L|V|LV|LVT)
  if self.prev_gcb == L && (gcb == L || gcb == V || gcb == LV || gcb == LVT) {
    return false
  }
  // GB7: (LV|V) × (V|T)
  if (self.prev_gcb == LV || self.prev_gcb == V) && (gcb == V || gcb == T) {
    return false
  }
  // GB8: (LVT|T) × T
  if (self.prev_gcb == LVT || self.prev_gcb == T) && gcb == T {
    return false
  }
  // GB9: × (Extend|ZWJ)
  if gcb == Extend || gcb == ZWJ {
    return false
  }
  // GB9a: × SpacingMark
  if gcb == SpacingMark {
    return false
  }
  // GB9b: Prepend ×
  if self.prev_gcb == Prepend {
    return false
  }
  // GB9c: \p{InCB=Consonant} [Extend|Linker]* Linker [Extend|Linker]* × \p{InCB=Consonant}
  if self.incb == IcsLinker && icb == IcbConsonant {
    return false
  }
  // GB11: \p{Extended_Pictographic} Extend* ZWJ × \p{Extended_Pictographic}
  if self.ep == EpC && is_ep {
    return false
  }
  // GB12/13: pair-bond Regional_Indicators
  if self.ri_odd && gcb == RI {
    return false
  }
  // GB999: default break
  true
}

///|
/// All grapheme-cluster boundaries in `text`, sorted ascending.
///
/// First element is always `0`; last is always `text.length()`. For empty
/// text, returns `[0]` (single boundary).
pub fn grapheme_boundaries(text : String) -> Array[Int] {
  let out : Array[Int] = []
  out.push(0)
  let len = text.length()
  if len == 0 {
    return out
  }
  let (cp0, init_i) = decode_codepoint_at(text, 0)
  let mut i = init_i
  let mut state = State::start().advance(
    gcb_of(cp0),
    is_extended_pictographic(cp0),
    incb_of(cp0),
  )
  while i < len {
    let (cp, next_i) = decode_codepoint_at(text, i)
    let g = gcb_of(cp)
    let ep = is_extended_pictographic(cp)
    let ic = incb_of(cp)
    if state.break_before(g, ep, ic) {
      out.push(i)
    }
    state = state.advance(g, ep, ic)
    i = next_i
  }
  out.push(len)
  out
}

///|
/// Iterate UTF-16 (start, end) ranges, one per grapheme cluster.
///
/// Empty string yields zero items.
pub fn grapheme_clusters(text : String) -> Iter[(Int, Int)] {
  let bs = grapheme_boundaries(text)
  let mut idx = 0
  Iter::new(fn() {
    if idx + 1 >= bs.length() {
      None
    } else {
      let pair = (bs[idx], bs[idx + 1])
      idx = idx + 1
      Some(pair)
    }
  })
}

///|
/// Smallest grapheme-cluster boundary `>= pos`.
///
/// Returns `0` if `pos <= 0`. Returns `text.length()` if
/// `pos >= text.length()`. Accepts any `Int`, including positions inside
/// surrogate pairs and inside multi-codepoint clusters; never aborts.
///
/// Semantically: when `pos` is a boundary, returns `pos`. When `pos` is
/// strictly inside a cluster (mid-codepoint or mid-multi-codepoint
/// cluster), returns the cluster's end.
///
/// **Cost: O(n).** Each call rebuilds the full boundary array via
/// `grapheme_boundaries(text)`. A tight loop calling this `n` times over
/// the same string is therefore O(n²) — for hot paths over long strings,
/// materialise `grapheme_boundaries(text)` once and binary-search instead.
pub fn next_grapheme_boundary(text : String, pos : Int) -> Int {
  let len = text.length()
  if pos <= 0 {
    return 0
  }
  if pos >= len {
    return len
  }
  let bs = grapheme_boundaries(text)
  // Linear scan; small in practice. Could binary-search if hot.
  for b in bs {
    if b >= pos {
      return b
    }
  }
  len
}

///|
/// Largest grapheme-cluster boundary `<= pos`.
///
/// Returns `0` if `pos <= 0`. Returns `text.length()` if
/// `pos >= text.length()`. Same offset-tolerance contract as
/// `next_grapheme_boundary`. Same O(n) per-call cost — see the note on
/// `next_grapheme_boundary` for the materialise-once escape hatch.
pub fn prev_grapheme_boundary(text : String, pos : Int) -> Int {
  let len = text.length()
  if pos <= 0 {
    return 0
  }
  if pos >= len {
    return len
  }
  let bs = grapheme_boundaries(text)
  let mut last = 0
  for b in bs {
    if b > pos {
      return last
    }
    last = b
  }
  last
}

///|
/// True iff `pos` is a grapheme-cluster boundary in `text`.
///
/// Endpoints `0` and `text.length()` are always boundaries. Positions
/// inside surrogate pairs and inside multi-codepoint clusters are never
/// boundaries.
pub fn is_grapheme_boundary(text : String, pos : Int) -> Bool {
  let len = text.length()
  if pos <= 0 || pos >= len {
    return true
  }
  if is_trailing_surrogate_at(text, pos) {
    return false
  }
  let bs = grapheme_boundaries(text)
  for b in bs {
    if b == pos {
      return true
    }
    if b > pos {
      return false
    }
  }
  false
}
