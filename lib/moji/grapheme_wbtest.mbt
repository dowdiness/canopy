// Inline grapheme-boundary fixtures from
// `docs/plans/2026-05-10-moji-api-spec.md` §4.1.
//
// These tests pin the canopy-side contract: every Unicode shape canopy
// cares about must produce the documented boundary set under Unicode 15.1.

///|
/// Helper: render a `grapheme_boundaries` result as a comma-separated
/// string for use with `inspect`.
fn boundaries_str(text : String) -> String {
  let bs = grapheme_boundaries(text)
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
test "GB §4.1 ASCII baseline" {
  inspect(boundaries_str("hello"), content="0,1,2,3,4,5")
}

///|
test "GB §4.1 BMP single (Hiragana)" {
  inspect(boundaries_str("あ"), content="0,1")
}

///|
test "GB §4.1 BMP single (CJK)" {
  inspect(boundaries_str("中"), content="0,1")
}

///|
test "GB §4.1 BMP combining mark binds to base" {
  // "e" + U+0301 COMBINING ACUTE ACCENT
  inspect(boundaries_str("e\u{0301}"), content="0,2")
}

///|
test "GB §4.1 precomposed equivalent (single codeunit)" {
  // U+00E9 LATIN SMALL LETTER E WITH ACUTE
  inspect(boundaries_str("é"), content="0,1")
}

///|
test "GB §4.1 non-BMP single (emoji)" {
  inspect(boundaries_str("😀"), content="0,2")
}

///|
test "GB §4.1 non-BMP single (CJK Ext B)" {
  // U+20BB7 — non-BMP CJK
  inspect(boundaries_str("𠮷"), content="0,2")
}

///|
test "GB §4.1 mixed (cluster boundaries skip surrogate interior)" {
  inspect(boundaries_str("a😀b"), content="0,1,3,4")
}

///|
test "GB §4.1 ZWJ family (man + ZWJ + woman + ZWJ + boy)" {
  // 👨‍👩‍👦 — three EP + two ZWJ — collapse into one cluster.
  inspect(boundaries_str("👨\u{200D}👩\u{200D}👦"), content="0,8")
}

///|
test "GB §4.1 skin-tone modifier" {
  // 👋 + Fitzpatrick Type-4
  inspect(boundaries_str("👋\u{1F3FD}"), content="0,4")
}

///|
test "GB §4.1 variation selector (heart + VS-16)" {
  inspect(boundaries_str("\u{2764}\u{FE0F}"), content="0,2")
}

///|
test "GB §4.1 RGI ZWJ profession (woman + skin tone + ZWJ + laptop)" {
  // 👩🏽‍💻
  inspect(boundaries_str("\u{1F469}\u{1F3FD}\u{200D}\u{1F4BB}"), content="0,7")
}

///|
test "GB §4.1 Regional Indicator (one flag)" {
  // 🇯🇵 — JP flag
  inspect(boundaries_str("\u{1F1EF}\u{1F1F5}"), content="0,4")
}

///|
test "GB §4.1 two adjacent flags" {
  // 🇯🇵🇺🇸 — JP + US
  inspect(
    boundaries_str("\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}"),
    content="0,4,8",
  )
}

///|
test "GB §4.1 Hangul jamo decomposed" {
  // L + V + T jamos compose into one syllable cluster.
  inspect(boundaries_str("\u{1100}\u{1161}\u{11A8}"), content="0,3")
}

///|
test "GB §4.1 Hangul precomposed syllable" {
  // 각 (U+AC01 — single precomposed LVT) — one cluster of 1 codeunit.
  inspect(boundaries_str("각"), content="0,1")
}

///|
test "GB §4.1 Indic virama conjunct (Devanagari)" {
  // क (U+0915 InCB=Consonant) + virama (U+094D InCB=Linker) + ष (U+0937
  // InCB=Consonant) → क्ष as one cluster per GB9c (Unicode 15.1).
  inspect(boundaries_str("\u{0915}\u{094D}\u{0937}"), content="0,3")
}

///|
test "GB §4.1 CRLF (one cluster)" {
  inspect(boundaries_str("a\r\nb"), content="0,1,3,4")
}

///|
test "GB §4.1 empty string" {
  inspect(boundaries_str(""), content="0")
}

///|
test "GB §4.1 leading combining mark (degenerate)" {
  // Combining mark with no base — boundary still after each codepoint
  // (combining mark stays attached to nothing, breaks before next char).
  inspect(boundaries_str("\u{0301}a"), content="0,1,2")
}

// ─── point-query semantics (Codex's offset-tolerance characterisation) ───

///|
test "next_grapheme_boundary on boundary returns pos" {
  // "a😀b": boundaries 0,1,3,4. next(text, 1) == 1.
  inspect(next_grapheme_boundary("a😀b", 1), content="1")
}

///|
test "next_grapheme_boundary mid-surrogate snaps forward" {
  // pos=2 lands inside the surrogate pair; next returns cluster end (3).
  inspect(next_grapheme_boundary("a😀b", 2), content="3")
}

///|
test "prev_grapheme_boundary on boundary returns pos" {
  inspect(prev_grapheme_boundary("a😀b", 3), content="3")
}

///|
test "prev_grapheme_boundary mid-surrogate snaps back" {
  // pos=2 inside surrogate pair; prev returns cluster start (1).
  inspect(prev_grapheme_boundary("a😀b", 2), content="1")
}

///|
test "is_grapheme_boundary endpoints" {
  inspect(is_grapheme_boundary("hello", 0), content="true")
  inspect(is_grapheme_boundary("hello", 5), content="true")
}

///|
test "is_grapheme_boundary mid-surrogate is false" {
  inspect(is_grapheme_boundary("a😀b", 2), content="false")
}

///|
test "is_grapheme_boundary mid-cluster is false" {
  // ZWJ family "👨‍👩‍👦" boundaries are 0,8 — anything in between is false.
  inspect(
    is_grapheme_boundary("👨\u{200D}👩\u{200D}👦", 4),
    content="false",
  )
}

///|
test "boundaries clamp out-of-range positions" {
  // pos < 0 → 0; pos > len → len. No abort.
  inspect(prev_grapheme_boundary("abc", -100), content="0")
  inspect(prev_grapheme_boundary("abc", 100), content="3")
  inspect(next_grapheme_boundary("abc", -100), content="0")
  inspect(next_grapheme_boundary("abc", 100), content="3")
}
