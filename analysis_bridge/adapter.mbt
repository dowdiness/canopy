///|
// A single match returned by ast-grep (from range.byteOffset in its JSON output).
// Using a named struct rather than a bare tuple keeps the call site self-documenting
// and is safe if this type is ever exposed across an FFI boundary.
pub(all) struct AstGrepMatch {
  byte_start : Int
  byte_end : Int
  pattern_id : String
} derive(@debug.Debug)

///|
pub fn AstGrepMatch::AstGrepMatch(
  byte_start~ : Int,
  byte_end~ : Int,
  pattern_id~ : String,
) -> AstGrepMatch {
  { byte_start, byte_end, pattern_id }
}

///|
// Converts ast-grep matches into PatternMatchFact values.
// byte offsets come from ast-grep's range.byteOffset and are converted to
// UTF-16 code units here at the adapter boundary.
pub fn from_ast_grep_matches(
  matches : Array[AstGrepMatch],
  source : String,
  snapshot : @facts.SourceSnapshot,
) -> Array[@facts.PatternMatchFact] {
  matches.map(fn(m) {
    @facts.PatternMatchFact::PatternMatchFact(
      snapshot~,
      from=@facts.byte_offset_to_utf16(source, m.byte_start),
      to=@facts.byte_offset_to_utf16(source, m.byte_end),
      pattern_id=m.pattern_id,
      captures=Map([]), // Phase 2 will populate from ast-grep's metaVariables
    )
  })
}
