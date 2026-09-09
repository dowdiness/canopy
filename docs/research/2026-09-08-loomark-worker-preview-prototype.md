# Loomark Worker Preview prototype

**Status:** experimental comparator; **not for production adoption**. This report
records a standalone, page-lifetime Worker experiment dated 2026-09-08. The
main-authoritative Source contract and dependency pins are unchanged; local
execution remains the default. No commit, push, or dependency update was made.
**No ADR needed:** this is an isolated comparator, not production adoption or
a plan closure.

## Scope and decision

The opt-in `?preview-worker=1` moves only the existing Preview parser and
Markdown lowering to a dedicated Worker. Without that query parameter, Preview
remains local. This is not a cooperative-Loom implementation: no resumable or
time-budget API was added. The comparison is local execution versus Worker
execution only.

Do **not** adopt this prototype for production. **Historical 2026-09-08
snapshot:** Rabbita component-unmount cleanup was not wired or tested, and the
cold-asset gate failed when `preview-worker.js` was unavailable at first demand.
Those two prototype gaps are resolved in the 2026-09-09 follow-up below. Its
other limits remain: production CSP and release-pipeline validation are outside
this experiment, and there is no synchronous main-parser fallback.

## 2026-09-09 follow-up: offline-first payload and disposal

This follow-up is limited to offline-first Preview after the application has
loaded and actual Rabbita cleanup. It is not a Service Worker, cache
infrastructure, cold-offline-page-load guarantee, or another performance
campaign. The user now treats 10 ms as an effort goal; existing test thresholds
were not changed. No new startup, memory, or performance claim is made.

### Embedded Worker payload

The build embeds the Worker source as inert JSON in `index.html`, escapes `<`,
and verifies a single payload script. The client parses that payload, creates a
classic-Worker Blob URL on first request, and reuses it through Worker restarts
and document activation. Thus first Preview demand still works when the HTTP
Worker asset is blocked **after application load**; it does not make a cold
offline navigation work. The current artifact retains `preview-worker.js`, but its uncompressed Worker
source is also embedded. The 3,076,700-byte `index.html` and 2,993,569-byte
`preview-worker.js` figures are historical pre-minify sizes; see
[Worker minification and size comparison](#worker-minification-and-size-comparison).

`worker-src` must permit `blob:` for this mode. Production CSP was neither
changed nor validated. Missing or corrupt payload remains an error rather than
a synchronous main-parser fallback. The archived RED isolated pre-change
assets and failed its cold gate; the current GREEN probe passes. An earlier RED
attempt using a local-mode URL is not accepted as evidence.

### Worker minification and size comparison

The build now minifies the Worker with Terser 5.51.2 using the existing
Warren `-c toplevel=true -m toplevel=true` options, with no property mangling.
Minification happens before the Worker hash and embedded payload are created.
A callback replacer fixes replacement-string `$$` corruption, and a verbatim
insertion guard verifies the payload insertion. All sizes below are bytes.

| File / encoding | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Worker raw | 2,993,569 | 608,646 | 79.7% |
| HTML raw | 3,076,700 | 627,566 | 79.6% |
| HTML gzip level 9 | 323,843 | 147,394 | 54.5% |
| HTML Brotli quality 11 | 223,029 | 118,366 | 46.9% |

These are offline encoded-file sizes, not actual network transfer: server
compression is unchanged. They make no latency, memory, or performance claim.
The main bundle and unminified Worker input are byte-identical before and
after; HTML is identical except for its payload. The offline probe passes, as
does the three-case disposal fixture. The full Worker E2E initial run was
62/63: the unchanged 1 MiB Saved timing p95 assertion failed at 10.3 ms
(`<=10 ms`), while its isolated rerun passed. This is not a 63/63 single-pass
result. The user's 10 ms target remains an effort goal; no threshold changed.
See the [size data](../evidence/2026-09-09-loomark-worker-minify/sizes.json)
and [minify manifest](../evidence/2026-09-09-loomark-worker-minify/manifest.json).

### Rabbita lifetime cleanup

`app.app` now owns a local Rabbita subscription whose unload calls
`PreviewEngine.dispose`. Final disposal terminates the Worker, clears pending
callbacks/timers, disarms future requests, revokes the Blob URL, and permanent
engine activation/ownership fences reject later work. The fixture toggles the
app through `switch_by`; its cleanup-removal RED had two failed assertions, and
the restored fixture passed all three lifecycle cases.

### Recorded validation and boundaries

The recorded run has 108 unit tests, 63 Worker E2E tests, three lifecycle
fixture tests, and 55 default-local E2E tests passing; `moon check` recorded
nine warnings and no errors, alongside TypeScript checking, formatting, and
`moon info`. The independent review found no critical issue and noted the test-route
placement; the parent moved its registration before navigation and reran it. Payload byte/hash consistency and the
single escaped parent script were checked. The existing 4324 control artifact
is preserved; the current prototype serves on 4325. The isolated August 19
private `/tmp` SDK was restored; no commit, push, dependency, or global
toolchain change was made. No ADR is needed: this is a prototype follow-up,
not plan closure.

See the [2026-09-09 evidence](../evidence/2026-09-09-loomark-worker-offline-dispose/manifest.json).

## Implemented boundary

- The app retains Document text authority. `Input` captures the current text
  and composition state; the Worker receives text plus an optional exact edit.
- A Worker owns a `PreviewEngine` and runs its existing parser/lowering path;
  it returns detached Markdown-node DTOs, not parser/runtime objects. The main
  thread decodes and renders those DTOs through the shared safe renderer.
- The renderer uses typed Rabbita HTML and renders Markdown HTML as text; it
  does not use `innerHTML`. Each changed-block subtree is limited to depth 256
  and 10,000 nodes. The response-string cap is 16,777,216 UTF-16 code units,
  not a 16 MiB wire-byte limit or a 10,000-node limit for the entire response.
- Worker request sequence is distinct from parser/acceptance sequence. The
  Worker permits one unacknowledged candidate. Parsing advances on requests;
  only the accepted projection/reuse baseline advances after main admission
  and a positive ACK.
  Reuse indexes are accepted only once and only from the previously accepted
  block set.
- The lifecycle permits one in-flight request, tracks dirty/revision flags,
  and captures the authoritative current input when work starts. It does not
  enqueue a text snapshot or Worker request per edit. A Worker `error`,
  `messageerror`, exception, or 10-second timeout terminates the client,
  reports failure, retains the last successful view, and allows a later edit to
  start a fresh Worker.
- Logical suspension and IME composition cancel pending admission/scheduling;
  work already running may finish but cannot publish while blocked. A new
  generation terminates the old Worker and fences its completion.

Source inspection establishes that the opt-in `prepare_command` and
`catch_up_command` use the Worker request path rather than constructing a
main-thread `PreviewEngine` parser. The held-response browser test separately
shows that a Worker result is required before it appears; it is not evidence
for the source-inspection claim.

## Validation recorded

The final evidence records 107 JS unit tests, 60 opt-in Worker E2E tests, and
55 default-local E2E tests passing. The Worker total is the 55 reused production
cases (with their Worker assertion changed to expect one Worker) plus five
focused held-response, crash, generation, IME, and timeout cases. It also
records TypeScript checking, formatting, `moon info`, `moon check` (9 warnings,
0 errors), and the Worker build. An [independent read-only review](../evidence/2026-09-08-loomark-worker-preview/review.txt)
reported no high-confidence defects. Neither tests nor review constitute a
formal proof or an adoption approval.

The final ABBA measurements bind main bundle
`99122bd161957a6ce67a4b118ec0854ae5ee8629df3168bd96124f633db058ab` and
Worker bundle
`811ab6832efe78194006e381f2437c2586afccd1bf1cccac8e7c84062d29b03d`.
Earlier `b8e6…` Worker measurements predate unused JSON-representation removals
and private-API cleanup, so they are historical rather than final-byte evidence.

## Measurement snapshot and limits

The probe ran 50 trials of 50 trusted insertions (2,500 measured inputs),
at 2,000 lines. The unchanged
server on port 4324 recorded one Text control failure of 10.7 ms across 12
trials; the earlier 83.9 ms result was not exactly reproduced.

Final headful-Xvfb ABBA runs used two trials per placement at each interval.
All latency values below are milliseconds; updates are observed DOM text
changes, not verified presentation timestamps.

| Interval | Local: input max / keydown delay max / duration max / updates | Worker: input max / keydown delay max / duration max / updates |
| --- | --- | --- |
| 30 ms | 5.3–6.0 / 48.8–52 / 72 / 2–3 | 4.8–4.9 / 2.7–2.9 / 24 / 1 |
| 100 ms | 5.3, 79.4 / 2.8, 3.3 / 24, 88 / 50, 49 | 5.4–5.6 / 5.0–5.8 / 24 / 47, 47 |

These are not equal-work speedup measurements: preview cadence differs. They
also do not establish a universal 10 ms pass. The pre-cleanup headful Worker
run includes a 12.7 ms proxy spike, and final local includes a 79.4 ms spike.
At final-local index 41, the trace has 79.579 ms keypress wall time, 4.076 ms
thread CPU, 1.563 ms layout, and 0.311 ms input dispatch. At the earlier Worker
index 19, it has 12.957 ms keypress wall time, 5.142 ms thread CPU, 0.964 ms
layout, and 0.385 ms input dispatch. Wall/CPU gaps do not attribute either
spike to GC, the parser, or the host, and do not establish a shared cause.

Headless Event Timing duration maxima remain about 1.3 s at 30 ms and 4.24 s at
100 ms. Omitting the supplied CDP timestamp in a separate control did not
resolve the large durations. Headful-Xvfb values span 24–128 ms.
Do not label either raw value INP: physical-paint timestamps were not proven.
The input probe measures before-input-listener to input-microtask timing, not
whole INP or all handlers. Keydown delay relative to a CDP timestamp may include
outbound transport, and ACK round-trip is not input queueing.

## Reproduction

The build script deliberately uses an isolated August 19 `MOON_HOME`, not the
global September toolchain. It runs `npm ci` in `apps/loomark`, builds the
standalone assets and Worker, and prints their hashes. Install the vanilla test
dependencies separately, then serve the Worker build on 4325; the unchanged
4324 artifact remains the `906…` control.

```bash
MOON_HOME=/tmp/loomark-toolchain-aug19 bash scripts/build-loomark-preview-worker.sh
(cd apps/loomark/examples/vanilla && npm ci)
LOOMARK_STANDALONE_PORT=4325 node apps/loomark/examples/vanilla/serve-standalone-dist.mjs
# In another terminal, from the repository root:
node scripts/test-loomark-preview-worker.mjs
# Offline probe now passes after application load while the HTTP Worker asset is blocked:
node scripts/loomark-preview-worker-offline-probe.mjs
# Optional Rabbita lifecycle fixture:
MOON_HOME=/tmp/loomark-toolchain-aug19 bash scripts/build-loomark-preview-worker.sh --fixture
node scripts/test-loomark-preview-fixture.mjs
```

The archived headful driver is `driver-headful.mjs.txt`; copy it to an `.mjs`
file and adapt its absolute import path if the checkout moved. For one Split,
30 ms traced repetition:

```bash
xvfb-run -a env URLBASE=http://127.0.0.1:4325/ TRACE_ALL=1 REPETITIONS=1 \
  MODE=Split INTERVAL_MS=30 OUTDIR=/tmp/loomark-worker-preview \
  node /tmp/driver-headful.mjs
# Repeat with URLBASE='http://127.0.0.1:4325/?preview-worker=1' for Worker mode.
```

## Evidence

- [Summary](../evidence/2026-09-08-loomark-worker-preview/summary.json) and [outlier spans](../evidence/2026-09-08-loomark-worker-preview/outlier-spans.json)
- [Source manifest](../evidence/2026-09-08-loomark-worker-preview/source-manifest.json) and [toolchain](../evidence/2026-09-08-loomark-worker-preview/toolchain.txt)
- [Final Worker E2E](../evidence/2026-09-08-loomark-worker-preview/final-e2e.txt), [local E2E](../evidence/2026-09-08-loomark-worker-preview/local-e2e.txt), [units](../evidence/2026-09-08-loomark-worker-preview/unit-final.txt), and [build](../evidence/2026-09-08-loomark-worker-preview/build-cleanup.txt)
- [2026-09-09 manifest](../evidence/2026-09-09-loomark-worker-offline-dispose/manifest.json), [offline RED/GREEN](../evidence/2026-09-09-loomark-worker-offline-dispose/cold-red.txt) / [probe](../evidence/2026-09-09-loomark-worker-offline-dispose/cold-green.txt), and [lifecycle RED/GREEN](../evidence/2026-09-09-loomark-worker-offline-dispose/dispose-red.txt) / [fixture](../evidence/2026-09-09-loomark-worker-offline-dispose/dispose-green.txt)
