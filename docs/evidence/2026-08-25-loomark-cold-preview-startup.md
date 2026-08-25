# Loomark cold Preview startup measurement

Issue: [#1369](https://github.com/dowdiness/canopy/issues/1369)

Decision: **`EXPECTED_COLD_START`**

## Question

Is the first incremental Preview update a repeatable one-time cold cost while later incremental updates stay within the 10 ms Preview-preparation budget?

## Boundary

The existing #1368 practical-corpus runner was temporarily adapted to PR #1370's production `TextArea` and shared `TextChange` boundary. No profiling module, public debug API, Worker, queue, artificial warm-up, or Chrome trace was added. The temporary Preview and runner changes were removed after collecting the raw samples; the retained repository change is evidence-only.

The runner measures the existing phases:

- Parser edit;
- semantic attachment read;
- typed Rabbita Html materialization; and
- after-render wall time, reported separately because it includes frame scheduling wait.

Initial Preview, the first incremental update, and later incremental updates are separate samples. The first update is not discarded.

## Known startup behavior

The owning Loom implementation confirms that startup is not comparable to a later incremental update:

- `deps/loom/loom/pipeline/parser.mbt` documents and implements `Parser::new` by running an initial full `parse()` before publishing the parser views.
- `deps/loom/examples/markdown/reactive_keyed_markdown_ir.mbt` constructs the keyed MarkdownIR graph and acquires a terminal `scope.watch(document)`. Watch acquisition primes that lazy graph.
- `deps/loom/incr/docs/concepts.mbt.md` documents derived values as lazy, cached computations.

The initial full Preview therefore owns parser construction, a full parse, attachment graph construction, and initial graph priming. The first later `apply_edit` is the first execution of the incremental invalidation/recompute path in the fresh JavaScript runtime. The measurement checks whether that one-time distinction is stable; it does not attempt to optimize expected startup.

## Environment

- Canopy base: `7a90813c741d3f3bdab60b54ea311b26a8a26fa8`
- Loom: `f3286da505dd1dde44c9d260416030912ff6c40b`
- Rabbita: `4352e69cfbd2d480f4634c7f1ddbdea523c4f91a`
- Moon: `0.1.20260819 (fc2a4ee)`
- Moon compiler: `v0.10.9+6e6c44045`
- Node.js: `v24.14.1`
- Chromium: `149.0.7827.55`
- Target: JavaScript release production build served as static Warren output
- Fixture: 250 units, 22,419 UTF-16 code units, 1,000 lines, approximately 500 Markdown blocks
- Matrix per launch: insertion, deletion, and replacement at beginning, middle, and end; five measured repetitions per scenario

## Results

Preparation is Parser edit + semantic read + typed Html materialization. Initial construction uses the corresponding Parser-construction phase instead of Parser edit.

| Fresh launch | Initial Preview preparation | Initial after-render wall time | First incremental preparation | Later median | Later p95 | Later maximum |
|---|---:|---:|---:|---:|---:|---:|
| 1 | 121.0 ms | 134.8 ms | 15.2 ms | 4.0 ms | 6.6 ms | 9.2 ms |
| 2 | 126.1 ms | 138.7 ms | 13.0 ms | 3.9 ms | 6.3 ms | 8.1 ms |
| 3 | 121.6 ms | 135.3 ms | 15.7 ms | 4.0 ms | 6.1 ms | 7.2 ms |

The pooled 132 later incremental samples measured:

- median: **4.0 ms**;
- p95: **6.4 ms**; and
- observed maximum: **9.2 ms**.

First incremental phase attribution was:

| Fresh launch | Parser edit | Semantic read | Typed Html | Preparation |
|---|---:|---:|---:|---:|
| 1 | 4.5 ms | 8.1 ms | 2.6 ms | 15.2 ms |
| 2 | 4.2 ms | 6.8 ms | 2.0 ms | 13.0 ms |
| 3 | 4.1 ms | 9.0 ms | 2.6 ms | 15.7 ms |

Every launch reproduced the same shape: one slower first incremental update, followed by later updates whose observed maximum remained below 10 ms. No repeated or unpredictable steady-state failure appeared.

## Decision

Select **`EXPECTED_COLD_START`**.

- Keep initial full Preview startup separate from incremental updates.
- Keep the first cold incremental update visible and separately reported.
- Apply the 10 ms Preview-preparation gate to later incremental updates after startup.
- Do not add trace collection, counterfactual experiments, artificial warm-up, or Parser optimization for this result.
- A small production Preview/Split plan may proceed from the standard Rabbita architecture and shared `TextChange` boundary.

Text input remains independent of Preview preparation; the existing Warren production suite continues to enforce the 10 ms Text input contract.

## Raw samples

- [`2026-08-25-loomark-cold-preview-run-1.json`](2026-08-25-loomark-cold-preview-run-1.json)
- [`2026-08-25-loomark-cold-preview-run-2.json`](2026-08-25-loomark-cold-preview-run-2.json)
- [`2026-08-25-loomark-cold-preview-run-3.json`](2026-08-25-loomark-cold-preview-run-3.json)
