# Loomark LocalText sustained-input prototype

**Date:** 2026-08-23

**Status:** throwaway performance evidence; no production persistence, undo, or collaboration contract is accepted

This branch inherits two explicitly named package-public repository functions
from the first LocalText prototype. That generated-interface drift makes the
branch intentionally non-mergeable; it is not a proposed production API.

## Question

Does synchronous full-history archive preparation displace the second and later
inputs after the first character has become visible?

The earlier four-clock experiment measured only one edit. It proved that
LocalText reduces reopen and durable completion, but it could not observe work
that blocks a later browser input.

## Protocol

The experiment keeps the same `MarkdownEditor`, parser, projection, commit,
persistence queue, and IndexedDB adapter from the earlier prototype. The only
lane difference is archive preparation and restore:

- **Full history v1:** production archive preparation, including
  `history_since()` and complete history JSON encoding;
- **LocalText:** the private three-field source record, with no
  `history_since()` call.

Two generated Markdown documents were measured:

| document | source bytes | full seed bytes | LocalText seed bytes |
|---|---:|---:|---:|
| 2,000 lines | 42,040 | 17,167,170 | 44,189 |
| 10,000 lines | 210,040 | 86,233,289 | 220,189 |

After one complete unmeasured reload/edit/write warm-up, an independent Node
timer sent `XYZABC` through CDP `Input.insertText` at fixed 500ms offsets. The
sends were not awaited serially, so later commands could queue while the
renderer was blocked. Every actual Node send offset is retained in the raw
evidence and used in the delivery calculation.

Each lane order ran in a separately launched Chromium process. Within one
order, each lane used a fresh browser context:

- 2,000 lines: 10 samples per order, 20 samples per lane;
- 10,000 lines: 3 samples per order, 6 samples per lane.

The aggregator fails closed unless both orders, both lanes, exact sample counts,
matching browser/protocol values, and matching source/seed sizes are present.

The 10,000-line sample count is deliberately fail-fast because one exact reload
takes roughly 148–203 seconds. Its p95 is the maximum of six samples and is
exploratory, not a stable distribution estimate.

Measurements are:

- **content-visible:** navigation origin through exact textarea text;
- **delivery lag:** actual `beforeinput` offset minus its independently recorded
  Node/CDP send offset, both relative to the first delivered/sent input; this
  does not measure absolute first-input delivery delay;
- **input-visible:** actual `beforeinput` through the second animation frame;
- **scheduled input-visible:** Node send offset through that frame, thereby
  including renderer displacement relative to the first input;
- **causal-ready:** actual `beforeinput` through the first accepted local commit
  whose recorded post-commit source length proves that it includes that input;
  multiple queued inputs may share one batch receipt;
- **durable:** first `beforeinput` through the final selected IndexedDB write;
- browser long-task and animation-frame-gap maxima during the burst.

All summaries below aggregate both independent lane orders.

### Causal evidence limitation

The source runs validated each selected receipt against its post-commit source
length, but they predate retention of the selected sequence and length in the
raw per-input record. The aggregate JSON therefore marks
`causal_receipt_fields_retained: false`. Causal timings below are diagnostic and
are not used as the acceptance basis. The current benchmark retains those
fields on future runs; an attempted full replacement run did not complete and
is not included.

## Results

Values are p50/p95 milliseconds except record bytes and commit counts.

### 2,000 lines

| measure | Full history v1 | LocalText | Local/Full p50 | Local/Full p95 |
|---|---:|---:|---:|---:|
| content-visible | 5,914.0 / 9,261.1 | 5,798.4 / 9,770.2 | 0.98x | 1.06x |
| max later delivery lag | 2,364.4 / 4,007.9 | 1.4 / 148.7 | 0.001x | 0.04x |
| max later scheduled input-visible | 2,410.4 / 4,219.7 | 69.5 / 247.4 | 0.03x | 0.06x |
| max later input-visible | 182.9 / 268.3 | 69.6 / 168.3 | 0.38x | 0.63x |
| max later causal-ready | 325.8 / 506.6 | 244.3 / 506.9 | 0.75x | 1.00x |
| burst durable | 7,216.1 / 9,191.7 | 2,750.4 / 2,976.5 | 0.38x | 0.32x |
| max long task | 2,550 / 4,422 | 182 / 417 | 0.07x | 0.09x |
| max frame gap | 2,683.2 / 4,583.2 | 166.6 / 533.2 | 0.06x | 0.12x |
| persisted bytes | 17,169,556 | 44,195 | 0.003x | 0.003x |

Full history completes only two accepted causal commits at p50 for six inputs
because blocked inputs coalesce. LocalText completes six. LocalText still has
non-persistence outliers—the later scheduled-visible p95 is 247.4ms—but removes
the multi-second displacement caused by complete archive preparation.

Content-visible does not materially improve in this run. The earlier startup
benefit is therefore not treated as a repeated 2,000-line result.

### 10,000 lines

| measure | Full history v1 | LocalText | Local/Full p50 | Local/Full p95 |
|---|---:|---:|---:|---:|
| content-visible | 177,986.3 / 202,504.2 | 148,262.6 / 173,570.2 | 0.83x | 0.86x |
| max later delivery lag | 1,341.7 / 4,647.8 | 1,509.1 / 2,125.5 | 1.12x | 0.46x |
| max later scheduled input-visible | 4,114.9 / 8,294.6 | 4,299.4 / 4,944.4 | 1.04x | 0.60x |
| max later input-visible | 3,783.7 / 7,266.3 | 3,893.0 / 4,354.5 | 1.03x | 0.60x |
| max later causal-ready | 4,278.5 / 9,345.0 | 4,449.7 / 4,960.7 | 1.04x | 0.53x |
| burst durable | 21,744.1 / 45,953.8 | 5,478.3 / 6,233.4 | 0.25x | 0.14x |
| max long task | 17,052 / 37,040 | 1,555 / 2,476 | 0.09x | 0.07x |
| max frame gap | 17,082.6 / 37,081.8 | 4,766.5 / 5,416.5 | 0.28x | 0.15x |
| persisted bytes | 86,235,676 | 220,195 | 0.003x | 0.003x |

All six inputs coalesce into one accepted causal commit in both lanes. The
first commit and visible update already take roughly 4 seconds at p50 before
archive preparation can separate the lanes. LocalText therefore does not
materially improve the 10,000-line visible or causal clocks: their p50 values
are at parity or slightly worse.

The numeric p95 improvements come from Full-history outliers in only six
samples and are not treated as a distribution-level win. LocalText does remove
most post-commit persistence work: durable p50 falls by about 75%, the longest
task by about 91%, and the record by about 99.7%. That benefit begins too late
to repair the already multi-second first commit.

## Decision

### Confirmed at 2,000 lines

Synchronous full-history preparation is on the interactive critical path of
continued typing. It creates multi-second frame gaps and delays inputs whose
CDP sends occurred near their requested offsets. LocalText reduces later
scheduled input-visible p95 from 4,219.7ms to 247.4ms, well beyond the 0.75x
material-win threshold.

The production standalone path should not prepare a complete history archive
synchronously after every edit. This selects removal of full-history
preparation from the interactive path as a valid mechanism; it does not select
the prototype record as the final product schema, and the remaining 247ms p95
still requires separate investigation.

### Insufficient at 10,000 lines

At 10,000 lines, restore plus the first edit/commit/projection path is already
catastrophic before persistence starts. LocalText removes a later 17-second
p50 full-history long task but cannot make the first causal or visible update
interactive.

The next performance investigation must isolate source restore,
`MarkdownEditor` commit, Markdown parsing/projection, and DOM publication with
persistence disabled. Production persistence design should not be expanded to
solve this separate core/editor scaling problem.

### Product boundaries remain unresolved

This experiment does not decide:

- production record versioning or migration;
- reload-surviving undo;
- Local-to-Collaborative promotion;
- collaborative causal restore;
- whether Candidate A or an opaque EGW codec is appropriate for collaboration.

Candidate A remains collaboration-specific research. Existing v1 bytes remain
the backup/oracle until a separately reviewed production persistence contract
exists.

## Evidence and reproduction

Aggregated evidence, both lane orders, every sample, every input, actual Node
send offsets, the explicit causal-audit limitation, and source runs are retained
in:

`docs/evidence/2026-08-23-loomark-localtext-sustained-input.json`

The benchmark entry point is:

`apps/loomark/examples/vanilla/bench-local-text-sustained-input.mjs`

The build/run wrapper reproduces all four fresh-process runs and aggregation:

```bash
./scripts/run-loomark-localtext-sustained-input.sh
```
