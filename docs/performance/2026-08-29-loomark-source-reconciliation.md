# Loomark Source reconciliation characterization

**Date:** 2026-08-29

**Issue:** [#1303](https://github.com/dowdiness/canopy/issues/1303)

## Question

Loomark scans independently authoritative Source records and derives an
in-memory Catalog when the application opens. This characterization separates
browser cursor cost from Source decoding, Source encoding, Markdown name
derivation, complete pure reconciliation, one-entry Catalog transition, and
Source transaction completion. It establishes evidence; it does not propose an
optimization.

## Workloads

The MoonBit JS release benchmarks use 10 and 100 small Markdown Sources and a
1,000-Source mix in which every hundredth Source contains 256 representative
Markdown paragraphs. Every Source has an ATX H1. Complete reconciliation scans
only Source records and builds the Catalog in memory.

The production Chromium cursor measurement stores the same counts under
`source/v1/<document-id>`. Every hundredth value contains a larger Markdown
body. The Source-write measurement replaces one small Source and one Source
with a 1 MiB text value. Browser rows report the median of five completed
transactions after the fixture repository is quiescent.

## Results

### MoonBit JS release

Command:

```bash
cd apps/loomark
NEW_MOON_MOD=0 moon bench internal/source_repository --target js --release
```

| Operation | Workload | Mean |
| --- | --- | ---: |
| Complete reconciliation | 10 small Sources | 129.99 µs |
| Complete reconciliation | 100 small Sources | 1.31 ms |
| Complete reconciliation | 1,000 mixed Sources | 38.06 ms |
| Strict Source decode | 1,000 mixed Sources | 1.54 ms |
| Strict Source encode | 1,000 mixed Sources | 3.00 ms |
| ATX H1 name derivation | 1,000 mixed Sources | 31.33 ms |
| In-memory Catalog transition | replace 1 of 1,000 entries | 158.87 µs |

### Production Chromium IndexedDB

Command:

```bash
./scripts/test-loomark-standalone-e2e.sh
```

| Operation | Workload | Median |
| --- | --- | ---: |
| Cursor scan | 10 Sources | 1.300 ms |
| Cursor scan | 100 Sources | 2.700 ms |
| Cursor scan | 1,000 Sources | 12.900 ms |
| Source put through transaction completion | small Source | 0.400 ms |
| Source put through transaction completion | 1 MiB Source | 2.100 ms |

## Interpretation

At 1,000 mixed Sources, Markdown name derivation accounts for most pure
reconciliation time. Strict JSON decoding, encoding, and one-entry Catalog
transition are smaller. The browser cursor scan remains separate from the
38.06 ms pure phase. Normal save writes one Source record; it does not encode or
write a Catalog or touch unrelated Sources.

All complete-source work occurs during repository open or `SaveRequested`,
never inside the Raw input task. No hash, generation, persistent Catalog,
sidecar, index, or handwritten heading scanner is added. Future optimization
requires a user-visible open or partial-listing target and a new profile; these
measurements alone do not justify increasing repository complexity.
