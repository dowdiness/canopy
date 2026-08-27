# Loomark Preview quiet-window comparison: 32 ms versus 24 ms

Date: 2026-08-28

## Question

Can Loomark shorten the Preview quiet window from 32 ms to 24 ms while
preserving rapid-input coalescing, the 10 ms Text-input contract, IME behavior,
and large-document responsiveness?

## Environment

- Canopy base commit: `fa08288b848b26ac59c2b8451466bd3342d6e02e`
- Candidate source change: `PREVIEW_QUIET_MS` from 32 to 24
- Target: JavaScript release build
- Chromium: 149.0.7827.55, headless
- Node.js: v24.14.1
- Host: Linux x64, WSL2 kernel 6.18.33.2
- CPU: AMD Ryzen 7 6800H with Radeon Graphics
- Browser launches: 3 fresh processes per latency case
- Warm-up: 20 edits per launch
- Samples: 44 edits per launch, 132 per latency case

## Raw samples

32 ms control:

- [500-block boundary](2026-08-28-loomark-preview-32ms-500-boundary-raw.json)
- [2,500-block boundary](2026-08-28-loomark-preview-32ms-2500-boundary-raw.json)
- [2,500-block interior](2026-08-28-loomark-preview-32ms-2500-interior-raw.json)
- [20 ms and 40 ms bursts](2026-08-28-loomark-preview-32ms-burst-raw.json)

24 ms candidate:

- [500-block boundary](2026-08-28-loomark-preview-24ms-500-boundary-raw.json)
- [500-block interior](2026-08-28-loomark-preview-24ms-500-interior-raw.json)
- [2,500-block boundary](2026-08-28-loomark-preview-24ms-2500-boundary-raw.json)
- [2,500-block interior](2026-08-28-loomark-preview-24ms-2500-interior-raw.json)
- [20 ms and 40 ms bursts](2026-08-28-loomark-preview-24ms-burst-raw.json)

## Method

The 500-block fixture contained 250 heading/paragraph pairs. The 2,500-block
fixture contained 1,250 pairs. Boundary edits replaced the first character of a
paragraph. Interior edits used an offset of 14 UTF-16 code units within the same
paragraph.

Each latency edit waited for the expected Preview text through a public DOM
`MutationObserver`. No production profiling API or test-only Model state was
added. Long tasks were collected with the browser Performance Observer API.

The burst comparison replaced one character 20 times. It counted distinct
Preview values observed through the public DOM instead of counting internal
commands.

## Input-to-visible results

Each table value is the mean of three fresh Chromium launch means.

| Fixture | Edit | 32 ms control | 24 ms candidate | Difference |
|---|---|---:|---:|---:|
| 500 blocks | boundary | 51.38 ms | 46.21 ms | -5.17 ms (-10.1%) |
| 2,500 blocks | boundary | 173.53 ms | 159.91 ms | -13.62 ms (-7.8%) |
| 2,500 blocks | interior | 105.72 ms | 107.86 ms | +2.14 ms (+2.0%) |

For the 500-block boundary case, the control p95 values were 60.4–61.0 ms and
the candidate p95 values were 48.7–57.6 ms. Neither candidate produced a long
task.

The candidate's 500-block interior launch means were 36.76–38.59 ms, with p95
values of 44.5–44.9 ms and no long tasks.

Renderer-dominated long tasks remained in the 2,500-block cases. Candidate
boundary counts were 51–61 versus 71–79 for the control; interior counts were
19–42 versus 27–41. Mean long-task durations overlapped at 53–67 ms. The 2.0%
interior mean difference is small beside launch variance and does not establish
a regression.

## Burst behavior

Two clean launches produced the same publication counts:

| Input interval | 32 ms control | 24 ms candidate |
|---|---:|---:|
| 20 ms | 1 publication | 1 publication |
| 40 ms | 20 publications | 20 publications |

After the final 20 ms input, the candidate became visible in 48.2–48.6 ms
versus 56.4–58.0 ms for the control. After the final 40 ms input, the candidate
became visible in 39.2–39.6 ms versus 46.2–64.4 ms for the control. These runs
produced no long tasks and kept synchronous input handling below 2.4 ms.

## Behavioral validation

The 24 ms production candidate passed:

- all 16 standalone Playwright tests;
- both 10 ms Text-input gates;
- the IME test that forbids Preview work before composition commits;
- native range edit and native undo coverage; and
- strict JS checking for `apps/loomark`.

## Decision

Adopt the fixed 24 ms quiet window. It removes 5.2 ms from the 500-block
boundary mean, preserves clean 20 ms burst coalescing, and leaves the
2,500-block interior mean within 2.0% of the control. Keep 16 ms, zero-delay,
and adaptive policies out of scope. Revisit the value only with another
production-browser comparison.
