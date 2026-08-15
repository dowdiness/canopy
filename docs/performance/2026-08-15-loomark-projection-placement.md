# Loomark projection placement promotion evidence

**Date:** 2026-08-15

**Harness commit:** `782df1ccd72fd77d0a24ab75d4eb65f5c9ea47d6`

**Decision:** Do not promote the dedicated Worker or in-process executor. Retain synchronous production placement and the private executor comparison seam.

## Method

`apps/loomark/examples/vanilla/bench-projection-placement.mjs` ran the release Loomark application with Playwright 1.61.1 on Node.js 24.14.1 under Linux 6.18.33.2 WSL2. The exact bundled Chromium version was not recorded and is not claimed. The three placements used the same production authority, application, projection adoption, and DOM presentation path. Only the projection executor changed through the private `projection-placement` query.

The 2,000-line comparison used three samples per placement in a rotated 3×3 Latin square. Each run performed a cold whole-source Seed, one-character native `insertText` edits at the start, middle, and end, an eight-character typing burst, and a source-equal advance. Completion required both the expected source and a unique rendered-content marker, so a retained stale Preview could not finish a sample. Reported duration includes input through two animation frames after current Preview presentation.

The 10,000- and 50,000-line runs used one sample per placement with a hard 120,000 ms isolated-process deadline. Every run was censored during the cold Seed before later scenarios could execute. Killing the isolated process prevents one blocked renderer from contaminating later placements.

Tracing was enabled only by `projection-benchmark=1`. The browser calibration test proves that the default page exposes neither the trace control nor trace data, while an opted-in edit produces a non-empty, non-overflowed trace with zero dropped records and no trace-contract violation. Synchronous runs contain P0–F phases; Worker and in-process runs contain only authority-through-dispatch phases A0–B. Async adoption/presentation trace calibration is therefore incomplete.

## 2,000-line release-browser result

Durations are median / observed p95 in milliseconds from three samples. Long Task is observed p95 cumulative Long Task time.

| Scenario | Worker | In-process | Synchronous | Long Task p95 range |
| --- | ---: | ---: | ---: | ---: |
| Cold Seed → Preview | 6,042 / 6,290 | 5,973 / 6,307 | **4,293 / 4,442** | 4,282–6,154 |
| Local edit: start | 2,281 / 2,364 | 2,247 / 2,308 | **2,099 / 2,114** | 2,015–2,171 |
| Local edit: middle | 1,981 / 1,981 | 2,081 / 2,182 | **1,848 / 2,015** | 1,738–2,064 |
| Local edit: end | 1,948 / 1,997 | 1,881 / 2,014 | **1,649 / 1,964** | 1,706–1,906 |
| Eight-edit typing burst | **1,964 / 2,114** | 2,115 / 2,298 | 2,030 / 2,098 | 1,707–1,986 |
| Source-equal advance | **47.8 / 48.6** | 47.4 / 48.3 | 48.6 / 49.4 | 0 |

No placement satisfies the responsiveness gate. Worker wins the typing-burst median by 65.7 ms against synchronous, but loses cold Seed by 1,749.5 ms and loses every individual local-edit median by 132.7–299.3 ms. These results do not support a speedup claim. The near-total overlap between end-to-end duration, Long Tasks, and maximum frame gaps shows that main-thread presentation dominates; moving projection computation alone does not make the editor responsive.

## Large-corpus stop condition

All Worker, in-process, and synchronous 10,000- and 50,000-line cold-Seed runs exceeded 120,000 ms. No local-edit, Block, cutover, queue, payload/copy, or forced-GC retention result exists for those sizes. This is censored failure evidence, not a latency measurement and not proof of collectibility.

The plan's presentation stop condition therefore fired before executor promotion. The synchronous path remains the production default because neither alternative passed the common gate, and retaining it avoids Worker lifecycle and transport cost without claiming that synchronous presentation is acceptable.

## Raw evidence

- [2,000-line paired runs](../evidence/2026-08-15-loomark-projection-placement-2k.json) — SHA-256 `07dfc408d4844de0e383671bb8ab93e7117169a9db43077ea236ee017f926eb3`
- [10,000/50,000-line censored runs](../evidence/2026-08-15-loomark-projection-placement-large-censored.json) — SHA-256 `4867a52ca7d6748f5c45a01538702244fcdfab93dc8b977750d6b0a2f3db4112`

The raw 2,000-line report includes each run's available trace records, post-GC whole-page heap observation, Long Tasks, frame gaps, source bytes, run order, environment, and harness commit. Whole-page heap values are not used as adapter-retention evidence. The raw trace must not be described as P0–F evidence for Worker or in-process placement.

## Remaining evidence

Worker promotion is rejected, but issue #1244 remains open because the presentation path fails before the complete Commit 7 matrix can run. Still missing: calibrated async adoption/presentation phases D–F, back-to-back Block intent, demand-only Preview, split-edit isolation, forced failure/restart, cutover bursts, 100-cutover forced-GC reachability with a positive retention control, and separately attributed queue and payload/copy metrics. Those results must follow presentation work; this record does not mark their acceptance criteria complete.
