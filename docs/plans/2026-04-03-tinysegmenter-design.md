# TinySegmenter — Word-Level Tokenizer for Echo

**Status:** Approved
**Date:** 2026-04-03

## Goal

Add TinySegmenter (dictionary-free Japanese word segmenter) to the echo tokenizer package. Measure P@5 and MRR improvement over bigram baseline (P@5=0.44, MRR=0.81).

## What Changes

### New files in `echo/tokenizer/`

- `segment.mbt` — segmenter logic: `pub fn segment(String) -> Array[String]`
  - Character type classification (exact Unicode ranges from upstream JS)
  - Feature extraction: 42 table lookups per boundary
  - Boundary scoring: BIAS + sum of feature weights, split if score > 0
- `weights.mbt` — generated file, module-level `Map[String, Int]` initialized once (~4000 entries)
- `segment_wbtest.mbt` — unit tests

### Weight table initialization

The weight table must be initialized once at module load, not rebuilt per call. Use a module-level `let` binding:

```moonbit
let WEIGHTS : Map[String, Int] = {
  "BIAS": -332,
  "BC1:HH": 6,
  // ... ~4000 entries
}
```

### Weight generation

- `scripts/generate_weights.nu` — Nushell script
  - Reads original TinySegmenter JS source
  - Extracts ALL weight objects: BIAS, BC1, BC2, BC3, BP1, BP2, BQ1..BQ4, BW1..BW3, TC1..TC4, TQ1..TQ4, TW1..TW4, UC1..UC6, UQ1..UQ3, UP1..UP3, UW1..UW6
  - Flattens into prefixed keys: `"BC1:HH" => 6`
  - Emits `echo/tokenizer/weights.mbt`
  - Validation: script asserts extracted table count matches upstream (should be 30 tables + BIAS)

### Corpus tokenizer parameter

```moonbit
pub(all) struct Corpus {
  priv tokenize : (String) -> Array[String]  // new field
  priv mut next_id : Int
  priv doc_freq : Map[String, Int]
  priv posts : Array[Post]
}

pub fn Corpus::new(tokenize~ : (String) -> Array[String] = @tokenizer.bigram) -> Corpus
```

`add_post` and `query_text` use `(self.tokenize)(text)` instead of `@tokenizer.bigram(text)`.

### Testing

- Unit tests for `segment` with concrete fixtures:
  - `"今日はいい天気です"` → `["今日", "は", "いい", "天気", "です"]`
  - `"私の名前は田中です"` → `["私", "の", "名前", "は", "田中", "です"]`
  - `""` → `[]`
  - `"あ"` → `["あ"]`
  - Exact expected arrays verified against the reference JS implementation
- Eval tests: **two separate tests**, each with its own snapshots:
  - Existing bigram eval unchanged (P@5=0.44, MRR=0.81 baseline preserved)
  - New TinySegmenter eval using `Corpus::new(tokenize=@tokenizer.segment)` with same 30 fixtures from `make_fixture_corpus()`

### Corpus semantics and tokenizer behavior

Edge-case behavior is tokenizer-dependent:
- Bigram: single-char input → `[]` tokens → zero vector → no similarity
- TinySegmenter: single-char input → `["x"]` → one token → has a vector

Existing bigram-specific tests (e.g., "single char post has no similarity") remain in the bigram eval test. TinySegmenter eval tests assert TinySegmenter-specific behavior.

## Algorithm (Full Upstream Scoring)

For each character boundary position i in the input string:

1. **Pad** the string with boundary markers: `B3, B2, B1` prepended, `E1, E2, E3` appended (both chars and types)

2. **Classify** each character into a type using exact upstream ranges:
   - `H`: Kanji (U+4E00–U+9FA0, plus 々〆ヵヶ)
   - `I`: Hiragana (U+3041–U+3093)
   - `K`: Katakana (U+30A1–U+30F6, U+30FC, half-width U+FF71–U+FF9E)
   - `A`: ASCII letters (A-Z, a-z, U+FF41–U+FF5A, U+FF21–U+FF3A)
   - `N`: Digits (0-9, U+FF10–U+FF19)
   - `M`: Chinese numerals (一二三四五六七八九十百千万億兆)
   - `O`: Everything else

   Same BMP/UTF-16 assumption as bigram.

3. **Score** each boundary by summing weights from these tables (42 lookups total):
   ```
   score  = BIAS
   score += UP1[p1]  + UP2[p2]  + UP3[p3]           // unigram type pairs
   score += BP1[p1+p2] + BP2[p2+p3]                  // bigram type pairs
   score += UW1[w1] + UW2[w2] + UW3[w3] + UW4[w4] + UW5[w5] + UW6[w6]  // unigram chars
   score += BW1[w2+w3] + BW2[w3+w4] + BW3[w4+w5]    // bigram chars
   score += TW1[w1+w2+w3] + TW2[w2+w3+w4] + TW3[w3+w4+w5] + TW4[w4+w5+w6]  // trigram chars
   score += UC1[p1] + UC2[p2] + UC3[p3] + UC4[p4] + UC5[p5] + UC6[p6]  // unigram types
   score += BC1[p2+p3] + BC2[p3+p4] + BC3[p4+p5]     // bigram types
   score += TC1[p1+p2+p3] + TC2[p2+p3+p4] + TC3[p3+p4+p5] + TC4[p4+p5+p6]  // trigram types
   score += UQ1[p1+p2] + UQ2[p2+p3] + UQ3[p3+p4]     // conditional unigram
   score += BQ1[p2+p3+p4] + BQ2[p3+p4+p5]             // conditional bigram
   score += BQ3[p4+p5+p6] + BQ4[p5+p6+?]              // conditional bigram (cont.)
   score += TQ1[p2+p3+p4+p5] + TQ2[p3+p4+p5+p6]      // conditional trigram
   score += TQ3[...] + TQ4[...]                         // conditional trigram (cont.)
   ```
   Where w1..w6 = chars at positions i-3..i+2, p1..p6 = their types.
   Missing keys default to 0.

4. If **score > 0**, insert word boundary.

## Edge Cases

- Empty string → `[]`
- Single character → `["x"]` (one word, no boundary to evaluate)
- ASCII-only text → behavior follows TinySegmenter weights exactly (no extra heuristics)
- Mixed Japanese/ASCII → segmenter handles via character type features

## Success Criteria

P@5 > 0.44 on the 30-fixture eval.

## Out of Scope

- Custom training / weight retraining
- Streaming/incremental segmentation
- Handling surrogate pairs (same as bigram — BMP only)
- Blending strategy (follow-up experiment if TinySegmenter alone doesn't improve metrics)
