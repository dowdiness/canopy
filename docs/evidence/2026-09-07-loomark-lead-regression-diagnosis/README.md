# Document-lead regression diagnosis

Scope: the uncommitted connection slice after `44d18fa4`, not Stage 2 acceptance.
The original failures remain recorded in the [implementation plan](../../plans/2026-09-04-loomark-demand-driven-document-lead.md).

## Save-state failure: test fault reproduced on the baseline

The original `installDelayedDocumentAbort` aborted **every** matching Source
put after 500 ms. It therefore aborted the compensating write of `# Untitled`
as well as the intended in-flight write. `save-baseline-original.log` captures
two aborts on the unchanged `44d18fa4` implementation (one failure in five runs
with five workers). The current implementation initially failed four of five
under the same worker count. These are stress samples, not failure probabilities.

Adding a wait for the recovery transaction's `complete` event made the original
helper fail deterministically: `save-commit-barrier-red.log`. Previously a test
could pass by observing the brief interval before the second abort; reading the
old stored text alone did not prove the compensating write had committed.

The corrected helper holds the first transaction until the test delivers the
revert input and explicitly requests its abort. It observes the actual abort
event, permits subsequent writes, and waits for recovery commit before checking
the alert and stored text. There is no elapsed-time abort trigger. Production
save logic was not changed for this fix. The corrected case passed five of five
on both baseline and current bundles (`save-*-fixed.log`); independent review
found no remaining issue in this test seam.

## Input timing: no connection-specific increase established

The unchanged 1 MiB exact-Saved test was run against three equally minified
bundles, each in three serial runs with one worker. Each run uses ten warmup
replacement/revert pairs, then 25 measured pairs (50 observations). The temporary
bundle route and diagnostic logging were removed afterward; the 10 ms assertions
were not relaxed.

| Bundle | Per-run p95 (ms) | Per-run max (ms) |
| --- | --- | --- |
| `44d18fa4` baseline | 4.2, 3.8, 3.4 | 4.3, 4.2, 3.5 |
| Current connection | 4.0, 3.8, 3.5 | 4.2, 4.2, 3.9 |
| Current, extraction bypassed for diagnosis only | 3.9, 4.9, 3.9 | 4.3, 5.0, 4.5 |

Raw observations are in `input-*.log`. Do not pool the runs or infer a latency
guarantee from this small comparison. It does not explain away the previous
14.1/14.8 ms failures. No MoonBit optimization was justified by this result.

A separate phase-instrumented run with a CPU profiler put most of the measured
operation in browser `setRangeText`, rather than the `input` dispatch. See
`browser-53kb.json` and `input-current.cpuprofile`. The clock calls and profiler
make these diagnostic samples distinct from the uninstrumented timing test.

## Large-document execution remains blocking

The corpus is `# Note N`, a blank line, `Paragraph **content** with some detail.`,
and another blank line, repeated 1,000 or 10,000 times. The quiet scenario uses
native end-of-text typing of one character, not replacement of the whole value.
Extraction is instrumented in the compiled, non-minified function; byte counting
and result serialization are after the timer stop.

| Source | Cold extraction | Quiet extraction | Enclosing quiet long task |
| --- | --- | --- | --- |
| 52,890 bytes | 56.2 ms | 55.6 ms | 58 ms |
| 538,890 bytes | 377.8 ms | 369.0 ms | 374 ms |

The larger cold extraction was inside a 670 ms task. Other cold tasks also
occurred; they must not be attributed entirely to this extractor or added to its
timing. Output bounds and moving work to quiet do not bound main-thread work.

An earlier full-value replacement probe also produced a 12,916 ms long task
outside the measured 51.3 ms quiet extraction (`browser-full-replacement.json`).
Its cause is not established here. It is not pooled with native append results
and must not be represented as a problem solved by moving lead extraction.

### Placement comparison, not a production Worker implementation

A throwaway Worker evaluated the same compiled pure extractor and compared its
serialized bounded result (including enum tags) with the app result. The app
sidebar was hidden during this experiment to prevent a second, main-thread lead
extraction. The confirmed run (`worker-execution-confirmed.json`) took 444 ms
inside the Worker and 549.7 ms wall time; the bounded results matched. A native
input was delivered 98.3 ms after computation started and before it ended.
These are `performance.timeOrigin + performance.now()` timestamps from the page
and Worker, not an inference from an outstanding response. The probe first
waits for the Worker's start notification and asserts that the input timestamp
falls inside its computation interval. A 10 ms diagnostic interval continued,
with a maximum observed gap of 73.2 ms—not an absence-of-blocking or input-latency
guarantee. This does not claim faster total execution.

Earlier reply-pending measurements (`browser-539kb-worker.json`) are not evidence
of input during computation. The stronger timing check initially found that the
input preceded computation (`worker-startup-input.json`); that attempt is
retained as a negative control, not pooled with the confirmed run.

The existing synchronous parser cannot be interrupted by moving its call to
another timer. Cooperative scheduling would require parser changes. Off-main-
thread execution is therefore a supported candidate for the lead-specific
blocking problem, but the experiment does not validate readiness, stale-result
handling, cancellation, errors, serialization contracts, lifecycle, or a final
production protocol. None has been adopted. No Worker or diagnostic timer was
added to the production app. Stage 2 and execution acceptance remain open.

## Reproduction and environment

- Node v24.14.1; browser version is recorded in the JSON artifacts.
- Moon 0.1.20260819 (`fc2a4ee`), moonc/core `v0.10.9+6e6c44045`.
  The shared installation had advanced to an incompatible September nightly.
  Diagnosis used an isolated `/tmp/loomark-toolchain-aug19` installation, without
  changing the shared installation or migrating source to a different compiler.
- Baseline: a `git archive 44d18fa4` snapshot, with dependency repositories
  archived at the exact gitlinks, built in isolation. No source worktree was
  reset. The minifier command for all three comparison bundles was `terser -c -m`.
- `browser-diagnose.mjs` is the archived throwaway probe, not a maintained tool.
  It records the original absolute paths and expects the baseline/current/bypass
  bundles in `/tmp`; adapt those paths for another checkout. It uses a disposable
  browser context and a standalone server on port 4347. Its generated-code
  instrumentation is specific to this compiler. Do not copy it into production.

SHA-256 of the compared minified bundles:

```text
baseline:      93f6df012d3c5efa832952e5d92e954f3af7847d86c131e5482192a5dbcd6760
current:       061a28b9cb1c2eb63c7552b4381a29ced46d1edd22af25ac965ec022dd9ef565
no-extraction: e2757fac4c5fbd98df508a95d857225e1a9be0b398ff64d0a7544f92a3594721
```

Normal validation after removing temporary test overrides: TypeScript checking
passed; the complete standalone suite passed **56/56** (`full-suite.log`). This
supersedes the previous latest-suite failure, not its evidence or the open
large-document execution gate. Required GitHub CI is a separate result.
