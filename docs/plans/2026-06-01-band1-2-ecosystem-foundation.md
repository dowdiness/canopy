# BAND 1-2 Ecosystem Foundation Execution Spec

**Status:** Planning only. This document is an implementation plan, not an implementation record.
**Date:** 2026-06-01
**Design source of truth:** `docs/research/2026-06-01-moondsp-canopy-ecosystem-vision.md`.

This plan is the step-ordered HOW for BAND 1-2 of the converged MoonDsp + Canopy ecosystem vision. It does not re-derive the WHAT. The report's §5.2, §5.7, §7.1, §7.2, §7.3, §2.4/§2.4.1, §7.6, §8.3, and §9 are authoritative.

## Non-Negotiables

- This session is planning only. Do not edit code from this plan while authoring or reviewing this document.
- For Canopy, prefix every `moon` tooling command with `NEW_MOON_MOD=0`, including `moon check`, `moon test`, `moon bench`, `moon fmt`, `moon info`, and every `moon ide ...` command. Without it, MoonBit can migrate `moon.mod.json` to `moon.mod` across many packages.
- After each MoonBit file edit during implementation, run the local compile breakpoint before continuing. In Canopy that means `NEW_MOON_MOD=0 moon check --deny-warn`; in MoonDsp it means `moon check --deny-warn`.
- Run `moon fmt` and `moon info` only at defined breakpoints, and in Canopy always as `NEW_MOON_MOD=0 moon fmt` and `NEW_MOON_MOD=0 moon info`.
- After `moon info`, review generated `.mbti` diffs. Unexpected trait-bound widening is an API regression even when current consumers still compile.
- Before defining any new helper/type/API, do the Existing API First check. In Canopy, use `NEW_MOON_MOD=0 moon ide doc`, `NEW_MOON_MOD=0 moon ide outline`, `NEW_MOON_MOD=0 moon ide peek-def`, and `NEW_MOON_MOD=0 moon ide find-references`; record at least two candidate existing APIs in the PR reuse check, or explain why fewer exist.
- Cross-repo/submodule rule: push submodule commits to remote before updating or pushing the parent repo. Each nested submodule layer is one extra merge gate. Mark and clear every gate explicitly.
- Single-Runtime constraint: cross-runtime reads abort in `incr`, so shared-graph work needs both consumers on the same `incr` build. That is a downstream BAND 3+ unlock only; do not attempt shared graph/runtime work in this plan.

## Scope

In scope, exactly from §7.1:

- 1a. `incr` version convergence: Canopy root `dowdiness/incr` 0.5.2 to 0.6.0, resolving the Canopy root vs `lib/cognition`/MoonDsp skew.
- 1b. Cross-repository coordination mechanism: shared `incr` version-lock file plus CI checks as recommended by §7.3.
- 1c. Submodule nesting flattening and dependency hygiene: remove the `event-graph-walker` double vendoring at `canopy/event-graph-walker` and `canopy/loom/event-graph-walker`; close the loom#150-style standalone dependency problem.
- 2a. MoonDsp `DspNode`/`CompiledTemplate` `Eq`: a MoonDsp NaN-equality policy decision must precede implementation.
- 2b. Canopy O(N) change detection and O(m*n) LCS reconciliation: reproduce and measure first, then decide. This plan does not include the actual optimization patch.

Out of scope:

- 3a MoonDsp pattern-operation defunctionalization. This is the next gate after BAND 1-2.
- 4f MoonDsp graph DSL as a Canopy language.
- Persistence, CLAP/native, and community strategy work.
- Parser adoption, loom mooncakes publish, or MoonDsp production loom adoption. Those are BAND 4g, not 1c.
- The actual 2b optimization beyond reproduce -> measure -> decide.

## Verified Current Paths

Canopy:

- `/home/antisatori/ghq/github.com/dowdiness/canopy/moon.mod.json`: root depends on `dowdiness/incr` 0.5.2.
- `/home/antisatori/ghq/github.com/dowdiness/canopy/lib/cognition/moon.mod`: `dowdiness/incr@0.6.0`.
- `/home/antisatori/ghq/github.com/dowdiness/canopy/loom/incr/scripts/migrate-to-target-facades.py`: actual `incr` codemod path. It is not in Canopy root `scripts/`.
- `/home/antisatori/ghq/github.com/dowdiness/canopy/.gitmodules`: root submodules include `event-graph-walker` and `loom`.
- `/home/antisatori/ghq/github.com/dowdiness/canopy/loom/.gitmodules`: nested submodules include `event-graph-walker`.
- `/home/antisatori/ghq/github.com/dowdiness/canopy/loom/examples/lambda/moon.mod.json`: nested `event-graph-walker` path dependency currently points to `../../event-graph-walker`.
- `/home/antisatori/ghq/github.com/dowdiness/canopy/lang/lambda/proj/flat_proj.mbt`: `to_flat_proj_incremental` O(N) change-detection scan.
- `/home/antisatori/ghq/github.com/dowdiness/canopy/core/reconcile.mbt`: generic LCS reconciliation with O(m*n) child matching.
- `/home/antisatori/ghq/github.com/dowdiness/canopy/lang/lambda/flat/projection_memo.mbt`: existing revision/changed-index pattern.
- `/home/antisatori/ghq/github.com/dowdiness/canopy/lang/lambda/flat/versioned_flat_proj.mbt`: existing revision-stamp `Eq` pattern.
- `/home/antisatori/ghq/github.com/dowdiness/canopy/projection/tree_refresh_benchmark_wbtest.mbt`: existing benchmark package pattern using `@bench`.
- `/home/antisatori/ghq/github.com/dowdiness/canopy/.github/workflows/ci.yml`: canonical CI fan-out.

MoonDsp:

- `/home/antisatori/ghq/github.com/dowdiness/moondsp/moon.mod`: `dowdiness/incr@0.6.0`.
- `/home/antisatori/ghq/github.com/dowdiness/moondsp/graph/graph_node.mbt`: `DspNodeKind`, `GraphParamSlot`, and `GraphControlKind` already derive `Eq`; `DspNode` does not.
- `/home/antisatori/ghq/github.com/dowdiness/moondsp/graph/compiled_template.mbt`: `CompiledTemplate` owns `template`, `optimized`, and `index_map`; it does not derive `Eq`.
- `/home/antisatori/ghq/github.com/dowdiness/moondsp/graph/compiled_template_wbtest.mbt`: current white-box tests for `CompiledTemplate` snapshot and topology queries.
- `/home/antisatori/ghq/github.com/dowdiness/moondsp/identity/identity.mbt`: `Revision::max` and `Revision::combine` already exist.
- `/home/antisatori/ghq/github.com/dowdiness/moondsp/docs/decisions/0010-compiled-template-runtime-boundary.md`: defers `CompiledTemplate`/`DspNode` `Eq` pending NaN policy.
- `/home/antisatori/ghq/github.com/dowdiness/moondsp/graph/graph_benchmark.mbt`: existing graph benchmark surface.
- `/home/antisatori/ghq/github.com/dowdiness/moondsp/scripts/check-public-boundary.sh`: boundary-check script and CI precedent.

## Phase and PR Graph

```text
PR A1  Canopy incr convergence (1a)
  -> PR B1/B2 cross-repo version lock standup can proceed in parallel after current pins are known (1b)
  -> PR C1/C2/C3 submodule flattening can proceed in parallel with 1a/1b but merges through nested gates (1c)

PR D1  MoonDsp NaN policy ADR (2a design gate)
  -> PR D2 MoonDsp Eq implementation (2a)
  -> PR D3 optional performance/memoization wiring only if a benchmark reproduces a real cost

PR E1  Canopy 2b microbench reproduction and decision record
  -> separate future optimization plan only if the bottleneck reproduces
```

2a and 2b share only the revision-stamp pattern from §7.1. They do not share a fix, a PR, or a milestone gate beyond BAND 1 being complete.

## Global Verification Breakpoints

Use these as stop points in every implementation PR.

Canopy:

```bash
NEW_MOON_MOD=0 moon check --deny-warn
NEW_MOON_MOD=0 moon test --release
NEW_MOON_MOD=0 moon fmt
NEW_MOON_MOD=0 moon info
git diff -- '*.mbti'
```

Canopy targeted benchmark commands, only where a benchmark file is added or changed:

```bash
NEW_MOON_MOD=0 moon bench --release
NEW_MOON_MOD=0 moon bench --release --package dowdiness/canopy/projection
```

Canopy submodule fan-out when the change touches submodules:

```bash
NEW_MOON_MOD=0 moon test
NEW_MOON_MOD=0 moon check
```

Run the last two from each affected MoonBit module root named in the PR, for example the Canopy root, `event-graph-walker`, `loom/loom`, `loom/examples/lambda`, and `loom/examples/json`.

MoonDsp:

```bash
moon check --deny-warn
moon test --release
moon fmt
moon info
git diff -- '*.mbti'
./scripts/check-public-boundary.sh
```

MoonDsp benchmarks, only for performance claims:

```bash
moon bench --release --package graph
moon bench --release
```

If any breakpoint fails, fix at that point before editing the next logical file. Do not batch multiple failing files and defer the compile.

## PR A1: Canopy `incr` Version Convergence (1a)

Goal: align Canopy root with `lib/cognition` and MoonDsp on `dowdiness/incr` 0.6.0, while migrating Canopy-owned call sites toward 0.6 target facades where the codemod can do so safely.

Primary files:

- `moon.mod.json`
- `lib/cognition/moon.mod`
- `core/projection_memo.mbt`
- `lang/lambda/flat/projection_memo.mbt`
- `lang/lambda/flat/versioned_flat_proj.mbt`
- `lang/json/proj/proj_node.mbt`
- `lang/markdown/proj/proj_node.mbt`
- `editor/sync_editor*.mbt`
- `workspace/coordinator/*.mbt`
- `workspace/probe/*.mbt`
- `lib/cognition/*.mbt`
- `lib/visualizer/incr_tap.mbt`
- `ffi/lambda/workspace_memo_*_wbtest.mbt`
- generated `pkg.generated.mbti` files only as produced by `NEW_MOON_MOD=0 moon info`

Steps:

1. Preflight dependency health from Canopy root.
   - Run `NEW_MOON_MOD=0 moon check --deny-warn`.
   - Run `NEW_MOON_MOD=0 moon ide outline /home/antisatori/ghq/github.com/dowdiness/canopy/core` and equivalent outlines for the first packages to be touched.
   - Record the reuse check in the PR: likely candidate APIs are `@incr.Derived`, `@incr.ReachableDerived`, `@incr.DerivedMap`, `@incr.Input`, and `@incr.Watch`.
   - If the preflight fails before the version bump, stop and either fix an unrelated baseline failure in a separate PR or rebase.

2. Update the Canopy root dependency pin.
   - Change `moon.mod.json` `dowdiness/incr` from `0.5.2` to `0.6.0`.
   - Do not change `lib/cognition/moon.mod` unless the lock mechanism in PR B1 changes how pins are represented.
   - Breakpoint: `NEW_MOON_MOD=0 moon check --deny-warn`.

3. Run the `incr` codemod in dry-run mode from its real path.
   - Command shape:
     ```bash
     python3 /home/antisatori/ghq/github.com/dowdiness/canopy/loom/incr/scripts/migrate-to-target-facades.py /home/antisatori/ghq/github.com/dowdiness/canopy/core /home/antisatori/ghq/github.com/dowdiness/canopy/editor /home/antisatori/ghq/github.com/dowdiness/canopy/lang /home/antisatori/ghq/github.com/dowdiness/canopy/lib /home/antisatori/ghq/github.com/dowdiness/canopy/workspace /home/antisatori/ghq/github.com/dowdiness/canopy/ffi
     ```
   - Review report-only findings before applying. The script reports context-sensitive reads that need a manual strict-vs-permissive choice.
   - Do not scan `loom/incr` itself as part of Canopy consumer migration.

4. Apply mechanical target-facade rewrites for Canopy-owned packages only.
   - Use `--apply` only after the dry-run list is understood.
   - Migrate compatibility handles to target facades where safe: `Memo` to `Derived`, `HybridMemo` to `ReachableDerived`, and `MemoMap` to `DerivedMap`.
   - Respect 0.6.0 semantics: target-facade constructors exist, `Derived` read signatures changed, and compatibility handles still exist with no removal date. Do not remove compatibility paths where the codemod reports a real design choice.
   - Breakpoint after each edited file: `NEW_MOON_MOD=0 moon check --deny-warn`.

5. Manually resolve report-only read sites.
   - For reads inside tracked computations, use the strict/tracked read surface appropriate to 0.6.
   - For long-lived reads outside a tracked context, use the `Watch`/observer pattern rather than smuggling permissive reads through a helper.
   - If a compatibility-only diagnostic or lifecycle method is used, either keep that handle intentionally or design a small local seam and document why target facades do not cover it.
   - Verification: existing tests that assert runtime-threading and cross-runtime safety must still pass.

6. Confirm no unintended module-file migration.
   - Run `git status --short`.
   - There must be no new `moon.mod` files created from existing `moon.mod.json` packages.
   - If any appear, stop and revert only those generated files after confirming they were tool output from this PR, then rerun all Canopy `moon` commands with `NEW_MOON_MOD=0`.

7. Final validation for PR A1.
   - `NEW_MOON_MOD=0 moon check --deny-warn`
   - `NEW_MOON_MOD=0 moon test --release`
   - `NEW_MOON_MOD=0 moon fmt`
   - `NEW_MOON_MOD=0 moon info`
   - `git diff -- '*.mbti'`
   - `NEW_MOON_MOD=0 moon build --target js` if web-facing projection/editor packages changed

Acceptance criteria:

- Canopy root, `lib/cognition`, and MoonDsp all resolve to `dowdiness/incr` 0.6.0.
- No Canopy `moon.mod.json` file is accidentally converted to `moon.mod`.
- All manually migrated read sites have explicit tracked/outside-read rationale.
- Generated interface diffs are reviewed and intentional.

Risks covered:

- §7.2 `incr` version skew: direct mitigation.
- §7.2 compatibility-handle deletion timeline: partial mitigation by moving Canopy-owned code toward target facades while keeping compatible handles where still needed.

## PR B1/B2: Cross-Repository `incr` Coordination Mechanism (1b)

Goal: add the smallest enforceable mechanism that keeps Canopy and MoonDsp on the same `incr` minor and records the compatibility-handle deletion timeline.

Recommended decomposition:

- PR B1 in Canopy: shared lock schema, local validation script, Canopy CI hook.
- PR B2 in MoonDsp: same lock schema, local validation script, MoonDsp CI hook.
- Optional PR B3 after both land: cross-check workflow that checks out both repositories and validates both pins from one CI job or scheduled workflow.

Primary Canopy files:

- new `shared-substrate.lock.json` or `docs/decisions/2026-06-xx-shared-substrate-version-lock.md`
- new `scripts/check-shared-substrate.py` or `scripts/check-shared-substrate.sh`
- `.github/workflows/ci.yml`
- `moon.mod.json`
- `lib/cognition/moon.mod`

Primary MoonDsp files:

- new `shared-substrate.lock.json`
- new `scripts/check-shared-substrate.py` or `scripts/check-shared-substrate.sh`
- new `.github/workflows/substrate-check.yml` or an added job in an existing workflow
- `moon.mod`
- `docs/decisions/0014-shared-substrate-version-lock.md`
- `docs/decisions/README.md`

Lock contents:

- Record `dowdiness/incr` exact target version, current required minor, consumer repos, compatibility-handle status, and a deletion-policy field.
- Include a human-readable owner and ADR link.
- Do not encode loom parser adoption or loom publication. That is BAND 4g.

Steps:

1. Decide the lock-file schema in a short ADR.
   - Canopy may use a date-named decision under `docs/decisions/`.
   - MoonDsp should use the next numbered ADR after 0013, likely `0014-shared-substrate-version-lock.md`.
   - The ADR must state that Single-Runtime compatibility requires same `incr` build as a downstream BAND 3+ precondition, but the current mechanism enforces only same minor/pin discipline.

2. Add local validation.
   - The script must parse Canopy `moon.mod.json` JSON and `lib/cognition/moon.mod`.
   - The script must parse MoonDsp `moon.mod`.
   - The script must fail when any local pin disagrees with the lock file's exact version or allowed minor.
   - If the script supports a peer repo path, it should compare both repos when both are checked out, but local validation must be useful by itself.

3. Add CI jobs.
   - Canopy: add a dependency-rules or substrate-check step to `.github/workflows/ci.yml` after checkout and before build/test jobs.
   - MoonDsp: add a `substrate-check` workflow or job, following the precedent of `.github/workflows/boundary-check.yml`.
   - If a cross-repo checkout is required, make the paired-branch mechanism explicit so future coordinated bumps do not deadlock two PRs against each other's old `main`.

4. Add future bump protocol to the ADR.
   - Open paired PRs when `incr` minor changes.
   - Run local validation in each repo and a peer-root validation once both branches exist.
   - Merge order must not break required CI. If required CI cannot see peer PR branches, keep the peer-root cross-check as a manually triggered gate until repository rules support paired required statuses.
   - Compatibility-handle removal requires a shared-substrate ADR update with a dated removal target.

5. Final validation.
   - Canopy:
     ```bash
     python3 scripts/check-shared-substrate.py --root /home/antisatori/ghq/github.com/dowdiness/canopy
     NEW_MOON_MOD=0 moon check --deny-warn
     NEW_MOON_MOD=0 moon test --release
     ```
   - MoonDsp:
     ```bash
     python3 scripts/check-shared-substrate.py --root /home/antisatori/ghq/github.com/dowdiness/moondsp
     moon check --deny-warn
     moon test --release
     ./scripts/check-public-boundary.sh
     ```
   - Peer mode, once both repos have the script:
     ```bash
     python3 scripts/check-shared-substrate.py --root /home/antisatori/ghq/github.com/dowdiness/canopy --peer-root /home/antisatori/ghq/github.com/dowdiness/moondsp
     ```

Acceptance criteria:

- Both repos have the same `incr` lock value and fail CI on local pin drift.
- The coordination ADR says how to do the next `incr` minor bump without guessing.
- Compatibility-handle removal is no longer an untracked surprise.

Risks covered:

- §7.2 `incr` version skew: direct mitigation.
- §7.2 compatibility-handle deletion timeline: direct mitigation.

Open design point:

- Whether cross-repo validation is required CI on every PR, scheduled CI, or a paired-branch manual gate. Avoid a future two-PR deadlock.

## PR C1/C2/C3: Submodule Nesting Flattening and Dependency Hygiene (1c)

Goal: remove the duplicate `event-graph-walker` vendoring layer under `loom` while keeping Canopy's root `event-graph-walker` path stable for current production use.

This is dependency hygiene only. Do not promote loom to MoonDsp production parsing, do not publish loom/seam, and do not touch the parser-adoption path.

Merge gates:

- Gate C0: if `event-graph-walker` itself needs a version/tag/publish update, that PR must merge and be pushed first.
- Gate C1: loom submodule PR removes its nested `event-graph-walker` dependency path and validates standalone loom.
- Gate C2: Canopy parent PR updates the `loom` submodule pointer after C1 is on remote.
- Gate C3: Canopy parent CI validates recursive checkout no longer includes `canopy/loom/event-graph-walker`.

Before this work, `event-graph-walker` appears at two layers:

- root layer: `canopy/event-graph-walker`
- nested layer: `canopy/loom/event-graph-walker`

Each layer is a merge gate. Flattening removes the nested layer but does not eliminate the root submodule gate for Canopy's production CRDT dependency.

Primary loom files:

- `loom/.gitmodules`
- `loom/examples/lambda/moon.mod.json`
- `loom/examples/lambda/src/moon.pkg`
- `loom/examples/lambda/src/crdt_egw_test.mbt`
- `loom/docs/development/managing-modules.md`
- any loom CI config if present

Primary Canopy parent files:

- `.gitmodules`, only if root submodule configuration changes
- `loom` submodule pointer
- `.github/workflows/ci.yml`, only if test fan-out must account for the flattened dependency
- `moon.mod.json`, only if root dependency wiring needs adjustment

Steps:

1. Establish the dependency target for loom's lambda example.
   - **Verified current state (2026-06-01):** `event-graph-walker` is a **path dependency at both layers** — Canopy root `moon.mod.json` uses `"path": "./event-graph-walker"` and `loom/examples/lambda/moon.mod.json` uses `"path": "../../event-graph-walker"`. The module *declares* `version 0.3.0` in its own `moon.mod.json`, but it is **NOT present in the `.mooncakes/` cache**, i.e. it is almost certainly **unpublished to the registry**. There is no registry `dowdiness/event-graph-walker@0.3.0` to depend on yet.
   - Therefore the registry target is **blocked on publishing egw first (Gate C0)** — this is not optional. Do not fake it with a parent-relative path in standalone loom. Either publish `event-graph-walker@0.3.0` to mooncakes through Gate C0, or keep C1 blocked. (This downgrades open question #3 from "confirm" to "publish egw, then C1.")
   - Verification: standalone loom clone can run `NEW_MOON_MOD=0 moon test` for `loom/examples/lambda` without a nested submodule.

2. Loom PR C1.
   - Remove `event-graph-walker` from `loom/.gitmodules`.
   - Remove the nested submodule entry and path dependency.
   - Update `loom/examples/lambda/moon.mod.json` to use the selected registry version or another standalone-safe dependency.
   - Keep `crdt_egw_test.mbt` unless the test is intentionally split behind an integration profile; if split, document why the test is not silently removed.
   - Breakpoint after each file edit: `NEW_MOON_MOD=0 moon check --deny-warn` from the affected loom module root.
   - Final loom validation:
     From `loom/loom`:
     ```bash
     NEW_MOON_MOD=0 moon test --release
     ```
     From `loom/examples/lambda`:
     ```bash
     NEW_MOON_MOD=0 moon test --release
     ```

3. Push and merge C1 before touching the Canopy parent pointer.
   - Submodule commit must exist on remote before Canopy references it.
   - Record the loom commit SHA in the Canopy PR body.

4. Canopy parent PR C2.
   - Update `loom` submodule pointer to the merged C1 commit.
   - Run `git submodule status --recursive` and confirm `loom/event-graph-walker` is absent.
   - Keep root `event-graph-walker` unchanged unless Gate C0 required a version bump.
   - Final Canopy validation:
     ```bash
     NEW_MOON_MOD=0 moon check --deny-warn
     NEW_MOON_MOD=0 moon test --release
     NEW_MOON_MOD=0 moon build --target js
     ```
   - Run the submodule fan-out matching `.github/workflows/ci.yml`: Canopy root, `event-graph-walker`, `loom/loom`, `loom/examples/lambda`, `loom/examples/json`, `loom/examples/markdown`, `svg-dsl`, and `graphviz` as applicable.

5. CI hygiene PR C3, only if C2 shows CI drift.
   - Update `.github/workflows/ci.yml` to stop assuming nested `loom/event-graph-walker`.
   - Do not add MoonDsp loom adoption checks here.

Acceptance criteria:

- Recursive checkout has only one `event-graph-walker` under Canopy.
- Loom examples still test their CRDT integration against a standalone-safe dependency.
- Canopy parent references only pushed/merged submodule commits.

Risks covered:

- §5.4 and §8.3 submodule nesting debt: direct mitigation.
- §7.2 loom wasm-gc AudioWorklet build risk is not solved here; this PR only removes nested dependency debt that would otherwise add gates to later loom work.

Open design point:

- **Verified:** egw is a path dep at both layers and is unpublished (not in `.mooncakes/`). C1's registry target is hard-blocked on publishing `event-graph-walker@0.3.0` (Gate C0). Confirm sufficiency of that published version for loom's lambda example, then proceed. Until egw is published, C1 cannot start.

## PR D1/D2/D3: MoonDsp `DspNode`/`CompiledTemplate` Eq (2a)

Goal: make `DspNode` and `CompiledTemplate` equality available for future early-cutoff/memoization work, but only after MoonDsp chooses a NaN policy.

The design call belongs to MoonDsp. Canopy must not decide it.

Primary MoonDsp files:

- `docs/decisions/0014-dsp-node-compiled-template-eq-nan-policy.md`
- `docs/decisions/README.md`
- `docs/next-actions.md`
- `graph/graph_node.mbt`
- `graph/compiled_template.mbt`
- `graph/compiled_template_wbtest.mbt`
- likely new `graph/graph_node_eq_wbtest.mbt`
- `graph/graph_benchmark.mbt`, only if making a performance claim or wiring early cutoff
- `graph/pkg.generated.mbti`

Steps for PR D1, NaN policy ADR:

1. Write the ADR before editing Eq code.
   - Evaluate the three policies from §2.4.1:
     - structural bit equality, including `NaN == NaN` only for identical bits;
     - IEEE equality, where `NaN != NaN`;
     - canonical normalization before equality.
   - State how the chosen policy interacts with `CompiledTemplate::analyze` being infallible and with existing compile-time rejection of invalid graph constants.
   - State whether `-0.0` and `+0.0` follow IEEE equality or bit equality, because a bit-policy for NaN can accidentally change zero semantics.
   - State that `Eq` is for structural authoring/template identity and early cutoff, not for DSP sample equivalence.

2. Review D1 as a MoonDsp design call.
   - Do not implement Eq until D1 is accepted.
   - If the design chooses IEEE `NaN != NaN`, record that early cutoff will be intentionally disabled for NaN-bearing templates and explain why that tradeoff is acceptable.

Steps for PR D2, Eq implementation:

1. Run Existing API First in MoonDsp.
   - Use `moon ide outline graph`, `moon ide find-references DspNode`, and `moon ide find-references CompiledTemplate`.
   - Candidate existing APIs include `DspNode` accessors, `CompiledTemplate::analyze`, `CompiledTemplate::node_at`, and `Revision` in `identity/identity.mbt`.

2. Implement `DspNode` equality according to the accepted ADR.
   - Add a narrowly named helper only if the selected Double policy cannot be expressed clearly inline.
   - The helper responsibility boundary is only "Double equality for graph structural Eq"; do not make it a general numerical utility.
   - Tests must assert ordinary equal nodes, field differences, kind/input differences, and the selected NaN/zero semantics.
   - Breakpoint after file edit: `moon check --deny-warn`.

3. Implement `CompiledTemplate` equality.
   - Compare the authoring template snapshot, optimized nodes, and index map according to the ADR.
   - Tests must assert snapshot equality, caller-mutation isolation still holds, optimized/index-map differences matter, and NaN behavior matches `DspNode`.
   - Breakpoint after file edit: `moon check --deny-warn`.

4. Update public surfaces.
   - Run `moon info`.
   - Review `graph/pkg.generated.mbti` and root `pkg.generated.mbti` for intended `Eq` impl exposure.
   - Do not widen public constructors or expose generic `CompiledTemplate` internals as part of Eq.

5. Final D2 validation.
   - `moon check --deny-warn`
   - `moon test --release`
   - `moon fmt`
   - `moon info`
   - `./scripts/check-public-boundary.sh`

Steps for PR D3, performance or early-cutoff wiring, only if included:

1. Start with a microbenchmark.
   - Add or extend a benchmark in `graph/graph_benchmark.mbt` that isolates the claimed repeated `CompiledTemplate::analyze` or downstream early-cutoff cost.
   - Run `moon bench --release --package graph`.
   - If the benchmark does not reproduce a meaningful cost, stop and do not wire memoization or claim a performance improvement.

2. Only after reproduction, prototype the smallest early-cutoff wiring.
   - The likely pattern is a revision-stamped wrapper similar in spirit to Canopy's `VersionedFlatProj`, not shared code.
   - Verify before/after benchmark results in the same process and target.
   - If the prototype does not improve the isolated benchmark, stop and revert the optimization wiring.

Acceptance criteria:

- D1 accepted before D2 starts.
- `DspNode` and `CompiledTemplate` have deterministic, documented Eq semantics.
- NaN and zero behavior is pinned by tests.
- No performance claim appears without an isolated benchmark.

Risks covered:

- §2.4/§2.4.1 deferred Eq gate: direct mitigation.
- §7.2 MoonDsp rational overflow is not covered; that is a separate BAND 2 risk and not part of 2a.

Blocking design call:

- Select NaN equality policy in MoonDsp before implementation.

## PR E1: Canopy 2b Microbenchmark and Decision Gate

Goal: reproduce or reject the §7.6 Canopy hot-path claims before designing an optimization.

This PR does not implement the optimization. It creates isolated evidence and a decision record.

Claims to test:

- `to_flat_proj_incremental` O(N) change-detection scan is about 5 ms of the about 8.5 ms 1000-def keystroke pipeline.
- `core/reconcile.mbt` LCS child matching is O(m*n) and can become quadratic on wide sibling lists.

Primary files:

- `lang/lambda/proj/flat_proj.mbt` as measured code, not optimized in E1.
- `core/reconcile.mbt` as measured code, not optimized in E1.
- `projection/tree_refresh_benchmark_wbtest.mbt` or a new focused benchmark file under `projection/`.
- possibly `projection/moon.pkg` if new benchmark imports are needed.
- possibly `core/moon.pkg` only if the benchmark must live in `core`.
- new `docs/performance/2026-06-xx-band2-canopy-hotpath-baseline.md`.
- new follow-up `docs/plans/...` only if reproduction justifies optimization.

Steps:

1. Check staleness and mitigations.
   - Read `docs/performance/2026-04-06-pipeline-decomposition.md`.
   - Inspect `lang/lambda/flat/projection_memo.mbt` and `lang/lambda/flat/versioned_flat_proj.mbt` for current revision-stamp/backdating behavior.
   - Inspect `lang/lambda/proj/flat_proj.mbt` and `core/reconcile.mbt` to confirm the measured code still exists.
   - Record whether any later batching, caching, or lazy-eval change appears to have neutralized the claim.

2. Add an isolated O(N) change-detection benchmark.
   - Measure `to_flat_proj_incremental` alone at 20, 80, 320, and 1000 defs.
   - Include at least: unchanged same-root or structurally unchanged case, one tail def changed, and a shifted-offset case where reuse is intentionally blocked.
   - Keep setup outside the measured loop unless the setup is part of the claimed cost.
   - Verification command:
     ```bash
     NEW_MOON_MOD=0 moon bench --release --package dowdiness/canopy/projection
     ```
   - If 1000-def cost is not in the same order as the §7.6 claim, stop and re-evaluate before proposing an optimization.

3. Add an isolated reconciliation benchmark.
   - Measure `@core.reconcile` child matching over wide sibling lists with known same-kind and different-kind distributions.
   - Include a case that forces LCS table growth, not only a best-case same-kind run.
   - Verify that the benchmark measures reconciliation itself, not parsing or source-map construction.
   - Verification command:
     ```bash
     NEW_MOON_MOD=0 moon bench --release --package dowdiness/canopy/projection
     ```
   - If the O(m*n) cliff does not reproduce at plausible document shapes, do not replace LCS in this plan.

4. Write the performance decision record.
   - Add `docs/performance/2026-06-xx-band2-canopy-hotpath-baseline.md`.
   - Include raw command, target/backend, hardware note if available, measured operations, and conclusion.
   - Classify each claim as reproduced, smaller-than-claimed, or not reproduced.

5. Decide.
   - If neither claim reproduces: close E1 with "stop and reprofile full pipeline"; no optimization plan.
   - If only the O(N) scan reproduces: write a follow-up plan focused on revision/source-change stamps for change detection.
   - If only LCS reproduces: write a follow-up plan focused on keyed child matching and invariants for `TreeNode::same_kind`.
   - If both reproduce: write a follow-up plan that separates the two fixes. Do not combine them because they share only the revision-stamp idea, not implementation.

6. Final E1 validation.
   - `NEW_MOON_MOD=0 moon check --deny-warn`
   - `NEW_MOON_MOD=0 moon test --release`
   - `NEW_MOON_MOD=0 moon bench --release --package dowdiness/canopy/projection`
   - `NEW_MOON_MOD=0 moon fmt`
   - `NEW_MOON_MOD=0 moon info`
   - `git diff -- '*.mbti'`

Acceptance criteria:

- The O(N) scan claim is reproduced or rejected with an isolated benchmark.
- The LCS claim is reproduced or rejected with an isolated benchmark.
- No optimization code is included in E1.
- A follow-up optimization plan exists only for reproduced cliffs.

Risks covered:

- §7.6 Canopy O(N) change-detection scaling cliff: evidence gate.
- §7.6 Canopy O(m*n) reconciliation cliff: evidence gate.

## Risk Backlinks

| Source | Risk or cliff | Task |
| --- | --- | --- |
| §7.2 | `incr` skew across Canopy root, `lib/cognition`, MoonDsp | A1, B1/B2 |
| §7.2 | compatibility-handle removal timeline missing | A1 partial, B1/B2 direct |
| §5.4, §8.3 | `event-graph-walker` double vendoring | C1/C2/C3 |
| §7.2 | loom wasm-gc AudioWorklet build unproven | Not solved here; 1c only removes a dependency hygiene blocker |
| §2.4, §2.4.1 | `DspNode`/`CompiledTemplate` Eq blocked by NaN policy | D1/D2 |
| §7.6 | Canopy O(N) change-detection cost | E1 |
| §7.6 | Canopy O(m*n) LCS reconciliation | E1 |
| §7.1 | 2a and 2b share revision-stamp pattern only | D3 and E1 must not share implementation |
| §5.2 | Single-Runtime cross-runtime abort constraint | B1/B2 records downstream BAND 3+ unlock only |

## Open Questions and Blocking Calls

1. MoonDsp must choose the NaN equality policy before `DspNode` or `CompiledTemplate` Eq lands. The policy must explicitly cover NaN payloads and `-0.0`/`+0.0`.
2. Decide whether cross-repo `incr` validation is required CI on every PR, scheduled CI, or a paired-branch manual gate. Required cross-checks against peer `main` can deadlock future coordinated bumps.
3. **Verified blocker (not just "confirm"):** `dowdiness/event-graph-walker` is consumed as a path dep at both layers and is unpublished (absent from `.mooncakes/`); it only *declares* version 0.3.0. C1 is hard-blocked behind publishing egw to the registry (Gate C0). Decide whether to publish egw 0.3.0 now or defer all of 1c until egw is registry-ready.
4. E1 must answer whether the current code still reproduces the §7.6 costs. If not, the correct next step is full-pipeline re-profiling, not optimization.
5. If D3 wants to wire early cutoff in MoonDsp, the performance claim must start with a graph microbenchmark. Eq alone is not a performance result.

## PR Review Checklist

- [ ] PR states which workstream it implements: 1a, 1b, 1c, 2a, or 2b.
- [ ] PR reuse check names existing APIs considered before adding helpers.
- [ ] Canopy `moon` commands are all prefixed with `NEW_MOON_MOD=0`.
- [ ] MoonBit compile breakpoint was run after each edited file.
- [ ] `moon fmt` and `moon info` were run at the final breakpoint.
- [ ] `.mbti` diffs are explained.
- [ ] Submodule commits are pushed to remote before parent pointer updates.
- [ ] 2a has an accepted NaN policy before Eq implementation.
- [ ] 2a/2b performance claims include isolated microbench results.
- [ ] 2b contains no optimization code until the benchmark gate reproduces the cliff.
