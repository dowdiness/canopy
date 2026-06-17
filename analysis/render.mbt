///|
// A single entry for a match list UI widget — from/to for jump, pattern_id for label.
pub(all) struct MatchListEntry {
  from : Int
  to : Int
  pattern_id : String
} derive(@debug.Debug)

///|
pub fn facts_to_match_list(
  facts : Array[@facts.PatternMatchFact],
  snapshot : @facts.SourceSnapshot,
) -> Array[MatchListEntry] {
  facts
  .iter()
  .filter(fn(f) { f.is_current(snapshot) })
  .map(fn(f) { { from: f.from, to: f.to, pattern_id: f.pattern_id } })
  .collect()
}

///|
pub fn facts_to_decorations(
  facts : Array[@facts.PatternMatchFact],
  snapshot : @facts.SourceSnapshot,
) -> Array[@protocol.Decoration] {
  facts
  .iter()
  .filter(fn(f) { f.is_current(snapshot) })
  .map(fn(f) {
    @protocol.Decoration::Decoration(
      from=f.from,
      to=f.to,
      css_class="analysis-match pattern-" + f.pattern_id,
      data=f.pattern_id,
    )
  })
  .collect()
}
