# Loomark demand Preview implementation report

**Status:** IMPLEMENTED CANDIDATE — **HOLD** adoption of the overall 10 ms target; **not production ready**.

## Scope and verdict

This change fixes the specific hidden-Parser retention regression: when Text
hides an already healthy Preview, edits no longer advance its Parser. The
retained Preview catches up when demanded. It does **not** establish a
production response budget or a general speedup. The source manifest records
only Loomark Preview/app/tests and the diagnostic script; it does not list a
dependency or save-path change. No commit or push is part of this report.

The source-of-truth boundary remains app-owned Document text. `preview.Input`
is a captured read, not an authority; the app supplies current text and IME
state on every Preview transition. **No ADR needed:** this restores the existing
source-first interactive contract. No plan is closed.

## Implemented behavior

- A private pure `queue_refresh` chooses at most one text-free wake. It does
  not allocate a wake per edit. A pending wake whose revision changed waits a
  full additional quiet interval; the minimum quiet period is 24 ms, while
  browser delay and one extra quiet interval remain allowed.
- Demand, generation, input, ticket, composition, and output-acceptance checks
  fence stale preparation and refresh work. IME blocks initial preparation and
  cancels a pending wake; completion resumes the latest needed work.
- The Preview keeps its last successful view after a refresh failure, but a
  parser failure invalidates the private engine render baseline. This is the
  existing conservative engine behavior, not a new public API regression.
- `catch_up`/`catch_up_owned` reconcile a legitimately lagging healthy cache:
  one exact `TextChange` may be retained; otherwise they use `ReplaceAll` with
  current app text. They do not compute a generic diff.
- The local imperative `PreviewEngine` and command/timer wiring remain the
  shell. Lifecycle transition/queue decisions are pure; the command test
  harness confines mutation to event dispatch and restores the retained cache.

Existing lifecycle entry points and opaque state/event types remain. `Input`
adds an optional `composing` argument; `composition_started` and
`composition_ended` are new public lifecycle hooks. No trait bounds widened.
`queue_refresh` is private.

## Reuse check

- Text edits reuse `TextChange.apply`, `ReplaceRange`, and `ReplaceAll`; the
  textarea already falls back to `ReplaceAll` when native edit facts are not
  usable.
- The engine reuses its existing `apply`, `refresh`, `accept`,
  `SyntaxParser.apply_edit`, and `SyntaxParser.set_source` paths.
- The shell reuses Rabbita `cmd.delay`, `custom_cmd`, after-render scheduling,
  `request_animation_frame`, and browser timers. No new effect abstraction was
  added.
- `Option.equal` and pattern matching cover option comparison/selection;
  `Option.filter` was checked but is not needed. Core String APIs were checked
  for representation choices; no new String diff was introduced. The generic
  `compute_text_change` approach remains unused because it would add costly
  diff work to this path.

## Validation evidence

| Check | Result |
| --- | --- |
| Targeted JS release unit suite | 99/99 passed: Preview 40, app 59 |
| Production standalone E2E | 55/55 passed, including the new large trusted-input/retained-Preview and pending-wake IME cases |
| Old unchanged served application | New large retained-Preview E2E fails: p95 **47.3 ms** against `<=10 ms` |
| Candidate served application | The same E2E passes `<=10 ms` |
| Separate serial 2,000-line diagnostic | After Preview: p95 **3.0 ms**, max **3.2 ms**; reload control max **27.9 ms** remains |

The serial control is diagnostic evidence, not a baseline for a speedup ratio;
it must not be combined with the 47.3 ms E2E result.

## Independent browser probe and limitations

The independently scheduled CDP probe used 50 trusted keys at 30 ms intervals,
three trials, 2,000 lines, offline persistence, and reload restoration.

| Mode | Processing p95 by trial (ms) | Third-trial max (ms) |
| --- | --- | --- |
| Text | 3.5, 3.0, 3.1 | 83.9 |
| Split | 3.3, 2.7, 3.2 | 81.6 |

The third-trial outliers have no trace and are **unattributed**: do not call
them GC, parser, or host noise. A fully traced repeat has Text maxima 4.9, 7.2,
and 7.1 ms, but does not erase the earlier failures.

Split trace evidence still shows non-preemptible tasks: real keydown queue
maxima 62.1–63.1 ms and 24 ms wake-timer fires of 60.044 and 72.602 ms. That
supports a Worker/cooperative comparison before making any overall-budget
claim; a timer-only conclusion is not justified.

Keep raw Event Timing duration maxima (1,288–1,304 ms) uninterpreted: they are
not full INP or actual presentation. Trace paint gaps (43.148 and 103.218 ms)
are same-thread gaps, not presentation timestamps; rAF is not paint and CDP ACK
includes transport.

## Review disposition and next gate

- Reject “exact latest edit + 24 ms”: it conflicts with the deliberate
  one-pending-timer policy, which can add one quiet interval.
- Keep baseline clearing on parser failure: conservative invalidation is safe
  and already private, not a public API regression.
- Before adopting a 10 ms overall target, compare Worker and cooperative
  execution for the remaining Split non-preemptible work, with traced outliers
  and a presentation-capable measurement.

## Reproduction

From the repository root, build the standalone distribution, then serve it on
4324 (the diagnostic scripts default to that URL):

```bash
LOOMARK_STANDALONE_PORT=4323 NEW_MOON_MOD=0 bash scripts/test-loomark-standalone-e2e.sh
LOOMARK_STANDALONE_PORT=4324 node apps/loomark/examples/vanilla/serve-standalone-dist.mjs
# separate terminal
MODE=Text OUTDIR=/tmp/loomark-demand-text node scripts/loomark-preview-demand-diagnostic.mjs
MODE=Split OUTDIR=/tmp/loomark-demand-split node scripts/loomark-preview-demand-diagnostic.mjs
```

For the standalone E2E server, its default is 4317; set
`LOOMARK_STANDALONE_PORT=4323` to reproduce the recorded test port. Run the
recorded targeted suites with:

```bash
export NEW_MOON_MOD=0
moon check apps/loomark/internal/preview apps/loomark/app
moon test --target js --release apps/loomark/internal/preview apps/loomark/app
cd apps/loomark/examples/vanilla
npm run typecheck
LOOMARK_STANDALONE_PORT=4323 npm test
```

## Evidence

- [Source manifest](../evidence/2026-09-06-loomark-demand-preview/source-manifest.json)
- [Targeted units](../evidence/2026-09-06-loomark-demand-preview/final-unit.txt), [all E2E](../evidence/2026-09-06-loomark-demand-preview/all-e2e.txt), and [old-app failure](../evidence/2026-09-06-loomark-demand-preview/browser-red.txt)
- [Serial control](../evidence/2026-09-06-loomark-demand-preview/serial-2000/results.json), [Text probe](../evidence/2026-09-06-loomark-demand-preview/text-30/results.json), [Split probe](../evidence/2026-09-06-loomark-demand-preview/split-30/results.json), [fully traced Text](../evidence/2026-09-06-loomark-demand-preview/text-trace-all/results.json), and [trace analysis](../evidence/2026-09-06-loomark-demand-preview/trace-analysis.json)
- [Core Option API](../evidence/2026-09-06-loomark-demand-preview/core-option.txt) and [Core String API](../evidence/2026-09-06-loomark-demand-preview/core-string.txt)
