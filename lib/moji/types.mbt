// Unicode property values used by UAX #29 grapheme segmentation.
//
// `GCB` is the `Grapheme_Cluster_Break` property. `InCB` is the
// `Indic_Conjunct_Break` derived property (Unicode 15.1+, used by GB9c).
// `Extended_Pictographic` is a separate binary flag (used by GB11) — not
// folded into `GCB`.

///|
pub enum GCB {
  Other
  CR
  LF
  Control
  Extend
  ZWJ
  RI
  Prepend
  SpacingMark
  L
  V
  T
  LV
  LVT
} derive(Eq)

///|
pub enum InCB {
  IcbNone
  IcbConsonant
  IcbExtend
  IcbLinker
} derive(Eq)
