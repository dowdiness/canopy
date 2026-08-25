# Loomark persistence-intent coalescing

- **Issue:** [#1360](https://github.com/dowdiness/canopy/issues/1360)
- **Initial base:** `298f3ccf527de1447adde3bcab82140dd4eaddb2`
- **Initial measured code:** `0458a5827598bcdec4a14c956b8d93dd43e9ec73`
- **Paired-guard base:** `1f24c66042115763040a029d05fc753eb30902a4`
- **Paired-guard measured code:** `8b792bf495000549aa0f9664871a2c8a3da7dec9`
- **Decision:** `STOP` after implementing the selected boundary

## Result

Loomark now queues standalone LocalText as an immutable unencoded source intent.
The existing persistence queue keeps one selected write and one replaceable
latest value. It materializes and encodes LocalText only after that value has
been selected as the first write or promoted after the preceding
acknowledgment. A superseded pending source never reaches `prepare_local_text`.

This establishes the required boundary for later bounded checkpoint scheduling,
but it does not make one selected 1 MiB checkpoint cheap. Three 30-sample
candidate launches had a median W2 per-sample maximum long-task p95 of 91 ms,
equal to the current-main baseline and above the historical 70.5 ms material-win
gate. The complete 64 KiB/256 KiB/1 MiB candidate matrix reproduced the same
cliff: no W2 long tasks at 64 KiB or 256 KiB, and 30/30 samples with a W2 long
task at 1 MiB.

Per #1360's stop condition, this result does not authorize a Worker, chunked
encoding, a new record format, or a second persistence queue.

## Boundary change

Before:

```text
accepted LocalText source
  -> prepare_local_text and stringify
  -> enqueue prepared replacement
  -> discard an older prepared pending replacement
```

After:

```text
accepted LocalText source
  -> enqueue immutable unencoded payload
  -> replace older pending payload
  -> select first or promoted write
  -> storage shell requests exact LocalText v1 encoding
  -> IndexedDB replacement
  -> correlated acknowledgment
```

The FullHistory path still queues an already prepared replacement. Both payload
kinds reuse `LocalArchivePersistenceQueue`, `LocalArchivePendingWrite`, request
identity, document identity, queue epoch, opaque document version, completion,
failure, and retry transitions.

`prepare_local_text` is total for valid `String` and `LoomarkDocumentId` inputs.
It constructs and stringifies a MoonBit `Json` value and has no recoverable
preparation-failure channel. `PreparationFailed` remains the fallible
FullHistory-capture category; LocalText's fallible shell boundary begins at the
correlated IndexedDB replacement.

## Correctness evidence

Repository tests cover:

- the first LocalText intent becoming the selected write;
- two different pending sources coalescing to the latest without exposing an
  intermediate write;
- byte-identical LocalText v1 encoding after promotion;
- LocalText failure and retry;
- A→B→A request-identity fencing;
- a LocalText payload superseding a prepared pending payload;
- existing prepared FullHistory promotion, stale completion, document switch,
  queue epoch, failure, and retry behavior.

The standalone browser test now holds A's real IndexedDB transaction-completion
callback, accepts and flushes B and then C while A remains in flight, releases
A, and observes exactly two LocalText puts: A and C. Both encoded values are
measured at the exact expected UTF-16 length; reload restores C. This traverses
`queue.complete → Promoted → update_archive_queue → local_archive_write_command
→ archive_storage.replace → pending.encoded → IndexedDB`.

Validation completed before measurement:

- repository JS tests: 19/19;
- internal Rabbita JS tests: 162/162;
- Loomark module JS tests: 7,508/7,508;
- standalone browser tests: 16/16;
- independent MoonBit review: PASS with no remaining blocker or warning;
- generated repository interface: two intentional additive methods and no
  trait-bound drift.

The persistence effect remains a one-shot Rabbita `Cmd`; no `Sub` or second
scheduler was added. `record_kind()` does not materialize LocalText, and the
storage adapter calls `encoded()` exactly once for the selected write.

## Performance method

The release standalone build ran in headless Chromium 149.0.7827.55 on Linux
WSL2 with an AMD Ryzen 7 6800H, Node v24.14.1, and a 1280×720 viewport. Each
scenario used a fresh browser process, five warmups, thirty real-keyboard
samples, persistence required, and a 400 ms observation window. The 1 MiB ASCII
fixture had SHA-256
`bd2b39512f137e45eb14063920e77769422728321640fc9214787e00a5dd74ae`.

W2 is the 200–400 ms interval after input, containing the nominal 250 ms quiet
flush. The per-sample W2 value is the maximum long-task duration in that
interval. The raw samples retain every 0–400 ms long-task offset and duration;
the W2 summaries apply the 200 ms lower bound. The checked-in runner now emits
this bounded W2 summary directly.

### Current-main baseline

| Metric | Base `298f3ccf` |
|---|---:|
| W2 samples with long tasks | 30/30 |
| W2 maximum long task p50 | 68 ms |
| W2 maximum long task p95 | 91 ms |
| W2 maximum long task maximum | 91 ms |
| IndexedDB request offset p95 | 341.3 ms |
| IndexedDB acknowledgment p95 | 32.5 ms |
| Native mutation p95 | 37.5 ms |
| Input-handler p95 | 0.1 ms |

### Candidate launches at 1 MiB

| Launch | W2 incidence | W2 p50 | W2 p95 | W2 max | Put offset p95 | Ack p95 | Native p95 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 30/30 | 66 ms | 113 ms | 191 ms | 364.0 ms | 37.9 ms | 41.5 ms |
| 2 | 30/30 | 66 ms | 91 ms | 92 ms | 341.9 ms | 34.0 ms | 65.0 ms |
| 3 | 30/30 | 68 ms | 90 ms | 106 ms | 340.9 ms | 32.0 ms | 37.3 ms |
| **Launch median** | **30/30** | **66 ms** | **91 ms** | **106 ms** | **341.9 ms** | **34.0 ms** | **41.5 ms** |

The first and second launches show host noise in different metrics. The stable
conclusion is not a regression magnitude: every launch missed the 70.5 ms gate,
and the median W2 p95 was unchanged from the current-main baseline.

### Candidate size matrix

| Source | W2 incidence | W2 p95 | Native p95 | Input-handler p95 | Put offset p95 | Ack p95 |
|---:|---:|---:|---:|---:|---:|---:|
| 64 KiB | 0/30 | 0 ms | 3.5 ms | 0.1 ms | 254.1 ms | 2.1 ms |
| 256 KiB | 0/30 | 0 ms | 9.1 ms | 0.1 ms | 257.8 ms | 4.5 ms |
| 1 MiB | 30/30 | 89 ms | 37.4 ms | 0.1 ms | 339.5 ms | 38.9 ms |

### Counterbalanced immediate-input guard

The initial launch medians left the `1.10×` native-mutation guard unresolved:
41.5/37.5 was `1.1067×`, while the size matrix reported 37.4 ms. Before the
follow-up samples were observed, the comparison was fixed as five adjacent
base/candidate pairs with alternating order (`B-C`, `C-B`, `B-C`, `C-B`,
`B-C`). Each launch used five warmups and thirty 1 MiB samples. The decision
statistic is the median of the five candidate/base native-mutation p95 ratios;
the gate passes when that statistic is at most `1.10`.

| Pair | Order | Base native p95 | Candidate native p95 | Ratio |
|---:|---|---:|---:|---:|
| 1 | B-C | 38.2 ms | 36.2 ms | 0.9476× |
| 2 | C-B | 34.6 ms | 34.5 ms | 0.9971× |
| 3 | B-C | 38.2 ms | 35.8 ms | 0.9372× |
| 4 | C-B | 42.7 ms | 35.8 ms | 0.8384× |
| 5 | B-C | 42.7 ms | 40.3 ms | 0.9438× |
| **Median** | — | **38.2 ms** | **35.8 ms** | **0.9438×** |

The maximum paired ratio was `0.9971×`. Input-handler p95 was 0.1 ms for every
base and candidate launch. The immediate-input guard therefore **passes**.
The same launches retained the selected-checkpoint STOP result: candidate W2
long-task p95 had an 87 ms launch median and remained above 70.5 ms.

## Materialization and durability accounting

The runner observed one acknowledged LocalText `put` per measured sample. Code
inspection and independent review confirm that `storage.replace` calls the
selected write's `encoded()` method exactly once. The thirty measured 1 MiB
samples therefore performed thirty selected materializations and encoded
31,460,955 UTF-16 units in total, ranging from 1,048,684 to 1,048,713 units per
sample as the fixture grew.

No superseded intent was materialized in the deterministic queue matrix. The
browser runner deliberately exercises one idle selected checkpoint per sample,
so it measures the remaining selected-checkpoint cost rather than a coalescing
burst.

IndexedDB request and acknowledgment timings are reported separately above. In
this pre-#1351 LocalText model, ordinary source edits do not yet receive the
independent revision-bound `TextSnapshot` required by #1347, so the runner
cannot honestly report a distinct advancing durable revision. A successful
correlated acknowledgment still remains the only event that advances the
existing durable status; revision-bound checkpoint progress remains owned by
#1351 and #1347.

## Decision

Keep the unencoded latest-intent boundary. It removes provably wasted
materialization when pending work is superseded and is required before adding
#1347's max-wait checkpoints. Do not claim that it fixes the single selected
1 MiB checkpoint. That checkpoint remains complete-source JSON work and still
creates a long task.

Further work requires a separate evidence-backed decision after #1351 provides
revision-bound snapshots. This issue does not authorize guessing between
Worker placement, chunking, or a different Source representation. The
counterbalanced immediate-input guard passes; that result does not change the
selected-checkpoint STOP.

The compact machine-readable result and raw-run digests are in
[`2026-08-24-loomark-persistence-intent-coalescing.json`](2026-08-24-loomark-persistence-intent-coalescing.json).
The complete baseline, three candidate launches, and candidate size-matrix
samples are in
[`2026-08-24-loomark-persistence-intent-coalescing-raw.json`](2026-08-24-loomark-persistence-intent-coalescing-raw.json).
The ten counterbalanced immediate-input launches are in
[`2026-08-24-loomark-persistence-intent-immediate-input-paired-raw.json`](2026-08-24-loomark-persistence-intent-immediate-input-paired-raw.json).
