# Loomark post-commit persistence preparation characterization

**Date:** 2026-08-16
**Issue:** [#1244](https://github.com/dowdiness/canopy/issues/1244)
**Harness commit:** `f152a0c`
**Production baseline:** `6c7923232ffc68edcc84c75597f90dee6b37e4aa`

## Decision

Complete archive capture and JSON preparation dominate the 2,000-line middle-edit
response after the authority transition and before Preview materialization. Keep
production persistence unchanged in this characterization change. The next
prototype must target complete-replacement persistence preparation rather than
projection, Rabbita view materialization, DOM reconciliation, layout, or paint.

No new ADR needed: this change adds private measurement controls and retains the
accepted synchronous placement, archive schema, complete-replacement semantics,
and storage ordering. A checkpoint plus operation-tail design would change those
contracts and requires an ADR before implementation.

## Harness

The release-browser benchmark adds two private controls, both gated by the exact
`projection-benchmark=1` opt-in:

- `archive-persistence=0` disables archive preparation for a positive control;
- `persistence-trace=1` enables the existing bounded fixed-width numeric trace.

Production and malformed query values retain archive persistence and disable the
trace. The normal archive preparation path does not call an observer. Only the
trace-enabled path uses one fixed function observer.

The B-to-D interval is divided into these numeric milestones:

| Phase | Completed work |
|---|---|
| B | projection mirror synchronized |
| H1 | `commit_with_receipt` returned, including incremental receipt history |
| H2 | commit and persistence classification completed |
| H3 | complete archive preparation started |
| H4 | portable Markdown captured |
| H5 | complete history captured |
| H6-history | history JSON encoded |
| H6-envelope | archive envelope stringified |
| H7 | storage replacement command constructed |

Each measured browser scenario records the exact request IDs observed before and
after the scenario. Request attribution does not assume one request per scenario.

## 2,000-line positive control

Three isolated release-browser samples used synchronous projection and the same
middle native `insertText` edit.

| Archive persistence | End-to-end median | Samples |
|---|---:|---:|
| Enabled | 2,138.1 ms | 3 |
| Disabled | 254.4 ms | 3 |
| Difference | 1,883.7 ms | — |

Disabling preparation removes 88.1% of the measured median. This is a private
positive control, not a production proposal: authority mutation, projection,
Preview, and browser presentation remain active in both conditions.

## Enabled-path attribution

Median phase durations for the same middle edit:

| Interval | Median |
|---|---:|
| B → H1 incremental receipt history | 15.4 ms |
| H1 → H2 classification | 0.0 ms |
| H2 → H3 archive dispatch | 0.0 ms |
| H3 → H4 portable Markdown | 0.2 ms |
| H4 → H5 complete history export | 326.9 ms |
| H5 → H6-history history JSON | 806.7 ms |
| H6-history → H6-envelope envelope stringify | 652.0 ms |
| H6-envelope → H7 command construction | 0.1 ms |
| B → H7 total persistence preparation | 1,801.8 ms |

History JSON encoding and envelope stringify total 1,458.7 ms, 81.0% of B→H7.
Complete history export contributes another 326.9 ms. Incremental receipt history,
classification, portable Markdown capture, and command construction do not explain
the response.

## Trace control

With persistence disabled, the 2,000-line middle-edit median was 254.4 ms with
tracing and 253.5 ms without tracing, a 0.9 ms (0.35%) difference. All retained
trace-on runs were complete, non-empty, lossless, and contract-valid. The
trace-disabled evidence reports `enabled=false` and contains no phase entries.

Independent enabled-path runs varied more strongly with shared-runner load, so the
trace overhead claim is limited to the persistence-disabled control. Attribution
uses within-request timestamp differences rather than cross-run absolute latency.

## Isolated archive scaling

MoonBench reproduced the browser attribution without Rabbita, DOM, or presentation:

| Lines | Complete history export | History JSON encoding | Complete archive encoding |
|---:|---:|---:|---:|
| 2,000 | 273.91 ms | 694.40 ms | 1.15 s |
| 10,000 | 1.61 s | 3.80 s | 11.75 s |

Each completed cell is the mean of ten JS-release runs. The 50,000-line complete
history case did not finish MoonBench calibration within 900 seconds. The earlier
nine-case batch also exceeded 3,600 seconds. The 50,000-line JSON and complete
archive cases were not run individually afterward. Only the complete-history
case is a censored result; the other two have no reported latency.

The 2,000-line isolated values agree with the retained browser phases. The 10,000-line
results establish document-size scaling. Complete archive encoding includes
history JSON encoding and the outer envelope stringify; it is not an
envelope-only measurement.

## Consequences

1. Keep synchronous production projection placement.
2. Do not optimize Preview materialization, Rabbita VDOM diff, layout, or paint for
   this response problem.
3. Keep archive persistence enabled in production.
4. Prototype one persistence design only after preserving archive recovery,
   failure atomicity, and history durability invariants.
5. Compare a defer-and-coalesce causal prototype first; treat it as confirmation,
   not a final design, because a deferred multi-second main-thread task can still
   block the next input.
6. If the result confirms the attribution, design checkpoint plus ordered operation
   tail persistence and record the schema/recovery/compaction decision in an ADR.

## Evidence

- [Paired 2,000-line browser runs](../evidence/2026-08-16-loomark-persistence-2k-paired.json)
- [Trace-disabled control](../evidence/2026-08-16-loomark-persistence-trace-off.json)
- [Isolated archive scaling](../evidence/2026-08-16-loomark-archive-scaling.json)
- [Presentation characterization](2026-08-15-loomark-presentation-critical-path.md)
