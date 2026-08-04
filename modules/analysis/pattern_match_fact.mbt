///|
pub(all) struct PatternMatchFact {
  snapshot : SourceSnapshot
  from : Int // UTF-16 code unit offset
  to : Int // UTF-16 code unit offset
  pattern_id : String
  captures : Map[String, (Int, Int)]
} derive(@debug.Debug)

///|
pub fn PatternMatchFact::PatternMatchFact(
  snapshot~ : SourceSnapshot,
  from~ : Int,
  to~ : Int,
  pattern_id~ : String,
  captures~ : Map[String, (Int, Int)],
) -> PatternMatchFact {
  { snapshot, from, to, pattern_id, captures }
}

///|
pub fn PatternMatchFact::is_current(
  self : PatternMatchFact,
  current : SourceSnapshot,
) -> Bool {
  self.snapshot.matches(current)
}
