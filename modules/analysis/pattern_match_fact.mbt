///|
#derive(@debug.Debug)
pub(all) struct PatternMatchFact {
  snapshot : SourceSnapshot
  from : Int32 // UTF-16 code unit offset
  to : Int32 // UTF-16 code unit offset
  pattern_id : String
  captures : Map[String, (Int32, Int32)]
}

///|
pub fn PatternMatchFact::PatternMatchFact(
  snapshot~ : SourceSnapshot,
  from~ : Int32,
  to~ : Int32,
  pattern_id~ : String,
  captures~ : Map[String, (Int32, Int32)],
) -> PatternMatchFact {
  { snapshot, from, to, pattern_id, captures, }
}

///|
pub fn PatternMatchFact::is_current(
  self : PatternMatchFact,
  current : SourceSnapshot,
) -> Bool {
  self.snapshot.matches(current)
}

///|
pub extend PatternMatchFact with @moonbitlang/core/debug.Debug::{to_repr}
