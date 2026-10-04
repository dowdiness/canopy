# Loomark local tabs — Worker experiment

> Draft synthetic-only experiment; no merge or production rollout is authorized.
> [CODEX_HANDOFF.md](CODEX_HANDOFF.md) records the fixes and separates historical
> measurements from current-commit verification on PR #1450.

Explicit experimental Text mode in the real Loomark `app()` entry. It reuses
MarkdownEditor.input_view/admit, TextArea/TextChange, Rabbita rendering and local
subscription disposal. It is not a production Source/DocumentReplica migration,
and it does not integrate the ordinary Catalog, Preview, account or server sync.
The experimental controls/style are deliberately limited to synthetic Text.

## Build and run

Use the repository's pinned submodules, MoonBit/compiler core 0.10.14+7d59c7ec9,
Node 24.11.1 and installed Chrome. The independent EGW checkout must be a sibling
of the Canopy checkout, named `egw-trial`, at commit
07a6a833ed9442eee26d463375f589864539b864 (manifest version 0.8.0). This includes
PR134 and experimental PR135. No submodule pointers are changed by this trial.
The `moon.work` here isolates this override from the ordinary root workspace.

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
moon check ../../internal/local_tabs --target js --deny-warn
moon build ../../main --target js --release
moon build engine/main --target js --release
moon build fixture --target js --release
cp _build/js/release/build/dowdiness/loomark/main/main.js loomark.js
cp _build/js/release/build/trial/local_tabs/main/main.js egw.js
cp _build/js/release/build/dowdiness/loomark/experimental/local-tabs/fixture/fixture.js fixture.js
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
  basis and the admitted merged union. This costs extra Worker restore time and
  memory; no second CRDT is rebuilt on the main thread.
- No editing until restore verifies Version/pending and returns text. Native
  input then changes the textarea immediately and queues every exact intent.
  An already admitted terminal input retains its native text and original basis
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
- Switching synthetic documents retains each session and its pending lane; old
  response IDs/epochs/document IDs cannot mutate another document. Workers are
  terminated at actual Rabbita local-scope disposal. No general cache/GC added.
- Schema2 admission/resource limits remain. Compact seed max100k accepted ops;
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
node browser-test.mjs
node fault-test.mjs
node performance-test.mjs
node trace-test.mjs
$env:HEADED='1'
node browser-test.mjs
node fault-test.mjs
node performance-test.mjs
node trace-test.mjs
```

`browser-test.mjs` includes separated-hunk ReplaceAll Undo/Redo alongside the
two-tab, Unicode, selection, save and admission boundaries. `fault-test.mjs`
adds terminal composition during Worker loss and a blocked transaction failure,
Saved→termination, missing edit reply, delayed remote projection, transaction
fault phases, readonly restore, A→B→A, unresolved Undo, and >100k missed ops.
`TEST_FILTER` selects named cases in those two scripts for diagnosis; omit it
for full verification. Fault injection belongs only to experimental assets.

Performance reports separate load→ready, Worker restore/replay, local input,
local acceptance, remote application and IDB commit. Double rAF is a presentation
opportunity proxy, not pixel paint. Chrome traces include navigation through
usable text and renderer main RunTask durations, excluding dedicated Worker
threads; raw traces are gzip JSON. Headed browser input is not actual OS IME.

Actual Japanese OS IME remains unverified. Synthetic composition events and
headed Chromium, including Linux/Xvfb runs, do not establish OS IME correctness.

See BOUNDARIES.md for the reference/reuse decisions and fault matrix. Root full
workspace validation belongs to repository CI; local results must identify the
actual affected-package/module scope and not be called whole-repository CI.
