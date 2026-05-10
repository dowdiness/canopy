// Codepoint → property lookups.
//
// Tables in `property_tables.mbt` are flat `Array[Int]` interval arrays
// `[s0, e0, s1, e1, ...]` (inclusive, sorted, non-overlapping). Lookup is
// binary search.

///|
fn in_range_table(table : Array[Int], cp : Int) -> Bool {
  let n = table.length() / 2
  if n == 0 {
    return false
  }
  // Find first range index `lo` with `table[2*lo] > cp`. Then candidate is
  // `(lo - 1)`, which has the largest start <= cp.
  let mut lo = 0
  let mut hi = n
  while lo < hi {
    let mid = (lo + hi) / 2
    if table[2 * mid] > cp {
      hi = mid
    } else {
      lo = mid + 1
    }
  }
  guard lo > 0 else { return false }
  let idx = (lo - 1) * 2
  cp <= table[idx + 1]
}

///|
/// `Grapheme_Cluster_Break` property of a codepoint.
///
/// Returns `Other` for codepoints not in any `GraphemeBreakProperty` range.
pub fn gcb_of(cp : Int) -> GCB {
  if in_range_table(table_cr, cp) {
    return CR
  }
  if in_range_table(table_lf, cp) {
    return LF
  }
  if in_range_table(table_control, cp) {
    return Control
  }
  if in_range_table(table_zwj, cp) {
    return ZWJ
  }
  if in_range_table(table_extend, cp) {
    return Extend
  }
  if in_range_table(table_regional_indicator, cp) {
    return RI
  }
  if in_range_table(table_prepend, cp) {
    return Prepend
  }
  if in_range_table(table_spacing_mark, cp) {
    return SpacingMark
  }
  if in_range_table(table_l, cp) {
    return L
  }
  if in_range_table(table_v, cp) {
    return V
  }
  if in_range_table(table_t, cp) {
    return T
  }
  if in_range_table(table_lv, cp) {
    return LV
  }
  if in_range_table(table_lvt, cp) {
    return LVT
  }
  Other
}

///|
/// True iff the codepoint has the `Extended_Pictographic` property.
pub fn is_extended_pictographic(cp : Int) -> Bool {
  in_range_table(table_extended_pictographic, cp)
}

///|
/// `Indic_Conjunct_Break` derived property (Unicode 15.1+).
pub fn incb_of(cp : Int) -> InCB {
  if in_range_table(table_incb_consonant, cp) {
    return IcbConsonant
  }
  if in_range_table(table_incb_linker, cp) {
    return IcbLinker
  }
  if in_range_table(table_incb_extend, cp) {
    return IcbExtend
  }
  IcbNone
}
