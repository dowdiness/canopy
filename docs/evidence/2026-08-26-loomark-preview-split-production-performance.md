# Loomark Preview and Split production performance

**Issue:** [#1372](https://github.com/dowdiness/canopy/issues/1372)

**Implementation commit:** `fee54528`

**Decision:** `STOP_REASSESS`

The production implementation passed its retained pure-renderer benchmark, but
later browser Preview preparation exceeded the 10 ms practical-corpus gate in
all three fresh launches. No optimization was added.

## Environment

- Date: 2026-08-26
- Chromium: 149.0.7827.55, headless
- Node.js: v24.14.1
- Target: JavaScript release build
- Browser launches: 3 fresh Chromium processes
- Practical fixture: 250 heading/paragraph units, approximately 500 Markdown
  blocks, 22,420 UTF-16 code units
- Later samples: 44 per launch, 132 total

Raw samples:

- [run 1](2026-08-26-loomark-preview-split-run-1.json)
- [run 2](2026-08-26-loomark-preview-split-run-2.json)
- [run 3](2026-08-26-loomark-preview-split-run-3.json)

## Method

The exact production renderer and Preview engine were built with temporary
`performance.measure` boundaries. The boundaries separated:

- initial Parser, attachment, semantic read, and typed-Html preparation;
- each committed Parser transition;
- later semantic read plus typed-Html preparation;
- semantic attachment read;
- typed-Html materialization;
- publication through Rabbita after-render; and
- input-to-visible DOM freshness observed by a `MutationObserver` in the
  measurement script.

The first incremental sample inserted text into heading 125. Later samples
alternated one exact `ReplaceRange` at paragraph 125 and waited for the expected
Preview DOM text after each change. The 50 ms product debounce is excluded from
`loomark-preview-refresh` and included in visible freshness.

The temporary performance marks were removed after collection. Production code
contains no profiling API or test-only Model state.

## Cold results

| Launch | Initial preparation | Initial typed Html | Initial after-render | Initial visible | First cold preparation | First cold typed Html | First cold after-render | First cold visible |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 128.7 ms | 7.9 ms | 12.8 ms | 157.6 ms | 16.6 ms | 5.4 ms | 4.7 ms | 77.6 ms |
| 2 | 133.1 ms | 12.0 ms | 20.4 ms | 162.5 ms | 12.5 ms | 5.3 ms | 6.8 ms | 76.0 ms |
| 3 | 122.0 ms | 10.7 ms | 12.7 ms | 147.0 ms | 14.8 ms | 7.9 ms | 4.2 ms | 76.0 ms |

Initial preparation remains a distinct cold-start product cost. The first cold
incremental sample is also reported separately and is not included in the later
gate.

## Later results

| Phase | Samples | Median | p95 | Maximum |
|---|---:|---:|---:|---:|
| Parser transition | 132 | 18.7 ms | 27.0 ms | 33.3 ms |
| Preview preparation | 132 | 8.5 ms | **12.9 ms** | **19.0 ms** |
| Semantic attachment read | 132 | 6.6 ms | 8.3 ms | 11.0 ms |
| Typed-Html materialization | 132 | 1.9 ms | 4.9 ms | 8.0 ms |
| Rabbita after-render | 132 | 3.8 ms | 16.9 ms | 20.3 ms |
| Input-to-visible freshness | 132 | 82.4 ms | 95.2 ms | 117.2 ms |

Per-launch Preview preparation:

| Launch | Median | p95 | Maximum |
|---|---:|---:|---:|
| 1 | 8.5 ms | 12.1 ms | 19.0 ms |
| 2 | 8.6 ms | 12.9 ms | 14.4 ms |
| 3 | 8.5 ms | 12.6 ms | 14.1 ms |

All three launches exceeded 10 ms at p95 and maximum. The failure is in later
Preview preparation, not only frame scheduling or visible freshness.

## Retained renderer benchmark

The release benchmark isolates pure `MarkdownIR -> typed Html` materialization:

| Fixture | Mean | Observed range |
|---|---:|---:|
| Practical 500 blocks | 2.95 ms | 2.89–3.06 ms |
| Scaling 2,500 blocks | 19.56 ms | 18.76–20.35 ms |

The 2,500-block result is scaling characterization and does not substitute for
the practical browser gate.

## Decision

The implementation does not satisfy #1372's later practical-corpus 10 ms gate.
Following the issue and implementation plan, work stops without adding a Worker,
virtualization, partial renderer, cache, artificial warm-up, or another Preview
pipeline. The implementation remains available on PR #1374 for reassessment;
it should not be presented as acceptance-complete until the performance policy
or implementation scope receives a new decision.
