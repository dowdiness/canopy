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
NEW_MOON_MOD=0 moon bench --release --target js \
  -p dowdiness/loomark/app/internal/source_repository
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

## Normal-save preparation follow-up

Issue [#1347](https://github.com/dowdiness/canopy/issues/1347) later measured
selected 1 MiB normal saves and found complete Source encoding and repeated
Catalog name derivation on that path. A release-JavaScript benchmark rotates
eight distinct operands and retains every result.

| Operation | Workload | Previous mean | Current mean |
| --- | --- | ---: | ---: |
| Strict Source encode | 64 KiB | 0.614 ms | 38.97 µs |
| Strict Source encode | 256 KiB | 2.81 ms | 303.99 µs |
| Strict Source encode | 1 MiB | 50.78 ms | 1.12 ms |
| Accept Source with unchanged certified title | 1 MiB suffix edit | 58.68 ms | 2.10 ms |
| Accept Source after title change | 1 MiB | full derivation required | 49.84 ms |

The encoder keeps the exact two-field Source schema and strict decoder but uses
native JSON serialization in this JS-only package. Catalog reuse is deliberately
narrow: each save reparses only the previous first terminated line, then reuses
the name when the first direct Document child is an unchanged ATX H1 and both
parse diagnostics and CST error/incomplete metadata are empty. No certificate
is stored. Title changes, recovered headings, and all uncertified forms continue
through the existing complete parser.

Production Chromium then exercised 30 saves across three fresh launches per
fixture. Put and acknowledgment offsets include the 250 ms quiet interval.

| Fixture | Previous put p95 | Current put p95 | Previous ack p95 | Current ack p95 |
| --- | ---: | ---: | ---: | ---: |
| Practical 500-block Preview | 280.1 ms | 256.1 ms | 301.2 ms | 270.3 ms |
| 64 KiB Text | 260.4 ms | 256.1 ms | 269.9 ms | 268.7 ms |
| 256 KiB Text | 276.6 ms | 258.6 ms | 286.2 ms | 271.9 ms |
| 1 MiB Text | 354.9 ms | 267.1 ms | 368.5 ms | 292.2 ms |

The selected 1 MiB save-phase long task fell from 30/30 samples at 105 ms p95
to 0/30. A separate post-input long task remained in 30/30 samples and varied
by launch up to 230 ms p95; this change does not claim to make 1 MiB textarea
input frame-responsive.

Command:

```bash
NEW_MOON_MOD=0 moon bench --release --target js \
  -p dowdiness/loomark/app/internal/source_repository \
  -f source_preparation_benchmark_wbtest.mbt --no-parallelize
```

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
