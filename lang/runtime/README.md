# lang/runtime

Generic companion runtime — Tier 2 language SPI
(`docs/decisions/2026-06-11-library-api-boundary.md`). Extracted in
architecture-redesign stage S3
(`docs/plans/2026-06-11-s3-lang-runtime-extraction.md`).

A `LanguageSpec[T, Op]` bundles, per language family, the closures that
differ between languages:

- `make_parser` — grammar-specific parser construction
- `build_memos` — the 3-memo projection pipeline (ProjNode, registry, SourceMap)
- `compute_edit` — structural op → span-level text edits + focus hint
- `describe_op` / `no_edit_policy` — how an unhandled op is reported
  (JSON errors; Markdown no-ops)

The machinery that does NOT differ lives here once: `new_editor` (SyncEditor
construction via the generic 3-memo pipeline) and `apply_edit` (the
structural-edit bridge: compute spans → `apply_span_edits` → cursor per
FocusHint).

Records over traits: MoonBit traits are Self-based without type parameters,
and the orphan rule blocks downstream impls. Closure fields also discharge
per-language bounds (`Eq`, `Show`) at construction time, so the record stays
unbounded. Per-instance capabilities (e.g. lambda's eval/semantic closures
capturing instance memos) are passed to `new_editor`, not stored in the spec.

Dispatch cost: benchmarked free (S3 gate,
`lang/json/companion/dispatch_benchmark.mbt`) — capability-record indirection
is sub-ns/call against a ~3 ms keystroke pipeline, on both wasm-gc and js.
