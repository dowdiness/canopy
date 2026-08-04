// Fixtures for the word-navigation policy (docs/plans/2026-07-05-word-navigation-policy.md).
// Expected values are hand-derived from each fixture's raw UAX #29 boundary
// list (see the segment tables in the design doc's test plan).

///|
test "basic words: right lands at word end, left at word start" {
  // "foo bar" — raw boundaries [0,3,4,7]; units foo(0,3) ws(3,4) bar(4,7)
  let t = "foo bar"
  inspect(next_word_stop(t, 0), content="3")
  inspect(next_word_stop(t, 1), content="3")
  inspect(next_word_stop(t, 3), content="7")
  inspect(next_word_stop(t, 4), content="7")
  inspect(next_word_stop(t, 7), content="7")
  inspect(prev_word_stop(t, 7), content="4")
  inspect(prev_word_stop(t, 5), content="4")
  inspect(prev_word_stop(t, 4), content="0")
  inspect(prev_word_stop(t, 3), content="0")
  inspect(prev_word_stop(t, 0), content="0")
}

///|
test "punctuation run is a single stop unit" {
  // "foo->bar" — raw [0,3,4,5,8]; '-' and '>' merge into Other(3,5)
  let t = "foo->bar"
  inspect(next_word_stop(t, 0), content="3")
  inspect(next_word_stop(t, 3), content="5")
  inspect(next_word_stop(t, 4), content="5")
  inspect(next_word_stop(t, 5), content="8")
  inspect(prev_word_stop(t, 8), content="5")
  inspect(prev_word_stop(t, 5), content="3")
  inspect(prev_word_stop(t, 4), content="3")
  inspect(prev_word_stop(t, 3), content="0")
}

///|
test "whitespace runs are skipped, never targets" {
  // "foo   bar" — raw [0,3,6,9]
  let t = "foo   bar"
  inspect(next_word_stop(t, 3), content="9")
  inspect(next_word_stop(t, 4), content="9")
  inspect(prev_word_stop(t, 6), content="0")
  inspect(prev_word_stop(t, 9), content="6")
  // tab has WB=Other but must classify as whitespace (Char::is_whitespace)
  inspect(next_word_stop("foo\tbar", 3), content="7")
  inspect(prev_word_stop("foo\tbar", 4), content="0")
  // newline
  inspect(next_word_stop("foo\nbar", 3), content="7")
  inspect(prev_word_stop("foo\nbar", 4), content="0")
}

///|
test "leading/trailing whitespace falls back to text edges" {
  // "  foo  " — raw [0,2,5,7]
  let t = "  foo  "
  inspect(prev_word_stop(t, 1), content="0")
  inspect(prev_word_stop(t, 2), content="0")
  inspect(prev_word_stop(t, 7), content="2")
  inspect(next_word_stop(t, 5), content="7")
  inspect(next_word_stop(t, 0), content="5")
}

///|
test "empty and all-whitespace text" {
  inspect(next_word_stop("", 0), content="0")
  inspect(prev_word_stop("", 0), content="0")
  inspect(next_word_stop("   ", 0), content="3")
  inspect(prev_word_stop("   ", 3), content="0")
}

///|
test "CJK Other runs merge into one stop unit" {
  // "日本語 test" — raw [0,1,2,3,4,8]; kanji merge to Other(0,3)
  let t = "日本語 test"
  inspect(next_word_stop(t, 0), content="3")
  inspect(next_word_stop(t, 1), content="3")
  inspect(next_word_stop(t, 3), content="8")
  inspect(prev_word_stop(t, 8), content="4")
  inspect(prev_word_stop(t, 4), content="0")
  // hiragana+kanji stretch = one unit spanning the whole text
  let u = "これは日本語です"
  inspect(next_word_stop(u, 0), content="8")
  inspect(prev_word_stop(u, 8), content="0")
  inspect(next_word_stop(u, 3), content="8")
  inspect(prev_word_stop(u, 3), content="0")
}

///|
test "katakana is WordLike; adjacent Word units do not merge" {
  // "abcカナ" — ALetter÷Katakana boundary; two Word units (0,3)(3,5)
  let t = "abcカナ"
  inspect(next_word_stop(t, 0), content="3")
  inspect(next_word_stop(t, 3), content="5")
  inspect(prev_word_stop(t, 5), content="3")
  inspect(prev_word_stop(t, 3), content="0")
}

///|
test "non-BMP offsets count UTF-16 code units" {
  // "𝔞𝔟 x" — U+1D51E/U+1D51F are ALetter, 2 code units each; raw [0,4,5,6]
  let t = "𝔞𝔟 x"
  inspect(next_word_stop(t, 0), content="4")
  inspect(prev_word_stop(t, 6), content="5")
  inspect(prev_word_stop(t, 4), content="0")
}

///|
test "emoji is an Other stop unit" {
  // "a 🙂 b" — units a(0,1) ws(1,2) emoji(2,4) ws(4,5) b(5,6)
  let t = "a 🙂 b"
  inspect(next_word_stop(t, 1), content="4")
  inspect(next_word_stop(t, 2), content="4")
  inspect(next_word_stop(t, 4), content="6")
  inspect(prev_word_stop(t, 5), content="2")
  inspect(prev_word_stop(t, 2), content="0")
}

///|
test "word boundary inside grapheme cluster is post-snapped" {
  // "\u{600}!" — U+0600 is WB=Numeric / GCB=Prepend: word boundary at 1
  // falls inside the single grapheme cluster (0,2). Landings must snap.
  let t = "\u{600}!"
  inspect(next_word_stop(t, 0), content="2")
  inspect(prev_word_stop(t, 2), content="0")
}

///|
test "default-ignorable chars never become stop targets" {
  // "\n\u{200E}a" — LRM (default-ignorable, WB=Format) leads its own raw
  // segment after a hard break; it must classify as skippable.
  let t = "\n\u{200E}a"
  inspect(next_word_stop(t, 0), content="3")
  inspect(prev_word_stop(t, 3), content="2")
  inspect(prev_word_stop(t, 2), content="0")
  // text-start LRM
  let u = "\u{200E}a"
  inspect(next_word_stop(u, 0), content="2")
  inspect(prev_word_stop(u, 2), content="1")
}
