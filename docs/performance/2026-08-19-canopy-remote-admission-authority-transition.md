# Canopy remote-admission authority transition

- **Date:** 2026-08-19
- **Canopy measurement base:** `dbff0651bf3004e65dc194a5c37e39558805f835` plus the uncommitted #1281 Canopy change
- **event-graph-walker:** `31fb57b4dc9e423a94dda15a42bfbdcbd7c103e6`
- **Issue:** [Canopy #1281](https://github.com/dowdiness/canopy/issues/1281)
- **Baseline:** [Remote-admission phase attribution](2026-08-18-canopy-remote-admission-phase-attribution.md)

## Decision

Canopy now consumes the event-graph-walker authority-owned admission transition instead
of materializing complete authority text before and after ordinary warm remote admission.
Exact scalar effects are prepared against the parser-held source and committed through the
existing cursor, parser, projection-identity, hint, and observation machinery. Explicit
`SnapshotRequired` and `Unavailable` outcomes retain coherent fallback and fail-closed
behavior.

Decision record:

- No ADR needed: this is the accepted #1281 follow-up under the existing authority and
  projection-publication decisions; it changes no Canopy public interface, wire format, or
  archive format.

## Correctness mechanism

The remote admission seam has one outcome-driven flow:

1. event-graph-walker admits the message and returns an opaque transition;
2. `Exact` effects are applied sequentially to the parser-held source without authority
   text reads;
3. Canopy converts scalar positions to UTF-16, then atomically settles cursor, peer cursor,
   parser, projection identity, and hint state;
4. `SnapshotRequired` reads one coherent post-admission snapshot;
5. `Unavailable` reads no snapshot and performs no reconciliation;
6. `finish()` returns the existing `SyncReport` or surfaces the stored committed error.

Detector-backed tests prove zero authority reads on the ordinary exact path, one read on
snapshot fallback, and zero reads on unavailable outcomes. End-to-end tests cover exact,
duplicate-only, pending-only, dependency-drain, source-equal, snapshot-required,
unavailable, partial-error, parser-failure, UTF-16 cursor, peer-cursor, identity-hint, and
observation behavior.

## Harness

Native release measurements use three independent processes for every mode and matrix
cell. Each fixture:

- creates exactly $H=0/1k/10k/100k$ resident operations in a raw `TextState`;
- independently fixes visible length at $L=0/2k/10k/50k$ UTF-16 units;
- hydrates the target authority with expanded setup-only limits and coherently seeds its
  parser outside the clocks;
- admits one new operation through the production `SyncEditor` path;
- checks the report count and source convergence after measurement.

Segmented and whole-call modes use equivalent fresh-process fixtures. This avoids retaining
two $H=100000$ editor/parser graphs in one process. Their medians are therefore controls,
not additive allocator measurements.

| Clock | Included work |
|---|---|
| transition | `AuthorityCore::admit_transition_with_tracking` |
| preparation | parser-source read, exact-effect application, scalar-to-UTF-16 edit preparation |
| reconciliation | prepared settlement and transition `finish()` |
| whole call | `SyncEditor::admit`, including method-exit work |

## Native release matrix

Medians in microseconds.

| H | L | transition | preparation | reconciliation | whole call |
|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 34.086 | 3.074 | 19.492 | 72.481 |
| 1,000 | 0 | 49.644 | 6.834 | 26.284 | 86.507 |
| 10,000 | 0 | 82.471 | 7.516 | 28.337 | 137.071 |
| 100,000 | 0 | 125.175 | 7.649 | 31.665 | 159.688 |
| 100,000 | 2,000 | 1,237.820 | 20.813 | 36.284 | 1,516.212 |
| 100,000 | 10,000 | 1,775.702 | 18.344 | 59.984 | 1,433.209 |
| 100,000 | 50,000 | 820.830 | 45.718 | 118.939 | 1,292.603 |

At $L=0$, increasing $H$ from 0 to 100k raises the whole call from 72.481 µs
to 159.688 µs. The removed post-admission snapshot previously reached 38,311.256 µs
at $H=100k,L=0$ before method-exit work.

At fixed $H=100k$, preparation remains at or below 45.718 µs and reconciliation remains
at or below 118.939 µs. Transition production is the largest named phase in the visible-text
cells. Its non-monotonic values across $L$ do not establish a visible-length complexity law;
the matrix identifies the remaining phase, not a new optimization target.

## Baseline comparison

For $H=100k,L=0$, medians in microseconds:

| Measurement | Baseline | #1281 |
|---|---:|---:|
| direct public whole call | 176,264.607 | 159.688 |
| post-admission complete snapshot / exact preparation | 38,311.256 | 7.649 |
| parser/projection reconciliation | 48.293 | 31.665 |

The native whole-call ratio is approximately $1104\times$. This supports the native
mechanism claim that removing full snapshot construction and lifetime cleanup removes the
measured history-shaped cost. It is not a cross-runtime or end-user speedup claim: no JS or
wasm-gc end-to-end matrix was run, and MoonBench exposes no allocator counter.

## Reproduction

```sh
rtk moon check modules/canopy/editor
rtk moon bench --target native --release \
  -p dowdiness/canopy/editor \
  -f sync_editor_remote_admission_benchmark_wbtest.mbt \
  -i <0..13>
```

Run every index in three fresh processes. Indices 0–6 are whole-call controls; indices
7–13 are segmented phase measurements in the same matrix order.

## Evidence

- [Raw samples, medians, provenance, clock definitions, and limitations](../evidence/2026-08-19-canopy-remote-admission-authority-transition.json)
- [Baseline report](2026-08-18-canopy-remote-admission-phase-attribution.md)
- [Baseline raw evidence](../evidence/2026-08-18-canopy-remote-admission-phase-attribution.json)
