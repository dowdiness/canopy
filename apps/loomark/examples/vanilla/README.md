# Loomark browser tests

This directory contains the Node and Playwright dependencies shared by two
separate browser boundaries.

- `dev-host.spec.ts` exercises the disposable private development driver. It
  owns one fresh connected mount per BrowserContext and observes detached
  snapshots, typed event effects, and Rabbita timing.
- `standalone.spec.ts` exercises only the Warren production output through its
  visible Raw editor, Block editor, and Preview controls. It imports no private
  driver module.

Neither boundary is a public Browser App/Session contract.

`scripts/test-loomark-dev-host-e2e.sh` builds both the private driver and the
projection Worker comparison asset, stages the Worker beside the file-backed
test page for the duration of the run, and removes the staged asset on exit.

## Behavioral and lifetime test inventory

| Boundary | Harness assertion | Lifetime claim |
| --- | --- | --- |
| Fresh connected host | one application mounts once into one connected container | mount ownership starts only after the fresh host is validated |
| Second mount | a second mount attempt is rejected by the private driver | no host reuse or remount |
| Page/process termination | the isolated page/context closes to end the run | termination is the only lifetime end; runtime cleanup is unclaimed |
| Source/mode/event/error/focus | typed source, mode, editor, error, and focus operations remain independent of host lifetime | application behavior is testable without teardown |
| Immediate reads / after-render writes | snapshots read committed state immediately; focus, selection, and measurement write/read after the corresponding render command | no synchronous read-after-write assumption |
| Selection / measurement | supported capabilities succeed; unsupported or failed capabilities report typed boundary errors | DOM capability semantics belong to `dom-boundary` |
| Listener load / tagger refresh / unload | one retained-key test listener is installed, its source-dependent tagger refreshes through `RunningSub.update_tagger`, unload removes it exactly once, and repeated cleanup stops delivery | control transport remains available while the test listener is stopped |
| Fatal driver state | fatal application errors reject later private driver operations with an operation/reason snapshot | the control listener remains reachable so rejection is observable; no teardown claim is made |
| Forbidden paths | no clear, reuse, remount, transfer, or cleanup approximation appears in a case | a new page/process is used for every isolated case |

The one mount-ownership site in the private adapter is the migration point that
#1072 will replace with Rabbita `MountedApp::unmount`. That migration must add
disposal, repeated-unmount, fatal-cleanup, reentrancy, remount, and host-reuse
tests before deleting this adapter and harness.

## Gate R0 browser oracle corpus

`fixtures/r0-browser-v1/browser-fixture-catalog-v1.json` binds five fixed
1,000-event complete-v1 archives to their archive, text, and history hashes and
to the exact first edit: append U+005A at the restored text's UTF-16 end. The
browser fetches and verifies those assets itself before seeding the production
local-archive path; candidate restore is not selected by this oracle.

```bash
npm run fixtures:r0:generate  # regenerate through EGW LegacyOracleEventV1 + v1 encoder
npm run fixtures:r0:test      # catalog, digest, archive, and fail-closed controls
npm run fixtures:r0:verify    # regenerate in a temporary directory and byte-compare
```

The canonical Gate R0 runner owns both the fresh-Chromium correctness run and
the fixed browser measurement lane. It builds release JavaScript, assembles the
production Warren static output, pins Chromium `149.0.7827.55`, warms each
fixture once, then performs 20 measured reloads. Every measured reload restores
the fixed full-history archive, appends U+005A as a real browser edit, and waits
for the resulting complete archive replacement.

Raw samples and nearest-rank summaries are retained for the IndexedDB storage
read, the black-box interval from storage completion to expected text, total
restore-to-text observation, first edit to persisted archive, its IndexedDB
write transaction, and restore plus first edit. The valid fixture corpus has no
recovery run, so fallback/error timing is explicitly not applicable. Candidate
A/C browser timing is likewise `not_applicable: product_restore_seam_absent`;
the lane must not present plain-text import as candidate restore evidence.

Run the fast schema/invariant checks independently with:

```bash
npm run measurement:r0:test
```

## Startup benchmark

`npm run bench:startup` runs `bench-startup.mjs`, which boots the standalone
static output (the same Warren production surface that `standalone.spec.ts`
exercises) behind a local static server. It measures reload-to-restored-editor
time with repeated samples and reports nearest-rank p50/p95 values.

Without configuration it uses a small synthetic document and history-changing
cycles `[0, 2, 10, 20]`. To measure a Markdown corpus, pass a file or directory
(the directory is searched recursively):

```bash
LOOMARK_STARTUP_CORPUS=/path/to/markdown npm run bench:startup
```

That mode uses the corpus for document size and generates controlled history.
The first generated edit is a full-document replacement, so this is a stress
corpus rather than a claim about a user's operation granularity. For real
persisted histories, pass exported active-archive JSON files instead:

```bash
LOOMARK_STARTUP_ARCHIVES=/path/to/archive-json npm run bench:startup
```

Archive fixtures must be complete v1 active-archive envelopes, including
`schema_version`, `document_id`, `portable_markdown`, `history`, and empty
`extensions`. Archive mode is the preferred input for deciding a replay
threshold; Markdown mode is useful for separating document size from generated
history. `LOOMARK_STARTUP_SAMPLES` controls reload samples (default `20`), and
`LOOMARK_STARTUP_CYCLES` controls generated cycles (default `0,2,10,20`). Paths
are emitted as opaque `document-N` labels by default; set
`LOOMARK_STARTUP_INCLUDE_PATHS=1` when local path labels are useful.

Each result reports archive, Markdown, and history sizes, the individual
reload samples, and p50/p95 startup timings. The first navigation in each
scenario is a warm-up, so these are warm-context reload measurements rather
than cold first-load timings. Output is printed as a `console.table` summary
followed by one JSON line per scenario. The benchmark is a local development
tool — it does not define a CI budget or a production performance guarantee.

## Projection placement benchmark

Synchronous projection is the production default. The dedicated Worker and
main-thread in-process executors remain private comparison placements; they are
selected only with `projection-placement=worker` or
`projection-placement=in-process`. The release output still includes
`projection-worker.js` so the comparison and Worker lifecycle tests exercise the
same build as the production editor. There is no runtime fallback between
placements.

`npm run bench:projection` runs the 2,000/10,000/50,000-line release-browser
matrix. It enables private bounded P0–F tracing with
`projection-benchmark=1`, counterbalances placement order, uses native
single-character edits after the cold Seed, and isolates each run behind a hard
process deadline. Set `LOOMARK_PROJECTION_COMMIT` to the exact harness commit
when retaining evidence. The 2026-08-15 result and raw files are indexed in
[`docs/performance/2026-08-15-loomark-projection-placement.md`](../../../../docs/performance/2026-08-15-loomark-projection-placement.md).

Set `LOOMARK_MAIN_THREAD_TRACE=1` to add calibrated Chromium main-thread
intervals for each scenario. `LOOMARK_PROJECTION_PLACEMENTS` accepts a
comma-separated subset when characterizing one placement; the default remains
the counterbalanced three-placement matrix. Main-thread `FunctionCall` time
includes input dispatch and authority work and must not be interpreted as DOM
or paint time. The 2,000-line phase characterization is recorded in
[`docs/performance/2026-08-15-loomark-presentation-critical-path.md`](../../../../docs/performance/2026-08-15-loomark-presentation-critical-path.md).

## Driver seam

The generated JavaScript for `internal/dev_host` is private test infrastructure.
Its exports accept `String`/`Int` arguments and return `Unit` or serialized
status/snapshot `String`s. Each request is encoded in MoonBit, dispatched
through typed `dom-boundary` custom-event APIs (the DOM `CustomEvent.detail` is
a `String`), and decoded into a typed `DriverEvent`; there is no live enqueue
closure or global handle registry. Raw DOM/Rabbita values, `MarkdownApp`,
`MarkdownSession`, and `unmount` are deliberately absent.
