# Loomark local-tabs Worker: Codex handoff

Status: **draft synthetic-only experiment; not approved for merge or deployment**
(updated 2026-10-04).

The Worker-side migration tracked in
[#1458](https://github.com/dowdiness/canopy/issues/1458) is documented in the
[current README](README.md#worker-implementation). The timeline below describes
the earlier PR #1450 implementation and evidence, not the compiled MoonBit
Worker's current validation. Its capacity/renderer-trace limitations remain
unresolved.

## 日本語の引き継ぎ

Loomark の実際の Text エディターから、合成文書だけを使う Worker / EGW
実験へ入る作業途中のスナップショットです。本番採用・マージ・デプロイの
承認ではありません。既存の測定結果と、このブランチの検証状態を分けて
扱ってください。まず下記の未解決項目を再現し、修正後のコミットで通常の
フックと CI を実行してください。

## Resumed work, 2026-10-04

- Reproduced and fixed both reported bugs: one Undo group now spans all diff
  hunks of a native ReplaceAll; a binding-admitted composition commit is queued
  on its original basis even while blocked. Retry does not discard the intent.
- Added browser regressions for separated-hunk Undo/Redo and terminal Japanese
  composition during Worker recovery and a blocked IndexedDB abort. Both
  regressions failed before the corresponding fix and passed afterward.
- Before the subsequent watchdog correction, fresh headless validation passed:
  11 pure tests, 13 browser scenarios,
  13 fault scenarios, 3 real Rabbita unmount/remount scenarios, and ordinary-mode
  isolation. Scoped strict MoonBit checks and 388 Loomark release tests passed.
  Independent persistence/concurrency and Undo-boundary reviews found no
  high-confidence defects. These are scoped results, not whole-workspace CI.
- Headed revalidation then exposed a further recovery defect: valid 120k replay
  exceeded the fixed 15-second response deadline and repeatedly restarted the
  Worker. The watchdog now measures inactivity, renewed only after actual
  replica restore or whole-packet admission on the matching request. The headed
  120k regression passes without a restart; a separate silent-exit-after-commit
  regression confirms timeout recovery still preserves the identical packet.
  Independent reviewers also checked these progress/ACK boundaries.
- Subsequent final-candidate runs intermittently timed out after inspection or
  test-replay. A deterministic concurrent `inspect` / `catchUp` probe exposed
  diagnostic requests bypassing the pump's ownership guard and blocking the
  editor with `Overlapping Worker request`. Diagnostic requests now hold the
  same per-session `running` guard and resume queued work on release. The probe
  changes from blocked/failure to neither; final suite results belong to the
  exact-commit PR evidence, not the earlier passing runs.
- Fresh Linux/Xvfb traces on `7f1f77116b329a3edf930233feaf84633a5ffb04`
  **failed** the assertion forbidding renderer-main tasks over 50ms: headless 55.846ms,
  headed 50.160ms. The headless overrun included 46.398ms of Layout.
  Functional success does not establish the historical A6 performance result.
  Keep the performance failure visible even if a later sample falls below 50ms.
- Final-commit reruns, performance measurements, normal hook results, and the
  exact GitHub CI head are recorded on [PR #1450](https://github.com/dowdiness/canopy/pull/1450).
  Do not infer a current pass from the historical results below or `RESULTS.md`.
- Browser scripts now support `CHROME_PATH` consistently and default to the
  lockfile-matched Playwright Chromium on Linux. See README for Linux build/run
  commands. Generated bundles, dependencies, and raw `evidence/` remain untracked.
- Actual Japanese OS IME, stable provenance-based cursor anchors, and durable
  local Undo across Worker restarts remain outside the verified claims.

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

## Original findings and current disposition

1. **ReplaceAll Undo grouping — fixed.** The Worker starts a new Undo group
   only on the first diff hunk of each native intent. The regression checks a
   separated-hunk replacement, a following edit, two Undo steps and two Redo
   steps, preserving both grouping and boundaries between intents.
2. **Composition commit during recovery or blocked state — fixed.** Once the
   binding admits an input on an existing basis, the client retains its native
   text and intent regardless of the execution gate. Worker loss and an actual
   IndexedDB transaction abort while composing are covered; Retry and reload
   preserve the committed text. Blocked state remains Not saved.
3. **Unacknowledged history action remains explicit — revalidated.** Retry
   retains an interrupted Undo/Redo request; only separately confirmed
   cancellation abandons it. Fresh fault runs exercise a Worker crash and an
   ordinary error after history execution, including Retry and cancellation.
4. **Isolation, repeated flows, and disposal — revalidated in scoped suites.**
   Accepted packets remain immutable until matching IndexedDB completion;
   ordinary Preview's latest-only policy is not used.
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

Use the dependency setup in the [current README](README.md#build-and-run).
The nested `moon.work` selects the experiment's pinned EGW submodule without
changing the ordinary workspace's dependency.

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

All browser scripts accept `CHROME_PATH`; Linux defaults to the pinned
Playwright Chromium installed with `npx playwright install chromium`.
Performance runs must be serial. Build outputs and dependencies must be
regenerated, never copied from an older bundle to claim final-source validation.

Keep the behavioral regressions above when making further changes. Run the
affected MoonBit strict checks/release tests and normal hooks on each candidate.
Review the generated `.mbti` diff and get independent persistence/concurrency
review. Push normally without bypassing Lefthook and verify GitHub's required
`All Checks Passed` aggregate for the exact commit before considering merge.

The reusable boundary matrix and API decisions are in `BOUNDARIES.md`. This
document is a temporary handoff, not a replacement for the repository backlog.
