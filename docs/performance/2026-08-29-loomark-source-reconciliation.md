# Loomark Source reconciliation characterization

**Date:** 2026-08-29

**Issue:** [#1303](https://github.com/dowdiness/canopy/issues/1303)

## Question

Loomark now scans independently authoritative Source records and rebuilds a
derived Catalog when the application opens. This characterization separates
browser cursor cost from Source decoding, Markdown name derivation, Catalog
comparison, and complete pure reconciliation. It establishes evidence; it does
not propose an optimization.

## Workloads

The MoonBit JS release benchmarks use 10 and 100 small Markdown Sources and a
1,000-Source mix in which every hundredth Source contains 256 representative
Markdown paragraphs. Every Source has an ATX H1 and the complete-reconciliation
cases include a current 1,000-entry Catalog.

The production Chromium measurement stores the same counts under
`source/v1/<document-id>`. Every hundredth value contains a larger Markdown
body. It records the median of five complete `openCursor()` scans after the
fixture repository is quiescent.

## Results

### MoonBit JS release

Command:

```bash
cd apps/loomark
NEW_MOON_MOD=0 moon bench internal/source_repository --target js --release
```

| Operation | Workload | Mean |
| --- | --- | ---: |
| Complete reconciliation | 10 small Sources | 149.50 µs |
| Complete reconciliation | 100 small Sources | 1.50 ms |
| Complete reconciliation | 1,000 mixed Sources | 42.48 ms |
| Strict Source decode | 1,000 mixed Sources | 1.68 ms |
| ATX H1 name derivation | 1,000 mixed Sources | 35.50 ms |
| Catalog decode and equality | 1,000 entries | 700.31 µs |

### Production Chromium IndexedDB

Command:

```bash
./scripts/test-loomark-standalone-e2e.sh
```

| Cursor workload | Median |
| --- | ---: |
| 10 Sources | 1.500 ms |
| 100 Sources | 2.900 ms |
| 1,000 Sources | 12.600 ms |

## Interpretation

At 1,000 mixed Sources, Markdown name derivation accounts for most pure
reconciliation time. Strict JSON decoding and Catalog comparison are smaller.
The browser cursor scan is material but remains separate from the 42.48 ms pure
phase. All of this work occurs during repository open or `SaveRequested`, never
inside the Raw input task.

No hash, generation, cache authority, or handwritten heading scanner is added.
Future optimization requires a user-visible open-path target and a new profile;
these measurements alone do not justify increasing repository complexity.
