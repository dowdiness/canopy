# Canopy remote-admission phase attribution

**Date:** 2026-08-18  
**Canopy baseline:** `5733710920facd17d87647be6096c5a34da39c5a`  
**event-graph-walker baseline:** `3640bfa314ca29c14146ceb8fe1ab49223578b70`  
**Parent:** [Canopy #1279](https://github.com/dowdiness/canopy/issues/1279)  
**Implementation follow-up:** [Canopy #1281](https://github.com/dowdiness/canopy/issues/1281)

## Decision

The dominant remaining native remote-admission work is the lifecycle of the complete
materialized-text snapshots taken around authority admission, not authority admission,
version maintenance, cursor adjustment, or parser/projection reconciliation itself.
Canopy #1281 owns replacing the pre/post snapshot pair with exact accepted text-effect
evidence at the remote-admission transition seam.

Production behavior remains unchanged in this characterization change. No ADR needed:
this report records measurements and files an implementation issue without changing a
public interface, runtime behavior, or an accepted ownership decision. Any new public
receipt or effect interface requires separate design review.

## Question

After the maintained-version cache fix, which `SyncEditor::admit_with_policy` phase
accounts for the remaining native latency as resident history $H$ and materialized
UTF-16 length $L$ vary independently?

## Harness

All cells use native release builds and three independent processes. Each fixture:

- admits exactly $H=0/1k/10k/100k$ resident operations;
- independently fixes materialized length at $L=0/2k/10k/50k$ UTF-16 units;
- primes the maintained version cache before the measured message;
- admits exactly one new operation;
- excludes source construction and history seeding from the measured transition;
- uses expanded private limits only for the characterization fixture.

The phase clocks cover:

| Phase | Work |
|---|---|
| `pre` | parser health, observer reentry guard, pending-transform taint |
| `v0` / `v1` | authority version reads before / after admission |
| `t0` / `t1` | complete authority text snapshots before / after admission |
| `authority` | `AuthorityCore::admit_with_tracking` |
| `observe` | authority-acceptance observation |
| `r0` | local cursor clamp |
| `r1` | peer cursor adjustment |
| `r2` | known-edit selection or fallback source diff |
| `r3` | parser/projection reconciliation |

A separate outer clock brackets the entire instrumented method. This control detects
work that occurs after the last inner phase, including implicit native scope-exit work.
MoonBench exposes no allocator counter, so this report makes no allocation claim and no
cross-runtime claim.

## Independent $H$ / $L$ matrix

Medians in milliseconds. `measured total` is the sum of the named inner phases.

| H | L | authority | post text `t1` | reconcile `r3` | measured total |
|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 0.024 | 0.003 | 0.018 | 0.046 |
| 1,000 | 0 | 0.034 | 0.110 | 0.029 | 0.173 |
| 10,000 | 0 | 0.058 | 1.453 | 0.032 | 1.544 |
| 100,000 | 0 | 0.077 | 38.311 | 0.048 | 38.438 |
| 100,000 | 2,000 | 1.628 | 44.676 | 1.388 | 47.695 |
| 100,000 | 10,000 | 1.356 | 52.278 | 7.079 | 60.727 |
| 100,000 | 50,000 | 0.580 | 138.774 | 37.442 | 176.859 |

At $L=0$, increasing $H$ from 0 to 100k raises `t1` from 0.003 ms to
38.311 ms while `r3` remains below 0.049 ms. This isolates retained-history work in
the post-admission text snapshot before parser reconciliation begins.

At fixed $H=100k$, increasing $L$ from 0 to 50k raises `t1` from 38.311 ms to
138.774 ms and `r3` from 0.048 ms to 37.442 ms. Parser/projection work becomes material
for large visible text, but the complete post-admission snapshot remains the largest
named phase in every measured $H=100k$ cell.

The pre-admission snapshot `t0` stays below 0.063 ms because the authority text cache is
already materialized by fixture seeding. Admission invalidates that cache; the first
post-admission `t1` read pays the rebuild.

## Whole-call control

For $H=100k$, $L=0$, and one incoming operation, medians in milliseconds:

| Measurement | Median |
|---|---:|
| ordinary public admission | 176.265 |
| whole instrumented method | 173.392 |
| sum of named phases in that method | 41.942 |
| measured unattributed residual | 131.449 |

The ordinary and instrumented whole-call medians agree within 1.7%, so the
instrumentation preserves the admission path at the scale under investigation. The
outer clock proves that 131.449 ms occurs after or between the named inner clocks.

The leading explanation is native scope-exit reference-count cleanup of the old/new
materialized snapshots and other retained transition values. This is an inference:
the residual is measured, but the runtime provides no allocator or destruction counter.
Canopy #1281 therefore requires a whole-call control after implementation; optimizing
only the timed `doc.text()` expression could leave the larger lifecycle cost intact.

## Attribution

`SyncEditor::admit_with_policy` currently performs:

1. read the old complete source snapshot;
2. admit the authority message;
3. read the new complete source snapshot;
4. compute or select an edit;
5. reconcile cursor, parser, and projection state;
6. release transition-local values when the method exits.

Authority admission is already sub-millisecond at $H=100k$, $L=0$. Maintained version
reads, acceptance observation, cursor work, and edit selection are microsecond-scale.
The remaining dominant seam is therefore Canopy's materialized-text snapshot lifecycle,
with parser/projection reconciliation a separate visible-text-scaled phase.

## Follow-up contract

Canopy #1281 must:

1. avoid materializing both complete pre- and post-admission text snapshots on the
   ordinary accepted-message path;
2. preserve complete, duplicate, pending, partial, dependency-drain, recovery, and
   source-equal semantics without caller-side authority prediction;
3. preserve cursor transforms, parser state, projection identity, and committed-error
   behavior;
4. retain an outer whole-call control so implicit destruction work remains visible;
5. re-run the independent $H/L$ matrix;
6. obtain JS or wasm-gc evidence before making a cross-runtime or end-user claim.

## Evidence

- [Raw samples, medians, provenance, phase definitions, and limitations](../evidence/2026-08-18-canopy-remote-admission-phase-attribution.json)
- [Prior maintained-version characterization](2026-08-18-canopy-post-admission-version-expansion.md)
- [Implementation follow-up #1281](https://github.com/dowdiness/canopy/issues/1281)
