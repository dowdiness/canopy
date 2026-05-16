# moji

UAX #29 grapheme-cluster and word-boundary segmentation for [MoonBit](https://www.moonbitlang.com/), targeting **Unicode 15.1**.

`moji` provides the minimum API surface canopy's editor needs to make
UTF-16 text positions grapheme-aware. Positions are UTF-16 code units
throughout — matching MoonBit `String[Int]` indexing and CodeMirror 6's
wire convention.

[#250]: https://github.com/dowdiness/canopy/issues/250
[#251]: https://github.com/dowdiness/canopy/pull/251
[spec]: https://github.com/dowdiness/canopy/blob/main/docs/plans/2026-05-10-moji-api-spec.md

## Status

Implemented in canopy [#251] from the original [#250] request; spec at
[`docs/plans/2026-05-10-moji-api-spec.md`][spec].

- **1187/1187** Unicode 15.1 `GraphemeBreakTest.txt` cases pass
- **1826/1826** Unicode 15.1 `WordBreakTest.txt` cases pass
- **41** inline §4.1 / §4.2 spec fixtures
- **43** total tests in the package

## Public API

```moonbit
// Grapheme cluster boundaries
pub fn prev_grapheme_boundary(text : String, pos : Int) -> Int  // at-or-before
pub fn next_grapheme_boundary(text : String, pos : Int) -> Int  // at-or-after
pub fn is_grapheme_boundary(text : String, pos : Int) -> Bool
pub fn grapheme_clusters(text : String) -> Iter[(Int, Int)]
pub fn grapheme_boundaries(text : String) -> Array[Int]

// Word boundaries
pub fn prev_word_boundary(text : String, pos : Int) -> Int
pub fn next_word_boundary(text : String, pos : Int) -> Int
pub fn word_boundaries(text : String) -> Array[Int]

// Property lookups (also public; useful for debugging segmentation)
pub fn gcb_of(cp : Int) -> GCB
pub fn wb_of(cp : Int) -> WB
pub fn is_extended_pictographic(cp : Int) -> Bool
pub fn is_default_ignorable_code_point(cp : Int) -> Bool
pub fn incb_of(cp : Int) -> InCB

// Named codepoint constants — see § "Named codepoint constants" below
pub const ZERO_WIDTH_SPACE : String  // U+200B
```

## Named codepoint constants

moji ships a named `pub const` for a specific Unicode codepoint only when
at least one of the following holds:

1. **External role.** A current non-moji consumer in the canopy workspace
   needs that exact scalar by role or name (not by property class). The
   consumer's call site is named in the constant's docstring.
2. **Public-API canonical value.** moji's own public API contract
   exposes that scalar as a canonical value — for example, as the
   documented return value of a function, or as the conventional
   sentinel for a result.

Appearing in moji's *internal* tests, conformance fixtures, or
property-predicate test inputs does **not** qualify. The rule defends
against opportunistic growth: every named codepoint constant is API
surface that consumers may end up depending on by name, so each new
entry needs a concrete justification.

Adding a constant outside these criteria requires opening an issue first.

Currently shipped:

- `ZERO_WIDTH_SPACE` — U+200B. Justification: canopy's markdown editor
  consumes this scalar by role as its empty-paragraph sentinel. Today
  the literal is hardcoded across `lang/markdown/edits/` and
  `lang/markdown/companion/`; a follow-up canopy package
  `lang/markdown/sentinel/` will alias this constant and route all
  consumers through it.

## Offset-tolerance contract

All `pos` arguments are UTF-16 code-unit offsets. Functions accept any
`Int`, including positions inside surrogate pairs and inside multi-
codepoint clusters. Out-of-range positions clamp to `[0, text.length()]`.
Functions never abort.

For `pos` strictly inside a cluster (mid-surrogate or mid-multi-codepoint
cluster):

- `next_grapheme_boundary` returns the cluster end.
- `prev_grapheme_boundary` returns the cluster start.
- `is_grapheme_boundary` returns `false`.

For `pos` exactly on a boundary, both `next` and `prev` return `pos`
unchanged.

## Performance characteristics

The current implementation prioritises correctness and code clarity over
peak throughput. Concrete characteristics callers should know:

- **`grapheme_boundaries(text)` and `word_boundaries(text)` are O(n)**
  — one forward walk over the codepoints with a constant-bounded state
  machine.
- **Point queries (`prev_/next_/is_*_boundary`) are O(n) per call** —
  they internally call `grapheme_boundaries(text)` (or its word
  counterpart) and scan the result. A tight loop calling
  `next_grapheme_boundary` `n` times over the same string therefore
  costs O(n²); for a long document, materialise `grapheme_boundaries`
  once and binary-search instead.
- **Per-codepoint property lookup is O(log m)** where `m` is the size
  of the largest property table (~400 ranges). Each `gcb_of` may
  consult up to 13 tables before falling through to `Other`. ASCII
  inputs are dominated by the first three lookups (CR / LF / Control).

These costs are acceptable for canopy's editor call sites (short
strings, single-shot queries on user mutation). They would not be
acceptable for streaming a multi-MB document one boundary at a time —
in that scenario, materialise the boundary array once.

## Out of scope

Normalization, bidi, casing, display width, line/sentence boundaries,
script detection, collation, well-formedness validation, JS bindings,
CRDT position conversion (UTF-16 ↔ item-space is the caller's
responsibility — see [spec §0][spec]).

## Re-generating tables and tests

Property tables and the conformance test cases are generated from
vendored UCD 15.1 files under `testdata/`. To bump the Unicode version
or refresh after editing the generators:

```bash
cd lib/moji
python3 scripts/gen_property_tables.py     # → property_tables.mbt
python3 scripts/gen_break_test_cases.py    # → graphemebreaktest_cases_wbtest.mbt
                                           # + wordbreaktest_cases_wbtest.mbt
moon test --package dowdiness/moji         # 43 tests
```
