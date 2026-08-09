# Loomark raw-input phase breakdown (2026-08-09)

> **Status:** measurement snapshot only. The temporary benchmark harness and
> prototype changes were removed. Existing private dev-host timing telemetry
> remains; standalone builds disable it. No optimization shipped from this
> investigation.

**Baseline HEAD:** `af0304979025e4e907f26b5130f031c170c7443d` (post-#1217)
**Document:** 250 Markdown blocks, 19,415 UTF-16 code units

## Environment and methodology

- Linux 6.18.33.2 WSL2, AMD Ryzen 7 6800H, Node v24.14.1
- Headless Chromium 149.0.7827.55 via Playwright 1.61.1
- MoonBit 0.1.20260713, JS release build
- Normal native-input timings include the existing 50 ms trailing debounce window; IME finalization is immediate
- 5 warmups then 50 samples per scenario unless noted

Phase timestamps were captured with the existing private telemetry probe in
`apps/loomark/internal/rabbita/raw_input_timing.mbt`. The probe records
`performance.now()` marks from the first native-input enqueue through render
and serializes durations (not absolute timestamps) through
`RawInputPhaseTiming::to_json`. It is deliberately private to the driver and is
disabled on the standalone path. Synchronous `beforeinput` duration was
measured separately by the temporary Playwright harness around
`dispatchEvent(new InputEvent("beforeinput", ...))`; it is not part of
`RawInputPhaseTiming`.

Wasm-GC comparison was unavailable: workspace compilation reaches
`modules/canopy/ephemeral/ephemeral_time_native.mbt`, whose `extern "c"` is
rejected by the wasm-gc backend. JS is Loomark's deployment target.

## Current post-#1217 input path

A collapsed middle insertion passes through these steps, each reconstructing or
re-scanning the selection:

1. **`beforeinput`** — the browser fires synchronously.
   `text_control_repair.mbt` constructs a validated `VersionedRawSelection`
   (two `@moji.is_grapheme_boundary` scans per `grapheme.mbt:257`).
2. **Normalization** — `raw_selection_transaction.mbt` revalidates the
   captured selection against the current canonical snapshot, validates the
   post-input caret and textarea value, computes a whole-text
   `@text_change.compute_text_change`, and builds the changed selection.
3. **Commit** — `sync_editor_text.mbt:397` (`apply_text_edit_exact`) checks
   both boundaries separately; `markdown/editor.mbt:1149` calls through from
   the Markdown editor.
4. **`resolve_applied_edit`** — `sync_editor_parser.mbt` computes a second
   whole-text diff to protect against CRDT placement divergence.
5. **Post-commit** — `raw_selection_transaction.mbt` computes and validates
   the resulting caret, scanning grapheme boundaries again.

Preview materialization, publish serialization, DOM offset mapping, and
line-ending normalization are not dominant at this document size.

## Scenario table — post-#1217 browser measurements

| Scenario | Samples | input→render p50/p95 | reduce p50/p95 | commit p50/p95 | Preview p50/p95 |
|---|---:|---:|---:|---:|---:|
| ASCII suffix | 50 | 80.3 / 83.7 | 20.9 / 22.6 | 7.4 / 10.5 | 0 / 0.1 |
| ASCII prefix, alternating char | 50 | 137.5 / 173.4 | 28.3 / 47.1 | 39.8 / 64.8 | 0 / 0.1 |
| ASCII middle insertion | 50 | 171.5 / 178.0 | 50.3 / 52.3 | 43.9 / 46.6 | 0 / 0 |
| ASCII middle replacement | 50 | 155.9 / 184.0 | 17.1 / 22.7 | 58.3 / 76.0 | 0 / 0.1 |
| ASCII middle deletion | 50 | 150.8 / 155.0 | 15.6 / 17.1 | 56.3 / 60.6 | 0 / 0.1 |
| Middle paste | 50 | 169.4 / 175.3 | 47.4 / 49.7 | 43.2 / 48.0 | 0 / 0 |
| Middle emoji | 30 | 167.6 / 172.6 | 47.2 / 50.9 | 42.5 / 45.2 | 0 / 0 |
| IME final commit | 30 | 118.6 / 121.2 | 48.1 / 49.2 | 42.5 / 45.8 | 0 / 0 |
| Middle + split Preview | 50 | 174.0 / 180.7 | 48.4 / 52.5 | 42.6 / 45.7 | 1.3 / 2.3 |
| Middle CRLF | 30 | 168.1 / 174.5 | 47.6 / 49.3 | 42.8 / 47.6 | 0 / 0.1 |
| Middle lone CR | 30 | 168.0 / 176.4 | 47.3 / 51.2 | 42.9 / 46.0 | 0 / 0 |

## Phase decomposition — middle insertion

`beforeinput` is synchronous and fires **before** `input_received_at`, so its
cost is outside the measured `input_to_render_ms` total.

| Phase | p50 | p95 |
|---|---:|---:|
| beforeinput (synchronous, outside total) | 11.1 ms | 11.7 ms |
| input→debounce | 50.2 ms | 50.3 ms |
| reduce | 50.3 ms | 52.3 ms |
| reduce→commit | 10.7 ms | 11.8 ms |
| commit | 43.9 ms | 46.6 ms |
| commit→publish | 15.9 ms | 18.0 ms |
| publish→render | 1.6 ms | 1.9 ms |
| **input→render (measured total)** | **171.5 ms** | **178.0 ms** |
| beforeinput + input→render (rough sum of medians, not a measured percentile) | ~182.6 ms | — |

Nested commit spans at p50: exact-boundary policy 10.7 ms; CRDT replace
0.2 ms (insertion) / 7.7 ms (replacement); local text-change propagation
23.9 ms; `actual_edit` diff inside that propagation 23.1 ms; parser apply
0.7 ms.

## Isolated microbenchmarks — scaled source sizes

JS release microbenchmarks used source lengths equivalent to approximately
25, 100, and 250 blocks. They confirm near-linear whole-document scans for
both grapheme checks and text diff:

| Operation | ~25-block size | ~100-block size | 250 blocks |
|---|---:|---:|---:|
| `@moji.is_grapheme_boundary` at middle | 0.479 ms | 1.94 ms | 4.54 ms |
| `@text_change.compute_text_change`, middle insert | 2.11 ms | 8.25 ms | 19.91 ms |

Additional 250-block measurements: collapsed `MarkdownDocumentUtf16Selection`
8.97 ms; LF textarea normalization 61.63 µs; CRLF normalization 114.18 µs;
source→DOM middle offset 31.85 µs; DOM→source middle offset 26.07 µs;
existing `commit_with_receipt` 46.15 ms mean; CRDT tail mutation pair 3.34 ms
mean; parser incremental edit pair 4.93 ms mean.

## Confirmed root cause

Every collapsed middle insertion repeats whole-document work across five
sites: beforeinput selection validation, normalization, commit boundary checks,
`resolve_applied_edit`, and post-commit caret construction. Each calls
`@moji.is_grapheme_boundary` or performs whole-document edit reconciliation
independently. For middle edits, `resolve_applied_edit` reaches
`@text_change.compute_text_change`; suffix edits can use the ASCII fast path in
`text_diff.mbt`. At 250 blocks the grapheme scan alone costs ~4.5 ms per call
and a non-fast-path text diff ~20 ms per call.

## Rejected prototype — selection reuse without revalidation

Removed the per-call grapheme revalidation by reusing the versioned selection
across normalization. Results on the 250-block benchmark:

| Scenario | Baseline p50 | Prototype p50 |
|---|---:|---:|
| Middle insertion | 171.5 ms | 138.0 ms |
| Middle replacement | 155.9 ms | 131.3 ms |

This prototype **failed** the test
`Raw selection is revalidated against the bound Session snapshot`
(MoonBit package tests: 96/97). Version and document-ID equality do not prove
that a selection was validated against the bound snapshot. This weakens an
explicit safety invariant and must not ship.

## Viable prototype — one boundary array per validation

Used the existing `@moji.grapheme_boundaries` function (`grapheme.mbt:145`,
returning `Array[Int]`) plus `Array::binary_search` to compute grapheme
boundaries once in each existing selection-constructor or exact-edit policy
check, then reuse that array for both endpoints. All revalidation retained.

| Scenario | Baseline p50/p95 | Prototype p50/p95 | Δ p50 |
|---|---:|---:|---:|
| Middle insertion input→render | 171.5 / 178.0 | 142.2 / 146.7 | −29.3 ms (−17.1%) |
| Middle replacement input→render | 155.9 / 184.0 | 126.9 / 142.1 | −29.0 ms (−18.6%) |
| Middle insertion beforeinput | 11.1 / 11.7 | 5.5 / 5.9 | −5.6 ms |

Phase-level reductions (middle insertion, p50): reduce 50.3→37.8 ms;
reduce→commit 10.7→5.2 ms; commit 43.9→36.8 ms; commit→publish 15.9→10.5 ms.

Prototype validation: affected MoonBit tests 175/175; Raw/composition dev-host
Playwright 46/46. This prototype is evidence for a follow-up implementation,
not retained code.

## Correctness finding — same-character-before-identical-character

A collapsed insertion of the same character immediately before that character
is silently rejected by the current pipeline:

- Canonical source: `x`; selection: `0:0`
- Native result: `xx`
- Observed after repair: `x` (unchanged); committed changes: 0; error: null

`compute_text_change("x", "xx")` picks the equally valid insertion at offset 1,
while the trusted `beforeinput` caret is offset 0. Normalization rejects the
mismatch. This is a separate correctness bug that needs fixing before
prefix/repeated-character workloads can be treated as complete.

## Recommendations

1. **Fix the same-character ambiguity** as a correctness issue. Make
   normalization selection-aware while preserving the trusted first
   `beforeinput` base and latest-result aggregation used for coalesced bursts.
2. **Implement the one-boundary-array-per-validation change** without removing
   either snapshot revalidation. Cover CRLF and lone-CR DOM↔canonical mapping,
   Unicode/grapheme boundaries, composition/IME finalization, stale input, and
   coalesced bursts in deterministic and browser tests.
3. **Re-run the 250-block/50-edit browser benchmark** after the implementation
   lands to confirm the projected ~17% improvement holds in-tree.
4. **Then investigate applied-edit reconciliation.** For middle and other
   non-fast-path edits, `resolve_applied_edit` recomputes the actual edit to
   protect against documented CRDT placement divergence. Preserve that guard
   or an equivalent check; do not remove it based only on aggregate timing.
5. **Keep the 50 ms debounce unchanged.** The trailing window is
   correctness-adjacent (`text_control_repair.mbt`,
   `RAW_INPUT_DEBOUNCE_MS`).

## Non-goals

- **No debounce shortening.** The 50 ms window is correctness-adjacent and
  must not be reduced independently of the input-coalescing contract.
- **No CodeMirror delta port.** Loomark uses native textarea input, not
  CodeMirror. This investigation does not apply to the CodeMirror-based ideal
  editor path.
- **No Preview optimization.** Preview materialization is not a dominant cost
  at p50 (0–2.3 ms across scenarios). Optimizing it would not move
  input→render.
