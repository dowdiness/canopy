# Canopy post-admission version expansion characterization

**Date:** 2026-08-18
**Canopy baseline:** `2f27a4d4b272423d3df432b744e413c8b12dd290`
**event-graph-walker baseline:** `9dee515f755a59f76bacab6ff582284ab1fbe7cf`
**Follow-up:** [event-graph-walker #123](https://github.com/dowdiness/event-graph-walker/issues/123)

## Decision

The next remote-admission performance prototype should maintain the Text version
cache from the committed operation receipt instead of rebuilding it from all
resident operations after every accepted message.

P3 removed history-dependent work from the message admission core, but Canopy's
`SyncEditor` immediately reads the authority version before and after admission.
The post-admission read observes the invalid cache and restores history-dependent
latency outside the P3 measurement boundary. This is an authority-transition
problem, not a parser, projection, transport, or incoming-message-size problem.

Keep production behavior unchanged in this characterization change. The prototype
belongs in event-graph-walker's Text admission ownership, where committed,
duplicate, pending, partial, and recovery outcomes are known. Do not add a Canopy
caller-side version prediction.

No ADR needed: this change records native characterization evidence and a prototype
gate without changing production behavior, public interfaces, or accepted ownership.
A future receipt or cache-maintenance contract that changes public semantics requires
its own design review and, if public, an ADR.

## Question

After P3 batch admission, does the first maintained-version read scale with incoming
message operations $M$ or resident history operations $H$, and does Canopy perform
that read in its real remote-admission transition?

## Harness

All cells use native release builds and three independent processes. The fixture:

- creates exactly $H=0/1k/10k/100k$ resident Text operations;
- alternates insert and delete, keeping materialized text at zero or one UTF-16 code
  unit so document length does not stand in for operation history;
- primes the maintained version cache after history admission;
- admits exactly $M=1/10/100$ new operations once;
- excludes fixture construction, history admission, and cache priming from inner
  clocks;
- uses expanded private limits only to admit the 100k-operation fixture.

Three lanes were measured:

1. Text `sync().apply(message)`;
2. Text `sync().apply(message)` followed by `version()` on a separate receiver;
3. full Canopy `SyncEditor::admit_with_limits(message)` through the public interface.

A fourth isolated control admits the message outside the clock and times only the
first invalid-cache `TextState::version()` read. This is the attribution lane. The
paired Text lane always runs apply-only before apply-plus-version, so its subtraction
can include GC and order effects and is supporting evidence only.

MoonBench exposes no allocator counter. This report makes no allocation claim and no
cross-runtime claim.

## Paired Text admission matrix

Medians in milliseconds:

| H | M | apply | apply + version |
|---:|---:|---:|---:|
| 0 | 1 | 0.015 | 0.015 |
| 0 | 10 | 0.077 | 0.077 |
| 0 | 100 | 0.739 | 0.772 |
| 1,000 | 1 | 0.396 | 0.479 |
| 1,000 | 10 | 0.594 | 0.547 |
| 1,000 | 100 | 1.251 | 1.368 |
| 10,000 | 1 | 6.916 | 12.649 |
| 10,000 | 10 | 6.529 | 12.973 |
| 10,000 | 100 | 8.342 | 14.711 |
| 100,000 | 1 | 123.319 | 226.709 |
| 100,000 | 10 | 115.882 | 216.234 |
| 100,000 | 100 | 116.073 | 217.215 |

At 10k and 100k history, the second lane adds an H-sized cost that changes little
with M. The 1k cells are within native process and GC noise and are not used for the
mechanism claim.

## Isolated invalid-cache version control

Medians in milliseconds:

| H | M | first post-admission `version()` |
|---:|---:|---:|
| 0 | 1 | 0.005 |
| 1,000 | 1 | 0.444 |
| 10,000 | 1 | 10.411 |
| 100,000 | 1 | 211.753 |
| 100,000 | 10 | 205.916 |
| 100,000 | 100 | 199.512 |

Increasing H from 0 to 100k raises the direct version read from 5.3 microseconds to
211.8 milliseconds. At H=100k, changing M by 100x leaves the median in the
199.5-211.8 ms band. The invalid-cache expansion is therefore history-bound, not
message-bound.

## Full Canopy admission

Medians in milliseconds:

| H | M | `SyncEditor::admit_with_limits` |
|---:|---:|---:|
| 0 | 1 | 0.020 |
| 0 | 10 | 0.088 |
| 0 | 100 | 0.804 |
| 1,000 | 1 | 0.392 |
| 1,000 | 10 | 0.449 |
| 1,000 | 100 | 1.304 |
| 10,000 | 1 | 6.282 |
| 10,000 | 10 | 6.906 |
| 10,000 | 100 | 6.667 |
| 100,000 | 1 | 126.340 |
| 100,000 | 10 | 125.746 |
| 100,000 | 100 | 126.656 |

The real Canopy transition reproduces the same shape: at H=100k the median is
approximately 126 ms for all three M values. Parser reconciliation operates on at
most one code unit in this fixture, so it cannot explain the history scaling.
Absolute values differ between lanes because each exercises a different amount of
admission, projection, allocation, and GC work; the shared H-scaling and M-invariance
are the claim.

## Source attribution

`SyncSession::apply_with_limits` invalidates `TextState.cached_version` whenever the
committed count is non-zero. `TextState::version()` then rebuilds the version from the
operation log.

Canopy's `SyncEditor::admit_with_policy` performs:

1. pre-admission `doc.version()`;
2. authority admission;
3. post-admission `doc.version()`;
4. authority/projection continuation and parser reconciliation.

The post-admission read is required for the existing transition comparison, so P3's
fast admission core is followed immediately by the full version expansion.

## Prototype gate

Prototype committed-operation cache maintenance inside event-graph-walker's Text
admission seam. Acceptance requires:

1. cache state equivalent to a fresh `Version::from_ops` reconstruction after
   complete, duplicate-only, pending-only, partial, dependency-drain, and recovery
   outcomes;
2. no caller prediction and no Canopy-only special case;
3. unchanged public `SyncReport` behavior unless a separately reviewed receipt
   contract is necessary;
4. direct-version and full-Canopy H/M matrices showing the post-admission version
   read no longer scales with H;
5. native plus JS or wasm-gc evidence before any cross-runtime or end-user speedup
   claim.

## Evidence

- [Raw samples, medians, provenance, and limitations](../evidence/2026-08-18-canopy-post-admission-version-characterization.json)
- [P3 Text admission cutover characterization](../../deps/event-graph-walker/docs/performance/2026-08-17-egw-p3-text-admission-cutover-native-characterization.md)
- [Version-cache maintenance follow-up](https://github.com/dowdiness/event-graph-walker/issues/123)
