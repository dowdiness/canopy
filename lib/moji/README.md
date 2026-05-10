# moji

UAX #29 grapheme-cluster and word-boundary segmentation for [MoonBit](https://www.moonbitlang.com/).

`moji` provides the minimum API surface canopy's editor needs to make
UTF-16 text positions grapheme-aware. Positions are UTF-16 code units
throughout — matching MoonBit `String[Int]` indexing and CodeMirror 6's
wire convention.

## Status

Early — scaffolded for canopy issue [#250]. The public API is being
filled in by phase per the [moji API spec][spec].

[#250]: https://github.com/dowdiness/canopy/issues/250
[spec]: https://github.com/dowdiness/canopy/blob/main/docs/plans/2026-05-10-moji-api-spec.md

## Planned API

```moonbit
pub fn prev_grapheme_boundary(text : String, pos : Int) -> Int  // at-or-before
pub fn next_grapheme_boundary(text : String, pos : Int) -> Int  // at-or-after
pub fn prev_word_boundary(text : String, pos : Int) -> Int
pub fn next_word_boundary(text : String, pos : Int) -> Int

pub fn is_grapheme_boundary(text : String, pos : Int) -> Bool
pub fn grapheme_clusters(text : String) -> Iter[(Int, Int)]
```

## Out of scope

Normalization, bidi, casing, display width, line/sentence boundaries,
script detection, collation, well-formedness validation, JS bindings,
CRDT position conversion. See [spec §3][spec].
