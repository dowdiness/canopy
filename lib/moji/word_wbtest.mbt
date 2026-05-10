// Inline word-boundary fixtures from
// `docs/plans/2026-05-10-moji-api-spec.md` §4.2.
//
// These tests pin the canopy-side contract for raw UAX #29 word boundaries
// under Unicode 15.1.

///|
/// Helper: render a `word_boundaries` result as a comma-separated string for
/// use with `inspect`.
fn word_boundaries_str(text : String) -> String {
  let bs = word_boundaries(text)
  let buf = StringBuilder::new()
  for i, b in bs {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string(b.to_string())
  }
  buf.to_string()
}

///|
test "WB §4.2 Latin words" {
  inspect(word_boundaries_str("hello world"), content="0,5,6,11")
}

///|
test "WB §4.2 CJK" {
  inspect(word_boundaries_str("日本語"), content="0,1,2,3")
}

///|
test "WB §4.2 mixed script" {
  inspect(word_boundaries_str("hello 日本"), content="0,5,6,7,8")
}

///|
test "WB §4.2 apostrophe binds word" {
  inspect(word_boundaries_str("don't"), content="0,5")
}

///|
test "WB §4.2 numeric cluster" {
  inspect(word_boundaries_str("$3.14"), content="0,1,5")
}

///|
test "WB §4.2 Hangul precomposed syllable run" {
  // Unicode 15.1 marks precomposed Hangul syllables as ALetter, so WB5 joins
  // this run even though each syllable remains its own grapheme cluster.
  inspect(word_boundaries_str("안녕하세요"), content="0,5")
}

// ─── point-query semantics (same offset-tolerance contract as grapheme) ───

///|
test "next_word_boundary on boundary returns pos" {
  inspect(next_word_boundary("hello world", 5), content="5")
}

///|
test "next_word_boundary mid-surrogate snaps forward" {
  // "a😀b": word boundaries 0,1,3,4. pos=2 is inside the surrogate pair.
  inspect(next_word_boundary("a😀b", 2), content="3")
}

///|
test "next_word_boundary mid-word snaps forward" {
  inspect(next_word_boundary("don't", 2), content="5")
}

///|
test "prev_word_boundary on boundary returns pos" {
  inspect(prev_word_boundary("hello world", 6), content="6")
}

///|
test "prev_word_boundary mid-surrogate snaps back" {
  inspect(prev_word_boundary("a😀b", 2), content="1")
}

///|
test "prev_word_boundary mid-word snaps back" {
  inspect(prev_word_boundary("don't", 2), content="0")
}

///|
test "word boundaries clamp out-of-range positions" {
  inspect(prev_word_boundary("abc", -100), content="0")
  inspect(prev_word_boundary("abc", 100), content="3")
  inspect(next_word_boundary("abc", -100), content="0")
  inspect(next_word_boundary("abc", 100), content="3")
}
