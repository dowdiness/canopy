# Loomark startup history corpus measurement

> Status: measurement snapshot. This report does not set a CI budget and does
> not authorize checkpointing or history compaction by itself.

## Baseline and environment

- Baseline: `e53305a7` (`main` after #1237)
- Node: `v24.14.1`
- Chromium: `149.0.7827.55`
- Browser surface: standalone Warren output
- Measurement seam: local archive injection, page reload, restored editor
  readiness, and `#loomark-root` visibility

The benchmark waits for the restored input value, not only for the root shell.
The first navigation warms the browser context; measured samples are subsequent
reloads in the same context. Percentiles use nearest-rank selection.

## Synthetic history scaling

Command:

```bash
cd apps/loomark/examples/vanilla
LOOMARK_STARTUP_SAMPLES=5 npm run bench:startup
```

The final Markdown value is 41 bytes. Each cycle adds and removes one
intermediate revision, so `historyChangingOperations` is `1 + cycles * 2`.

| History-changing operations | Archive bytes | History bytes | Reload p50 | Reload p95 |
|---:|---:|---:|---:|---:|
| 1 | 16,516 | 14,927 | 74.3 ms | 77.1 ms |
| 5 | 186,191 | 170,620 | 117.9 ms | 125.8 ms |
| 21 | 869,123 | 797,624 | 266.0 ms | 289.6 ms |
| 41 | 1,732,953 | 1,590,884 | 575.3 ms | 598.1 ms |

The synthetic result confirms that the one-time replay improvement does not
make startup bounded: replay cost continues to grow with the persisted history.

## Engine phase decomposition

Command:

```bash
cd modules/canopy
NEW_MOON_MOD=0 moon bench --release --target js \
  editor/markdown/markdown_editor_startup_benchmark_wbtest.mbt
```

The fixture contains 100 Markdown blocks and 41 history-changing operations,
mostly full-source replacements. These are diagnostic stress measurements, not
user-operation estimates.

| Phase | Mean | σ |
|---|---:|---:|
| `MarkdownDocumentHistory` JSON decode | 125.2 ms | 8.4 ms |
| `MarkdownEditor::open` (construction + CRDT admission + refresh) | 4.42 s | 0.17 s |
| `open_with_semantic_attachment` | 4.40 s | 0.14 s |
| semantic attachment from source, no history | 96.9 ms | 1.7 ms |

The result changes the implementation priority: for this stress history,
CRDT/editor admission dominates startup. Semantic attachment is not the
primary bottleneck, and deferring only the parser would not approach 16ms.
The `open` and `open_with_semantic_attachment` means are within benchmark
noise; the lower second mean is not evidence that semantic attachment is
faster.

## EGW internal causal-cut prototype

The next EGW step is implemented in the submodule as an internal, non-public
capture prototype (merged in event-graph-walker#117):

- `internal/oplog/causal_cut_prototype_wbtest.mbt` can build an exact immutable causal cut from
  an admitted `OpLog` at an explicit capture boundary.
- `CausalCut` retains stable operation identities, parents, content, origins,
  a derived Lamport timestamp, and an immutable frontier set.
- Whitebox coverage includes immutable snapshots, rebuild equivalence,
  destination-local LV independence, concurrent fresh agents, empty legacy
  inserts, pending remote drain, and partial remote admission prefixes.
- The candidate that maintained a duplicate cut after every admission was
  measured separately and removed after the matched performance gate failed.
- No `.mbti` drift or public checkpoint/restore API was introduced.

Command:

```bash
cd deps/event-graph-walker
NEW_MOON_MOD=0 moon bench --release --target js \
  internal/oplog/causal_cut_benchmark_wbtest.mbt
```

JS release measurements for 1,000 operations:

| Operation | Mean |
|---|---:|
| causal-cut rebuild | 449.3 µs |
| causal-cut equality | 160.0 µs |
| explicit capture from `OpLog` | 546.6 µs |
| frontier read | 51.2 ns |

The prototype establishes the internal evidence seam, not a fresh-writer
restore API. It still does not create a new `TextState` from a retained cut
without replay; that is the next EGW design boundary. The implementation also
hardens legacy `OpRun` handling so empty and multi-character singleton inserts
remain lossless during rebuild and JSON round-trip.

## Matched admission performance gate

The same `admission_overhead_benchmark_wbtest.mbt` was run against the clean EGW
baseline `29f10ec` and the candidate that maintained a duplicate causal-cut
node map after every admission:

| Path | Baseline | Candidate | Change |
|---|---:|---:|---:|
| local, 1,000 ops | 0.666 ms | 2.48 ms | 3.7× |
| local, 10,000 ops | 8.09 ms | 138.4 ms | 17.1× |
| remote, 1,000 ops | 2.50 ms | 3.93 ms | 1.6× |
| remote, 10,000 ops | 30.5 ms | 158.8 ms | 5.2× |
| reverse/pending drain, 1,000 ops | 5.42 ms | 6.68 ms | 1.2× |

**Verdict: NO-GO for duplicating the full causal node map inside every
`OpLog` on the typing path.** The cut shape is valid, but the maintenance
boundary is too expensive for local admission. The next design must reuse the
existing `OpLog`/causal graph as the runtime store and create immutable cut
material only at an explicit capture boundary, or share one coordinator-owned
store instead of maintaining one duplicate map per replica.

## Fresh-writer authority prototype

The next causal-layer boundary is now covered by the test-only prototype:

- `replica_session_prototype_wbtest.mbt` keeps one retained `OpLog` authority
  and gives each page session only a fresh writer ID plus an observed frontier.
- Local operations use the session's parents and writer identity, rather than
  the authority's default writer/frontier.
- `pull()` returns causal retreat/advance operations; `export_since()` uses the
  existing frontier-diff path.
- Coverage includes fresh identities, duplicate delivery, pending dependency
  drain, concurrent peer branches, and partial admission prefixes.

The prototype passes 5/5 focused tests and introduces no production API or
`.mbti` change. It deliberately does not restore `TextState` or `FugueTree`;
the local-operation allocator is test-only until the text materializer and
cross-package API boundary are designed.

## Text materializer prototype

`internal/document/replica_text_session_wbtest.mbt` now connects the causal
boundary to an editable `Document`:

- `attach` creates a fresh `Document` writer and replays the retained
  authority's operations into it once.
- `publish` and `pull` translate a stored RawVersion frontier into the
  destination document's local LVs, then reuse the existing causal graph diff
  and `Document::merge_remote` projection path.
- Identity and conflict handling use `(agent, seq)` plus full payload
  validation, not destination-local LV. This is required because independently
  materialized documents can assign different local versions to concurrent
  operations.
- Coverage includes initial materialization, fresh-writer publish, incremental
  pull, duplicate publish, and concurrent authority/session edits.

The focused materializer tests pass 5/5. JS release measurements are
312.8µs for a 100-operation attach and 6.28ms for a 1,000-operation attach.
The attach measurements use one measured iteration and are descriptive only.
This proves an editable fresh-writer shell, but **not** replay-free startup:
initial attach still replays all history, and the wrapper remains test-only.
The next decision is whether a materialized branch/tree can be safely retained
or cloned without replacing causal history.

## Excluded browser prototype

The throwaway SharedWorker warm-reload probe remains local-only and is
intentionally excluded from this durable measurement snapshot. Its findings do
not establish standalone reload durability, causal-history persistence, or the
fresh-writer production boundary.

## Repository-authored Markdown proxy corpus

This is a proxy corpus, not a user-history corpus. It used four repository
Markdown documents and generated one full-document replacement from the empty
baseline. Three reload samples were measured for each document with
`LOOMARK_STARTUP_CYCLES=0` and `LOOMARK_STARTUP_SAMPLES=3`. With three
samples, the reported p95 is the sample maximum and is descriptive only.

| Source bytes | Archive bytes | History bytes | Reload p50 | Reload p95 |
|---:|---:|---:|---:|---:|
| 2,885 | 1,168,359 | 1,067,072 | 1,461.1 ms | 1,465.3 ms |
| 5,051 | 2,046,946 | 1,869,919 | 3,536.3 ms | 3,798.1 ms |
| 5,273 | 2,133,300 | 1,948,665 | 3,781.3 ms | 3,952.2 ms |
| 8,147 | 3,282,534 | 2,998,689 | 9,200.6 ms | 9,611.5 ms |

The generated full-document replacement is intentionally a stress case. It
shows that archive size can dominate source size, but it must not be presented
as a user's normal editing distribution.

A 39,572-character repository document did not produce a settled archive
within the harness timeout. The DOM input changed, but local storage still
contained the 233-byte empty baseline (`portable_markdown` length 0, history
79 bytes). The harness cannot distinguish the exact provider/admission cause
from this observation; it is evidence that this generated path has a capacity
or operation-size boundary that must be measured explicitly.

## Interpretation

No replay threshold should be chosen from this proxy corpus. The next
measurement input must be complete active-archive JSON captured from real
Editing Documents, because Markdown alone cannot describe causal history or
operation granularity:

```bash
cd apps/loomark/examples/vanilla
LOOMARK_STARTUP_ARCHIVES=/path/to/archive-json \
LOOMARK_STARTUP_SAMPLES=20 \
npm run bench:startup
```

The archive mode reports each archive's portable Markdown size, causal-history
size, and reload p50/p95 through the same standalone seam. After that run,
define an explicit user-visible p95 target and select the checkpoint trigger
from measured causal-history size/replay time. A checkpoint must preserve CRDT
causal frontier semantics; a Markdown-only snapshot is not an acceptable
replacement for the archive.
