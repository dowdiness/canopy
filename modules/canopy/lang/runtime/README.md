# lang/runtime

Generic companion runtime — Tier 2 language SPI
(`docs/decisions/2026-06-11-library-api-boundary.md`). Extracted in
architecture-redesign stage S3
(`docs/plans/2026-06-11-s3-lang-runtime-extraction.md`).

A `Language[T, Op, E]` bundles, per language family, the closures that
differ between languages (ADR
`docs/decisions/2026-08-07-generic-language-spi-deepening.md`):

- `parse` — grammar-specific parser construction
- `project` — the 3-memo projection pipeline (ProjNode, registry, SourceMap)
  plus the language-owned extras value `E` (companion memos, semantic
  attachments; `Unit` for languages without extras)
- `edit` — structural op + `EditContext[T]` → `EditResult`
  (`Edits(edits, focus, hint?)` | `NoEdit`), raising structured
  `core.EditError`
- `capabilities` — view-pipeline closures built from the freshly constructed
  `E` (ordering: data before behavior, so no construction-time `Ref`
  side-channels)

The machinery that does NOT differ lives here once: `Language::build`
(SyncEditor construction returning `(SyncEditor[T], E)`) and
`Language::apply_edit` (the structural-edit bridge: guard projection → build
`EditContext` → `edit` port → `apply_span_edits` → cursor per `FocusHint`;
returns the applied `SpanEdit` patch trace and structured `EditError`).

Records over traits: MoonBit traits are Self-based without type parameters,
and the orphan rule blocks downstream impls. Closure fields also discharge
per-language bounds (`Eq`, `Show`) at construction time, so the record stays
unbounded. Per-instance capabilities (e.g. lambda's eval/semantic closures
capturing instance memos) are built by the `capabilities` closure from `E`,
not stored in the record.

Legacy: `LanguageSpec[T, Op]` (the pre-2026-08-07 SPI with string errors and
no extras) remains until all languages migrate; JSON and Markdown already use
`Language`. Do not build new languages on `LanguageSpec`. The superseded
2026-06-15 "Lambda edit bridge boundary" decision is recorded in
`docs/decisions/2026-08-07-generic-language-spi-deepening.md`.

Dispatch cost: benchmarked free (S3 gate,
`lang/json/companion/dispatch_benchmark.mbt`) — capability-record indirection
is sub-ns/call against a ~3 ms keystroke pipeline, on both wasm-gc and js.
