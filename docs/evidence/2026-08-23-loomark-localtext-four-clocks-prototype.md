# Loomark LocalText four-clock prototype

**Date:** 2026-08-23

**Status:** throwaway prototype evidence; no production archive or product contract is accepted

## Question

Does text-only local persistence remove Loomark input and reopen latency without
changing the editor implementation?

## Prototype

The branch adds an exact private opt-in:

```text
?projection-benchmark=1&four-clock-prototype=1&local-text-prototype=1
```

The opt-in:

- keeps the existing `MarkdownEditor`, parser, projection, commit, and UI paths;
- stores a private three-field record containing prototype format, document ID,
  and portable Markdown;
- does not call `history_since()` while preparing that record;
- reuses `LocalArchivePersistenceQueue` and the existing IndexedDB adapter;
- uses a separate `loomark.prototype-local-text` key;
- leaves production v1 loading and storage unchanged without the opt-in.

The prototype does not decide archive migration, collaboration, or
reload-surviving undo. Current undo behavior in this experiment is not an
accepted product contract. The throwaway branch adds two explicitly named
package-public repository functions so the existing persistence queue can be
reused; the generated interface drift makes this branch intentionally
non-mergeable. A production design must place the selected mechanism behind a
private seam rather than promote those functions.

## Measurement

Chromium `149.0.7827.55` ran one complete unmeasured reload/edit/write warm-up
and 20 measured cycles for each lane and each existing fixed 1,000-event
fixture. Lane order is counterbalanced by fixture. Every cycle reseeded the
original record, reloaded the Warren release page, appended `Z` with a real
keyboard input, and waited for the selected IndexedDB record.

Four clocks are independent:

- **content-visible:** navigation origin through exact textarea text;
- **input-visible:** `beforeinput` through the second animation frame after the
  matching input event;
- **causal-ready:** `beforeinput` through the next sequence-correlated
  successful local commit receipt, before archive preparation;
- **durable:** `beforeinput` through completion of the selected IndexedDB write.

Values below are p50/p95 milliseconds except persisted bytes.

| fixture | content-visible full → local | input-visible full → local | causal-ready full → local | durable full → local | persisted bytes full → local |
|---|---:|---:|---:|---:|---:|
| `S-distributed-1000` | 197.7/211.5 → 147.1/259.9 | 23.7/27.6 → 19.4/25.3 | 63.1/64.2 → 61.5/66.0 | 103.3/109.3 → 64.7/70.1 | 266218 → 2132 |
| `S-linear-1000` | 186.1/284.3 → 148.7/254.4 | 20.9/27.4 → 22.4/27.4 | 62.8/65.2 → 63.6/67.7 | 97.2/111.3 → 67.8/72.9 | 231139 → 2127 |
| `S-replacement-1000` | 168.6/287.4 → 108.1/205.6 | 19.0/26.9 → 24.3/28.0 | 53.9/54.4 → 52.9/53.8 | 90.3/94.2 → 54.2/57.1 | 227567 → 132 |
| `S-tombstone-1000` | 184.9/300.0 → 109.8/248.3 | 17.7/28.2 → 20.5/24.1 | 59.3/61.5 → 57.1/59.2 | 97.3/104.3 → 59.6/63.2 | 228936 → 790 |
| `S-unicode-1000` | 221.7/312.5 → 130.2/226.3 | 22.3/29.3 → 19.2/26.8 | 65.0/68.9 → 62.1/64.9 | 104.5/115.2 → 65.6/70.4 | 231140 → 2128 |

Raw values are retained in
`2026-08-23-loomark-localtext-four-clocks-prototype.json`.

## Result

### Confirmed

LocalText materially reduces durable completion and serialized size on every
fixture.

- durable p50 falls to 0.60–0.70× the full-history lane;
- durable p95 falls to 0.61–0.65×;
- the selected record falls from 227–266 KB to 132–2,132 bytes;
- content-visible p50 improves to 0.59–0.80× on every fixture;
- four of five content-visible p95 values improve to 0.72–0.89×.

The distributed fixture's content-visible p95 regresses to 1.23× despite its
p50 improving to 0.74×. The prototype therefore does not establish a universal
p95 startup win.

### Not confirmed

LocalText does not materially improve the first visible input or causal commit
on these fixtures.

- input-visible remains 17.7–24.3 ms p50 in both lanes;
- causal-ready remains 52.9–65.0 ms p50 in both lanes;
- the ratios fluctuate around parity rather than showing a consistent win.

This is useful negative evidence. Complete-history preparation happens after
the local commit milestone and does not explain the first visible keystroke on
these 1,000-event fixtures.

## Interpretation

The prototype confirms LocalText as a promising local **storage/reopen**
mechanism, not as a complete explanation for every report that the editor
"feels slow."

The earlier 2,000-line evidence measured 1.78 seconds of synchronous archive
preparation. That work may displace a subsequent input even though the first
character paints before preparation completes. This prototype measured one
input, not sustained typing or next-input displacement, and its visible text is
at most 1,715 bytes.

The next smallest experiment is therefore not a production schema. It is a
2k/10k sustained-input comparison that measures the second and later input
latency while archive preparation is active. If LocalText removes that
displacement, retain it as the selected latency mechanism. If it does not, stop
this persistence route and profile commit/projection scheduling.

## Reproduction

From the prototype worktree:

```bash
LOOMARK_LOCALTEXT_SAMPLES=20 \
LOOMARK_LOCALTEXT_OUTPUT=/tmp/loomark-localtext-four-clocks.json \
./scripts/run-loomark-localtext-prototype.sh
```
