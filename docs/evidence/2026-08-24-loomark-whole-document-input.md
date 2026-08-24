# Loomark whole-document input characterization

- **Issue:** [#1353](https://github.com/dowdiness/canopy/issues/1353)
- **Baseline:** `60ef805ca502cc5963e919fce9a263b0587d0f1d`
- **Decision:** `persistence_first`

## Result

At 1 MiB, the production 250 ms flush window produced a long task in every
measured sample. The per-sample maximum W2 long-task duration was 66 ms at p50,
94 ms at p95, and 127 ms maximum. A one-line throwaway counterfactual that
returned before `prepare_local_text` reduced W2 long-task incidence from 30/30
to 5/30 and reduced p95 to 52 ms (`0.553×`). The immediate native-mutation p95
did not regress.

This satisfies the project material-win threshold for the targeted boundary.
The first production slice should therefore coalesce revision-bound persistence
intents before complete-source materialization and encoding. The
counterfactual itself is not a production design: it disabled durability and
was removed after measurement.

## Production path

The measured path has three observable windows:

```text
W0  textarea mutation and immediate input dispatch
W1  0 ms RawFastPreview / publication / reconciliation
W2  250 ms RawFastFlush / LocalText preparation / IndexedDB request
```

Source locations:

- Rabbita reads the text control value in
  `deps/rabbita/rabbita/html/html_utils.mbt:397-440`.
- Loomark installs the browser draft and schedules preview and flush in
  `apps/loomark/internal/rabbita/application.mbt:521-550`.
- The delays are 0 ms and 250 ms in
  `apps/loomark/internal/rabbita/text_control_repair.mbt:48-52`.
- `RawFastFlush` reaches LocalText replacement in
  `apps/loomark/internal/rabbita/application.mbt:1171-1234`.
- `local_text_replacement` prepares the complete record before enqueueing it
  in `apps/loomark/internal/rabbita/document_transaction.mbt:114-130`.
- `prepare_local_text` constructs and stringifies the complete Source record
  in `apps/loomark/repository/repository.mbt:245-255`.
- Publication is rebuilt in
  `apps/loomark/internal/rabbita/application.mbt:325-400`.
- The current Rabbita textarea uses `field-sizing:content` in
  `deps/rabbita/rui/textarea.mbt:2`.

## Method

The release Warren build ran in headless Chromium 149.0.7827.55 on Linux WSL2
with an AMD Ryzen 7 6800H. Each size and surface used a fresh browser process,
a 1280×720 viewport, five warmups, and thirty real-keyboard samples. Fixtures
were deterministic ASCII Markdown with recorded SHA-256 hashes.

The native control reused the production textarea's inline style and measured
736 px width. The runner recorded:

- `beforeinput` to `input`;
- `input` to the event-loop microtask;
- `input` to IndexedDB `put` request;
- request to acknowledgment; and
- long-task offsets and durations during the following 400 ms.

Three representative 1 MiB traces were recorded separately from the
distribution run. Trace category durations can overlap and are not additive.

## Scaling baseline

| Source | Surface | Native mutation p50 / p95 | IDB request offset p50 / p95 | Samples with long task |
|---:|---|---:|---:|---:|
| 64 KiB | matched native textarea | 2.2 / 3.5 ms | n/a | 0/30 |
| 64 KiB | Loomark production | 3.3 / 13.0 ms | 253.4 / 262.0 ms | 0/30 |
| 256 KiB | matched native textarea | 8.7 / 10.0 ms | n/a | 0/30 |
| 256 KiB | Loomark production | 22.4 / 39.5 ms | 264.1 / 283.7 ms | 1/30 |
| 1 MiB | matched native textarea | 37.0 / 45.5 ms | n/a | 0/30 |
| 1 MiB | Loomark production | 36.0 / 57.4 ms | 316.6 / 344.4 ms | 30/30 |

The 1 MiB IndexedDB acknowledgment itself was 0.5 ms at p50 and 38.0 ms at
p95. More importantly, the request did not begin until 66.6–94.4 ms after the
nominal 250 ms flush boundary at p50/p95.

## Representative trace

Across the three 1 MiB traces:

- W0 lasted 35.7–45.6 ms and included 20.1–23.3 ms of style/layout;
- the 240 ms guard-band probe through the IndexedDB request lasted
  82.1–91.9 ms;
- that probe contained 71.6–81.2 ms of traced `FunctionCall` overlap; and
- each trace observed a 71–81 ms long task beginning near the actual 250 ms
  flush boundary.

The trace probe starts 10 ms before the nominal timer so scheduling jitter
cannot hide the task start. Its elapsed value is not presented as the exact
flush duration; the independently observed long tasks begin at approximately
250 ms.

W1 also contained substantial paint and occasional GC or script work. It
remains a measured follow-up concern, but it was not larger than W2 and was not
needed to select the first cut.

## Counterfactual

The only throwaway application change was based on
`60ef805ca502cc5963e919fce9a263b0587d0f1d` with a dirty working tree:

```diff
- guard model.archive_persistence_enabled else {
+ guard false else {
```

in `local_text_replacement`, before `prepare_local_text`. The runner used:

```text
LOOMARK_WHOLE_DOCUMENT_SIZES=1048576
LOOMARK_WHOLE_DOCUMENT_REQUIRE_PERSISTENCE=0
```

| 1 MiB W2 metric | Production | Persistence disabled | Ratio |
|---|---:|---:|---:|
| Samples with W2 long task | 30/30 | 5/30 | 0.167× incidence |
| Per-sample maximum W2 long task p50 | 66 ms | 0 ms | 0× |
| Per-sample maximum W2 long task p95 | 94 ms | 52 ms | **0.553×** |
| Per-sample maximum W2 long task maximum | 127 ms | 52 ms | **0.409×** |
| Immediate native-mutation p95 | 57.4 ms | 36.8 ms | 0.641× |

The machine-readable evidence marks the counterfactual as dirty and records a
digest of the patch description; it does not identify the modified build as an
exact checkout of the baseline commit.

The counterfactual proves that persistence work before or around record
materialization is a material W2 contributor. It does not by itself distinguish
JSON construction, stringify, queue construction, command scheduling, or the
memory pressure those operations create. The production child should move the
materialization boundary rather than add a permanent persistence-disable mode.

## Reproduction

Build the release standalone output and install browser dependencies:

```bash
./scripts/test-loomark-standalone-e2e.sh --list
```

Run the production baseline and representative traces:

```bash
cd apps/loomark/examples/vanilla
LOOMARK_WHOLE_DOCUMENT_TRACE_SAMPLES=3 \
LOOMARK_WHOLE_DOCUMENT_OUTPUT=/tmp/loomark-whole-document-input.json \
  npm run bench:whole-document-input
```

The complete raw samples, environment, fixture hashes, trace summaries, exact
counterfactual description, and comparison are in
`2026-08-24-loomark-whole-document-input.json`.

## Limitations

- Absolute timings are from one headless Chromium host.
- The matched native control showed cross-process variance. It establishes a
  browser surface floor but does not justify an editing-surface migration.
- Trace categories overlap and must not be summed.
- Only end insertion was required to choose the first complete-source boundary.
  The selected production implementation must run the broader #1351
  correctness and sustained-input matrix.

## Next slice

Create one bounded production issue under #1351 and coordinate it with #1347:

```text
accepted revision
  → enqueue replaceable persistence intent
  → coalesce to latest intent
  → materialize selected snapshot
  → encode and write IndexedDB
  → acknowledge durable revision
```

Do not add a durable operation tail or make persistence define canonical
acceptance.
