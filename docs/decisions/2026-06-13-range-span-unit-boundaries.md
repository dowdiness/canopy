# Range/span unit boundaries

**Date:** 2026-06-13
**Status:** Accepted
**Closes:** GitHub issue #415 once the documentation slice lands
**Related:** GitHub issue #216 · PR #555 · [API position units](../development/API_REFERENCE.md#position-units) · [protocol unit table](../../protocol/README.md#position-and-offset-units)

## Why this record exists

Canopy has several range-shaped concepts: source-map ranges, protocol spans,
editor text edits, Loom/seam syntax offsets, and eg-walker text positions.
They are all small integers, but they do not count the same thing. PR #555
made this concrete by splitting a generic cursor intent into separate
`SetPmCursor(pm_tree_position)` and `SetDocCursor(doc_code_unit_offset)`
variants; a shared raw `Range[Int]` would recreate the same ambiguity for
spans.

We also checked `moonbitlang/core/range` as a possible common primitive. It is
not a range value type today: it exports `iter(from~, to~, step?, inclusive?)`
and a sealed `Step` trait. It has no `Range`/`Span` struct, endpoint accessors,
or unit semantics to reuse directly.

## Decision

Do **not** introduce a single shared Canopy `lib/range` primitive now, and do
not standardize on `moonbitlang/core/range` for spans.

Keep unit boundaries explicit:

| Layer / API | Representation today | Unit |
|---|---|---|
| `ProjNode.start` / `.end` | `Int` fields | UTF-16 code-unit source offsets, half-open `[start, end)` |
| `SourceMap` node and token ranges | `@loomcore.Range` | UTF-16 code-unit source offsets, half-open `[start, end)` |
| Loom/seam syntax nodes and tokens | `Int` offsets from syntax APIs | UTF-16 code-unit source offsets, half-open spans |
| `SyncEditor` cursor/splice APIs | `Int` | UTF-16 code-unit offsets; cursor-bearing paths snap or validate UAX #29 grapheme boundaries |
| eg-walker text facade | `@text.Pos` / `@text.Range` | item-space positions, after editor-side conversion from UTF-16 |
| `protocol` wire fields | JSON numbers / arrays | field-specific; usually UTF-16 document offsets, but PM cursor intents use ProseMirror tree positions |

When a boundary needs stronger safety, introduce a unit-specific wrapper such
as `DocCodeUnitOffset`, `DocCodeUnitRange`, `ItemOffset`, `ItemRange`, or
`PmTreePosition`. Prefer labeled constructors such as
`from_bounds(start~, end~)` and explicit adapters to existing representations.
Do not add a broad public `RangeLike` trait or generic `Range[T]` until there
is a demonstrated need that does not erase unit distinctions.

## Design rules for future range work

- Use unit-bearing type names at public or cross-package boundaries.
- Keep source/document spans half-open by default: `[start, end)`.
- Prefer labeled constructors over positional `new(3, 8)` when crossing a
  package boundary.
- Pin edge-case behavior in constructors or helpers: negative offsets,
  `end < start`, zero-length spans, overlap vs adjacency, deletion clamping,
  and UTF-16/grapheme-boundary validation.
- Keep protocol JSON shapes stable; decode into typed MoonBit wrappers only on
  the MoonBit side if a boundary warrants it.

## Consequences

- `@loomcore.Range` remains the current SourceMap/projection range type.
- `@text.Pos` / `@text.Range` remain separate eg-walker item-space types.
- Protocol fields remain plain JSON numbers, backed by explicit unit docs.
- A future MoonBit core first-class range type can be revisited only if Canopy
  can still encode unit distinctions around it.
