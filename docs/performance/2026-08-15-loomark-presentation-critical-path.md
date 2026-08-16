# Loomark presentation critical-path characterization

**Date:** 2026-08-15
**Issue:** [#1244](https://github.com/dowdiness/canopy/issues/1244)
**Harness commit:** `dfc0101`
**Production baseline:** `c471ddc8f03ebfa420ef227571b78fbb1b5c970e`

## Decision

Do not optimize Rabbita view materialization, VDOM mutation, layout, or paint for
this issue. At 2,000 lines, those phases do not explain Loomark's 1.8–1.9 second
single-character edit response. The first document-scaled phase is JavaScript
work before the render-frame presentation slice, so presentation optimization
would not materially move the measured response.

This confirms the presentation stop condition recorded after the projection
placement comparison. It does not approve Worker or in-process projection, and
it does not close the remaining authority-path or retention work in #1244.

## Responsibility map

| Phase | Owner | Current entry point | Measurement |
|---|---|---|---|
| Projection result adoption | Loomark application model | `apps/loomark/internal/rabbita/application.mbt` | existing P0–F projection trace |
| Preview read model | Loomark | `preview_read_model.mbt` | existing D record |
| View materialization | Rabbita incremental root | `Sandbox::flush` → `root_view.read()` | temporary fixed-width split probe |
| VDOM comparison and DOM mutation | Rabbita runtime | `Sandbox::flush` → `diff_node(...)` | temporary fixed-width split probe |
| Style and layout | Chromium | main render thread | CDP `UpdateLayoutTree` and `Layout` events |
| Paint and composition | Chromium | main render thread | CDP `PrePaint`, `Paint`, and `CompositeLayers` events |

The release-browser harness now optionally records Chromium main-thread event
summaries with `LOOMARK_MAIN_THREAD_TRACE=1`. Marks surround each complete
scenario, so `FunctionCall` includes input dispatch and authority work as well
as presentation. It must not be labeled as view or DOM time without the split
probe.

## Method

The retained run used the release Warren bundle in headless Chromium through
Playwright 1.61.1 on Node.js 24.14.1. It ran three synchronous-placement samples
of the 2,000-line corpus. Each scenario retained its existing native
`insertText`, exact Preview-currentness wait, two-animation-frame settle, Long
Task observer, and frame-gap observer.

The CDP trace collected `blink.user_timing`, `devtools.timeline`, and `v8`
events. Calibration requires all six scenario intervals and a positive control:
cold Seed must contain JavaScript `FunctionCall` time and take longer than the
source-equal no-op. Both controls passed in every run.

A temporary measurement-only Rabbita probe then wrote numeric phase IDs and
`performance.now()` timestamps into a preallocated `Float64Array` immediately
before `root_view.read()`, between `root_view.read()` and `diff_node(...)`, and
after `diff_node(...)`. The probe was removed after measurement; it is not a
production hook.

## Results

### Retained release-browser CDP evidence

Medians across three 2,000-line synchronous runs:

| Scenario | End-to-end | JavaScript `FunctionCall` | Style/layout | Paint/composition |
|---|---:|---:|---:|---:|
| Cold Seed | 3,899.0 ms | 3,764.1 ms | 23.0 ms | 10.4 ms |
| Local edit — start | 1,898.8 ms | 1,800.7 ms | 11.7 ms | 4.5 ms |
| Local edit — middle | 1,914.7 ms | 1,814.1 ms | 8.5 ms | 4.8 ms |
| Local edit — end | 1,799.1 ms | 1,699.3 ms | 11.0 ms | 4.8 ms |
| Source-equal advance | 49.0 ms | 4.2 ms | 0.0 ms | 0.0 ms |

The `FunctionCall` column is deliberately broad. It identifies JavaScript as
the first document-scaled browser phase, but does not identify presentation as
its owner.

### Temporary D-to-paint split probe

| Scenario | End-to-end | Rabbita view reads, total | Rabbita VDOM/DOM diff, total | Render frames |
|---|---:|---:|---:|---:|
| Cold Seed | 3,978.3 ms | 5.3 ms | 8.5 ms | 2 |
| Local edit — start | 1,931.3 ms | 3.9 ms | 5.8 ms | 3 |
| Local edit — middle | 1,664.2 ms | 3.4 ms | 6.4 ms | 3 |
| Local edit — end | 1,647.8 ms | 4.0 ms | 7.4 ms | 3 |
| Sustained typing, 8 edits | 1,898.2 ms | 3.5 ms | 18.9 ms | 12 |
| Source-equal advance | 48.1 ms | 0.1 ms | 3.3 ms | 2 |

For the middle edit, measured Rabbita presentation work totals 9.8 ms against a
1,664.2 ms response. Style/layout and paint are also single-digit milliseconds
in the retained trace. Sustained typing had one VDOM/DOM outlier at 123.1 ms;
the other samples were 16.1 ms and 18.9 ms, so the outlier is retained rather
than generalized into a stable bottleneck. No presentation phase is large
enough to justify an optimization prototype.

The existing isolated Preview materializer benchmark corroborates the split:
2,500-block edited Preview materialization measured 22.70 ms mean, while the
2,000-line browser response remained approximately two orders of magnitude
larger.

## Evidence

- [2,000-line main-thread trace](../evidence/2026-08-15-loomark-main-thread-2k.json), SHA-256 `a1bef255de2b399c86f68c93fa850dfa4bfc05d03a927859065667073f63391d`
- [Temporary presentation split summary](../evidence/2026-08-15-loomark-presentation-split-probe.json)
- [Projection placement rejection](2026-08-15-loomark-projection-placement.md)

## Consequences

- Keep synchronous production projection placement.
- Keep the private projection executor seam for comparison only.
- Do not add presentation virtualization, keyed-local-render machinery, or a
  Rabbita profiling interface from this evidence.
- Continue #1244 by splitting the pre-frame JavaScript `FunctionCall` interval
  at authority receipt, commit, Block feedback, projection adoption, and render
  scheduling. Optimize only after that split identifies a reproducible dominant
  phase.

Decision record:

- No new ADR needed: this measurement applies the stop condition already
  recorded by the accepted concurrent-projection ADR; it does not change the
  production placement or public contract.
