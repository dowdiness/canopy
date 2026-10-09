# Loomark local tabs — Worker experiment

> Draft synthetic-only experiment; no merge or production rollout is authorized.
> [CODEX_HANDOFF.md](CODEX_HANDOFF.md) records the fixes and separates historical
> measurements from current-commit verification on PR #1450.

Explicit experimental Text mode in the real Loomark `app()` entry. It reuses
MarkdownEditor.input_view/admit, TextArea/TextChange, Rabbita rendering and local
subscription disposal. It is not a production Source/DocumentReplica migration,
and it does not integrate the ordinary Catalog, Preview, account or server sync.
The experimental controls/style are deliberately limited to synthetic Text.

## Worker implementation

`engine/main` is the compiled MoonBit module Worker. It owns the FIFO consumer,
typed requests, editing/merged replicas, projection offers and duplicate-command
results. EGW calls stay inside MoonBit; the old JavaScript dispatcher and
`globalThis.egw` string-returning facade are removed.

`worker-native.mjs` adapts browser primitives and the existing `core.mjs` /
`store.mjs` helpers. IndexedDB schema, immutable journal and transaction receipts
are unchanged. `client.mjs` still owns the main-thread controller; this step does
not move that controller into Rabbita or adopt the generic Rabbita Worker
request envelope. The existing structured-clone wire, progress checkpoints,
safe-integer IDs and `changes.approximate` array metadata are retained.

Migration tracking: [#1458](https://github.com/dowdiness/canopy/issues/1458).


## Build and run

Use the repository's pinned submodules, MoonBit/compiler core 0.10.14+7d59c7ec9,
Node 24.11.1 and installed Chrome. Initialize dependencies from the repository
root with `git submodule update --init --recursive`.

This experiment pins EGW at merged commit
`ff5afaf9d155d97d05d48e29fae59938bfb7e0b6` in `deps/loomark-local-tabs-egw`.
Its nested `moon.work` selects that dependency; the ordinary workspace's
`deps/event-graph-walker` pin is unchanged. No sibling checkout is needed.

`npm run build` checks the app binding and Worker package, then builds and copies
three separate assets: `loomark.js`, `worker.js` and `fixture.js`. The Windows
`build.ps1` wrapper selects its optional sibling toolchain and invokes the same
Node build script. Keep `worker-native.mjs`, `core.mjs`, `store.mjs` and the
installed `diff` dependency alongside the served Worker asset.

From this directory:

```powershell
npm ci
.\build.ps1
node serve.mjs
```

On Linux, build the same targets from this directory:

```sh
npm ci
npx playwright install chromium
npm run build
node serve.mjs
```

All browser scripts accept `CHROME_PATH`. Without it, Windows uses installed
Chrome and other platforms use the lockfile-matched Playwright Chromium.
For a Linux virtual display, use `xvfb-run -a node <script>`; add `HEADED=1`
to exercise headed Chromium. A virtual display does not exercise an OS IME.

Open `http://127.0.0.1:4182/?local-tabs-worker=1&doc=synthetic-demo` in two tabs.
Use `&size=10000` or `&size=100000` for synthetic digit seeds. Size/seed only
affects first initialization. Do not use real notes. The explicit query branches
before the normal repository/account initializer. Without experimental assets,
the branch stays read-only and reports missing assets rather than opening notes.
Storage is `loomark-egw-worker-experiment-v1`; no previous schema is migrated.

## Contracts

- Atomic shared immutable compact seed, fresh unique local writer on every
  Worker start, immutable operation union in IndexedDB, receipt deduplication.
  BroadcastChannel carries hints only; polling/focus/pageshow catches up.
- EGW remains in the Worker after restore. Two replicas retain the main display
  basis and the merged operation union. This costs extra Worker restore time and
  memory; no second CRDT is rebuilt on the main thread.
- No editing until restore verifies Version/pending and returns text. Native
  input then changes the textarea immediately and queues every exact intent.
  An already accepted terminal input retains its native text and original basis
  even if recovery or a blocked save has since made the editor read-only.
  Blocked queues remain Not saved until explicit Retry succeeds.
  Remote projection requires matching local revision/basis with no composition
  or pending input. This is not Preview's latest-only operation-dropping policy.
- An accepted packet reaches main memory before main authorizes its transaction.
  Only the exact IndexedDB transaction completion removes that packet. An old
  save acknowledgement cannot clear later input or another document's dirty state.
- Worker failure retains native intents and immutable unsaved packets. Recovery
  reconstructs the accepted basis from whole durable packets plus retained ones,
  then retries without changing IDs of already accepted operations. A fresh
  writer handles newly generated operations. Unload warns while work is unsaved;
  abrupt browser/process loss before commit is not claimed durable.
- The Worker watchdog measures 15 seconds without progress, not total replay
  time. Completed replica restores and whole-packet applications renew only the
  matching request's deadline. Progress never acknowledges an edit or a save.
  A silent Worker exit still triggers recovery with the same retained packet.
- Switching synthetic documents retains each session and its pending lane; old
  response IDs/epochs/document IDs cannot mutate another document. Workers are
  terminated at actual Rabbita local-scope disposal. No general cache/GC added.
  Disposal cancels unfinished native composition/editing state owned by the old
  textarea, but retains accepted intents and unsaved packets for remount recovery.
- Schema2 validation/resource limits remain. Compact seed max100k accepted ops;
  Version512KiB/global4096 intervals. Journal budget200k, conservative union500KiB.
  Capacity failure retains text and operations and displays Not saved. Whole
  packets remain intact even if accumulated missed history exceeds100k ops.
- UTF16/scalar translation is validated. Composition defers remote DOM and keeps
  the original basis. Selection uses bounded text alignment with an explicit
  approximate fallback; repeated characters lack stable provenance anchors.
- Undo records this tab's edits only, with one group per native intent even when
  ReplaceAll expands into separated diff hunks. Consecutive native intents remain
  separate groups. Known concurrent-delete Undo revival and deterministic
  redgreen/greenred overlapping rewrites are unchanged.
  Worker restart, like reopen, clears the old local Undo stack and says so.
  **Undo/Redo interrupted before its response cannot be reconstructed with the
  current EGW API.** It remains an explicit unresolved failure, never silently
  Saved. Retry retains that unacknowledged action. A separate Cancel interrupted
  Undo/Redo button, followed by explicit confirmation, abandons the request and
  restores the previous accepted basis. An already acknowledged Undo packet is retained and
  recovered exactly like any other operation packet.

## Verify

Keep the loopback server running; execute serially when collecting performance:

```powershell
node --test core.test.mjs protocol.test.mjs
node worker-test.mjs
node browser-test.mjs
node fault-test.mjs
node lifecycle-test.mjs
node normal-mode-test.mjs
node performance-test.mjs
node trace-test.mjs
$env:HEADED='1'
node worker-test.mjs
node browser-test.mjs
node fault-test.mjs
node lifecycle-test.mjs
node performance-test.mjs
node trace-test.mjs
```

`worker-test.mjs` posts directly to the real module Worker, bypassing the main
controller's serialization. It checks overlapping delayed requests, IDs and
command sequences above 32 bits, duplicate operation identity, recovery after a
rejected request, committed-save/lost-reply recovery without a second journal
row, and approximate selection metadata after a large rewrite/Undo.


`browser-test.mjs` includes separated-hunk ReplaceAll Undo/Redo alongside the
two-tab, Unicode, selection, save and change-application boundaries. `fault-test.mjs`
adds terminal composition during Worker loss and a blocked transaction failure,
Saved→termination, missing edit reply, delayed remote projection, transaction
fault phases, readonly restore, A→B→A, unresolved Undo, and >100k missed ops.
`TEST_FILTER` selects named cases in those two scripts for diagnosis; omit it
for full verification. Fault injection belongs only to experimental assets.

`lifecycle-test.mjs` exercises actual Rabbita unmount/remount while ready,
opening, accepting an edit, or composing. The composition case cancels unfinished
native input while retaining an earlier accepted edit, then checks new input,
saving and reload. `normal-mode-test.mjs` checks isolation without experimental
assets or storage and creates its own evidence directory when run independently.

Performance reports separate load→ready, Worker restore/replay, local input,
local acceptance, remote application and IDB commit. Double rAF is a presentation
opportunity proxy, not pixel paint. Chrome traces include navigation through
usable text and renderer main RunTask durations, excluding dedicated Worker
threads; raw traces are gzip JSON. Headed browser input is not actual OS IME.

The previously reported missed-history capacity timeout and renderer-main trace
failure remain unresolved. The dispatcher migration and functional passes do
not establish either a capacity fix or the historical performance result.

Actual Japanese OS IME remains unverified. Synthetic composition events and
headed Chromium, including Linux/Xvfb runs, do not establish OS IME correctness.

See BOUNDARIES.md for the reference/reuse decisions and fault matrix. Root full
workspace validation belongs to repository CI; local results must identify the
actual affected-package/module scope and not be called whole-repository CI.

## Local migration verification — 2026-10-04

Linux, compiler/core `0.10.14+7d59c7ec9`, Node `24.14.1`, Playwright Chromium
`153.0.8010.12`, headless. The shared Node build was exercised; the Windows
PowerShell wrapper was not run.

| Check | Observed result |
|---|---|
| `npm run build` | Strict app-binding/Worker checks and all three assets built |
| Core/protocol | 11 passed |
| Direct module Worker contracts | 3 passed |
| Existing browser scenarios | 13 passed |
| Selected fault scenarios | 13 passed; known missed-history capacity case excluded |
| Actual Rabbita lifecycle | 4 passed |
| Ordinary-mode isolation | Passed |
| Explicit Loomark package release tests | 388 passed |

The fault selection covers both terminal-composition failures, Saved→termination,
missing edit replies, delayed remote offers, all three transaction-loss phases,
silent exit after commit, 100k restore gating, A→B→A and both interrupted-Undo
cases. It does not claim the excluded capacity case passes.

A separate live-page check typed `base 日本語😀`, observed Saved, reloaded the
same text with a fresh writer, and found no main-thread EGW global or page errors.
Generated evidence is under ignored `evidence/`; these results are local scoped
verification, not CI, a performance certification, real OS IME coverage or
production approval.

The [archived implementation record](../../../../docs/archive/2026-10-04-loomark-moonbit-worker.md)
records the review corrections, artifact fingerprint and explicit release-test
package selection.
