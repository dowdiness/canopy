# Loomark local-tabs Worker: Codex handoff

Status: **draft handoff only; not merge-ready** (2026-10-03).

## 日本語の引き継ぎ

Loomark の実際の Text エディターから、合成文書だけを使う Worker / EGW
実験へ入る作業途中のスナップショットです。本番採用・マージ・デプロイの
承認ではありません。既存の測定結果と、このブランチの検証状態を分けて
扱ってください。まず下記の未解決項目を再現し、修正後のコミットで通常の
フックと CI を実行してください。

## Source provenance and scope

- Repository base: `dowdiness/canopy` at
  `122735058b798009a915ea7513ecb4f511dbede4`.
- Current `main` was identical to that base when checked on 2026-10-03.
- Source: `loomark-worker-a6.zip`, 7,598,071 bytes, SHA-256
  `210cc02beb0f20115a6792b342d91fed8f5a815bc693e3f94ea3b52c0b728300`.
  All 70 entries in its source manifest matched their recorded hashes.
- This archive is the **pre-fix export**. Five current A6 files were then
  recovered through authorized file upload and overlaid: client.mjs,
  fault-test.mjs, README.md, FOLLOWUP-REVIEW.md, and RESULTS.md. Their new
  behavior has not been runtime-validated. This is not a full latest-tree export.
- Imported source only: the app's opt-in branch/import, internal binding,
  experimental implementation, pinned dependency manifests, and test sources.
  Generated JavaScript, node_modules, screenshots/traces, and delivery metadata
  are omitted. The small `pkg.generated.mbti` API declaration is retained.
- Import adjustments: normalize text line endings to LF; restore the checkout's
  loopback server port 4182 (the portable export used 4183); add this handoff and
  explicitly label historical validation; redact a machine-specific user path
  and private artifact identifier from the recovered review note. No additional
  runtime correctness fix was made during handoff preparation.
- No production storage migration, account enrollment, server sync, submodule
  pointer change, merge, or deployment is included.

## Must resolve before implementation review

1. **ReplaceAll is split into multiple Undo groups.** `worker.mjs` expands a
   full replacement into diff hunks and calls `egw.replace` for each; the engine
   `replace` calls `undo.stop_capturing()` around every hunk. Add a regression
   with separated hunks and prove one Undo/Redo represents one native intent.
2. **Composition commit can be dropped during recovery or blocked state.**
   The original `client.mjs` rejected `onChange` while `!ready || blocked`. The
   recovered patch queues an existing-basis edit during `!ready`, but still
   rejects it while explicitly blocked even after binding admission. Reproduce Worker
   loss and persistence failure during composition, then terminal composition
   input. Preserve original basis, native text, intent, and honest Not saved
   status. A `!ready` fix alone does not establish correctness while blocked.
3. **Unacknowledged history action must remain explicit.** The pre-fix export's
   Retry canceled an interrupted Undo/Redo. Recovered A6 edits now retain history
   requests on any error and require a separately confirmed cancellation.
   The exact source changes and added fault tests are included, but the new
   regressions have not been run. Review and test this change before promotion.
4. Recheck normal-mode isolation, interrupted/repeated flows, and actual
   Rabbita disposal. Keep accepted packets immutable until matching IndexedDB
   transaction completion; ordinary Preview's latest-only policy is unsuitable.
5. Real Japanese OS IME remains unverified. Synthetic composition events and
   headed Chrome do not establish OS input-method correctness.

Other retained limitations: expensive synchronous Worker restore, two Worker
replicas, no stable provenance-based cursor anchors, no archived local Undo,
known concurrent-delete Undo revival, and no durability for volatile edits lost
before IndexedDB commit. Use synthetic text only.

## Version-separated evidence

### Original export, 2026-10-02

`RESULTS.md` records historical results: 11 pure tests, 12 browser scenarios,
10 fault scenarios, 3 lifecycle scenarios, normal-mode isolation, and 388
affected Loomark tests. Browser/fault/lifecycle tests were reported in headless
and headed Chrome. These are **not results for the eventual PR commit**.

The original headed 100k traces sampled three basic and three churn reopens:
renderer-main RunTask maximum 9.557 ms; Ready medians approximately 2.17 s and
2.85 s. These samples do not establish a universal performance guarantee or
validate later source changes. Original detailed evidence stays in the archive.

### Source-only handoff preparation, 2026-10-03

- Export archive and all manifest hashes verified.
- All imported `.mjs` files pass `node --check`.
- Dependency-free `node --test protocol.test.mjs`: 3 passed.
- No dependency installation, MoonBit compilation, browser run, normal commit
  hooks, normal push/Lefthook, or full-workspace CI was run for this candidate.
- A6's command runtime failed even for a basic location query, before project
  commands could execute. No credential access or permission workaround was
  used. The earlier export also reported missing `just`/`lefthook`.

The user requested a draft PR specifically as a Codex handoff despite this
execution blocker. API publication, if used, does **not** satisfy the normal
push requirement in `docs/development/workflow.md`. Every unchecked gate remains
required before this becomes an implementation-ready PR.

## Resume and verify

Read repository `AGENTS.md`, `docs/README.md`, Loomark `README.md` / `CONTEXT.md`,
and applicable workflow/reuse/review guidance first. Fetch current main and
reconcile any movement. PR #1421 is a separate Worker Preview experiment; its
only overlapping file with this handoff is `apps/loomark/app/app.mbt`. Preserve
both entry/lifecycle responsibilities rather than merging that branch wholesale.

Use the official pinned MoonBit/compiler core `0.10.14+7d59c7ec9`, Node
`24.11.1`, recursive repository submodules, and a sibling `egw-trial` checkout at
`07a6a833ed9442eee26d463375f589864539b864` (manifest version 0.8.0).
Verify dependency identity and reachability; do not change submodule pointers
to make this isolated trial compile. The nested `moon.work` owns this override.

On the documented Windows/Chrome setup, from this directory:

```powershell
npm ci
.\build.ps1
node --test core.test.mjs protocol.test.mjs
node serve.mjs
```

In a second terminal at the same directory, with the server still running:

```powershell
node browser-test.mjs
node fault-test.mjs
node lifecycle-test.mjs
node normal-mode-test.mjs
node performance-test.mjs
node trace-test.mjs
$env:HEADED='1'
node browser-test.mjs
node fault-test.mjs
node lifecycle-test.mjs
node performance-test.mjs
node trace-test.mjs
```

Most browser scripts currently hard-code
`C:/Program Files/Google/Chrome/Application/chrome.exe`; only browser-test.mjs
accepts `CHROME_PATH`. Review a portability change before running on another OS.
Performance runs must be serial. Build outputs and dependencies are deliberately
absent from this source handoff and must be regenerated, never copied from an
older bundle to claim final-source validation.

Add the failing regressions above first. Then run the affected MoonBit strict
checks/release tests and normal repository hooks against the candidate commit.
Review the generated `.mbti` diff and get independent persistence/concurrency
review. Push normally without bypassing Lefthook and verify GitHub's required
`All Checks Passed` aggregate for the exact commit before considering merge.

The reusable boundary matrix and API decisions are in `BOUNDARIES.md`. This
document is a temporary handoff, not a replacement for the repository backlog.
