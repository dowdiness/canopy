# P1.3 — Does the Term cutoff pay for itself?

**Question:** For the same trailing-whitespace edit and annotation root read,
does `query_eq` save total work compared with `query_always_changed` after
paying for Term extraction, structural equality, and dependency verification?
At what fixture size is the result visible?

**Verdict:** **NATIVE POSITIVE; JS LARGE POSITIVE / SMALL-MEDIUM NOT YET STABLE;
NO PRODUCTION SELECTION.**

This is a release microbenchmark, not an architecture change. The two graphs
share one Store, one Region, one `ProjectionCommit` Source, parser/projection,
SourceMap, Evaluation, AnnotationMap, edit workload, and consumer. The sole
variable is the Term selector constructor:

```text
baseline   Region::query_always_changed
candidate  Region::query_eq
```

Run both the behavioral gate and release benchmarks with:

```bash
./scripts/run-minimal-no-shadow-lambda-cutoff-benchmark.sh
```

To retain a new evidence set instead of using a temporary directory:

```bash
./scripts/run-minimal-no-shadow-lambda-cutoff-benchmark.sh \
  --record examples/spikes/minimal_no_shadow_lambda_projection/evidence/p1_3_cutoff_benchmark
```

## Scenario matrix

| Scenario | Definitions | Projected nodes | Source bytes | Baseline per edit | Candidate per edit |
|---|---:|---:|---:|---|---|
| small | 1 | 4 | 13 | Term recompute; Evaluation recompute | Term recompute + Eq; Evaluation green |
| medium | 32 | 128 | 553 | Term recompute; Evaluation recompute | Term recompute + Eq; Evaluation green |
| large | 128 | 512 | 2337 | Term recompute; Evaluation recompute | Term recompute + Eq; Evaluation green |

Each benchmark constructs and warms one graph outside the timed loop. Every
timed iteration toggles one trailing space, publishes one coherent commit, and
reads AnnotationMap. The source alternates between the same two states so an
iteration does not benchmark unbounded document growth. Counter guards require:

```text
baseline Evaluation compute_count > 1; green_verifications = 0
candidate Evaluation compute_count = 1; green_verifications > 0
```

Each size/policy first gets a separate preliminary invocation. It does not warm
the later process's JS JIT or runtime state: every recorded `moon bench` starts
a new process and performs its own ten intra-process batches. Measurement runs
two process-level cycles, `ABBA` followed by `BAAB`, where A is AlwaysChanged
and B is Eq cutoff. Adjacent AB/BA runs produce four paired deltas per target
and size.
Raw output, records, and summary are retained under
`evidence/p1_3_cutoff_benchmark/`.

## Counterbalanced end-to-end results

| Target | Fixture | Baseline median | Candidate median | Median paired delta | Paired range | Candidate wins |
|---|---|---:|---:|---:|---:|---:|
| native | small | 21.41 µs | 20.08 µs | -1.29 µs (-6.0%) | -2.07…-0.84 µs | 4/4 |
| native | medium | 538.74 µs | 496.12 µs | -45.45 µs (-8.4%) | -64.22…-16.02 µs | 4/4 |
| native | large | 2.405 ms | 2.215 ms | -0.235 ms (-9.8%) | -0.370…-0.180 ms | 4/4 |
| JS | small | 19.85 µs | 19.59 µs | -0.28 µs (-1.4%) | -1.32…+0.57 µs | 2/4 |
| JS | medium | 531.46 µs | 482.03 µs | -63.06 µs (-11.9%) | -122.95…+133.01 µs | 3/4 |
| JS | large | 2.470 ms | 2.210 ms | -0.240 ms (-9.7%) | -0.600…-0.050 ms | 4/4 |

All native paired deltas favor the candidate. JS large also favors it in every
pair. JS small and medium include sign reversals, so their crossover remains
unresolved. These samples support the verdict but do not select a universal
size threshold or production policy.

## Component scale check

Component benchmarks cycle across eight independently built operands instead of
repeating one hot object. They omit Query verification/recompute overhead and
must not be added together or used to explain the full end-to-end delta.

| Target | Fixture | Term structural Eq | `eval_term` | SourceMap build | AnnotationMap aggregation |
|---|---|---:|---:|---:|---:|
| native | small | 38 ns | 0.438 µs | 4.23 µs | 1.10 µs |
| native | medium | 0.907 µs | 24.96 µs | 149.54 µs | 32.95 µs |
| native | large | 5.03 µs | 287.84 µs | 744.51 µs | 233.16 µs |
| JS | small | 38 ns | 0.335 µs | 3.27 µs | 1.05 µs |
| JS | medium | 0.921 µs | 16.35 µs | 126.71 µs | 35.90 µs |
| JS | large | 4.15 µs | 149.94 µs | 625.57 µs | 224.83 µs |

Structural Eq is cheaper than `eval_term` in these isolated fixtures, consistent
with the candidate's mechanism. SourceMap and AnnotationMap remain substantial
common red-path costs. Component numbers are qualitative context only.

## What this establishes

```text
Native graph-level work avoidance       positive in measured fixtures
Term Eq versus eval_term cost           favorable in measured fixtures
Source count / owner graph              unchanged
Canopy-specific kernel fork             absent
General crossover threshold             not selected
JS large-fixture wall-clock direction    repeated positive
JS small/medium crossover                not stable
Allocation or retained-memory benefit   unmeasured
```

[P1_4_CUTOFF_MIXED_WORKLOAD.md](P1_4_CUTOFF_MIXED_WORKLOAD.md) measures the
semantic-changing overhead and a 50% mixed workload. P1.3 alone does not
authorize fingerprints, keyed subterm Queries, prefix-cache replacement, more
cutoffs, a production migration, #1236 work, or an ADR.
