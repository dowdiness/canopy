# Plan 003: Make repository topology documentation derive from live manifests

> **Executor instructions**: This is a documentation-only plan. Follow each
> step, verify every path and command against the repository, and do not change
> manifests or source code to make stale prose true. Stop on drift rather than
> guessing. Record the result in
> [issue #1125](https://github.com/dowdiness/canopy/issues/1125).
>
> **Drift check (run first)**:
> `git diff --stat f6e3a0a5..HEAD -- README.md docs/development/monorepo.md docs/development/module-package-map.md docs/development/workflow.md docs/architecture/modules.md moon.work moon.mod .gitmodules scripts/package-overview.sh scripts/check-strict.sh .github/actions/setup-moonbit/action.yml .github/workflows/ci.yml`
> Re-read live manifests and CI even when the diff is empty; copied topology is
> exactly what this plan is eliminating.

> **Resolution (2026-08-03)**: Integrated into repository-layout Phase 2.
> Phase 1 commit `eec6decc` and Phase 2 commits `75e12e24` / `a4d2fc64`
> replaced copied topology with live authorities, added lifecycle enforcement,
> and corrected the remaining active guidance. The original documentation-only
> file boundary was superseded by the approved Phase 2 integration; the source,
> CI, script, ADR, and historical-document changes are separated by purpose in
> the reviewed branch history.
>
> Verification on clean detached HEAD `a4d2fc64` against
> `origin/main` `0263aa79`: `validate-pr-ready.sh` passed for `core`, `editor`,
> `lang/lambda/edits`, `lang/markdown/edits`, and `sync_session`; targeted tests
> passed 151/151, 231/231, 257/257, 59/59, and 29/29; the workspace baseline
> reported zero failures.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs / dx
- **Audit finding**: 5
- **Planned at**: commit `f6e3a0a5`, 2026-07-25

## Why this matters

Active contributor documentation still describes the root as
`moon.mod.json`, lists an obsolete 11-member workspace, tells contributors to
run workspace submodules separately, names removed paths such as
`framework/core`, and copies old dependency versions. The live `moon.work` has
42 members and the root manifest is `moon.mod`. The fix is not another copied
42-item list: high-level docs should link to live manifests and generated
inventory, while the development map records only stable ownership rules and
representative examples.

## Current state

Authoritative sources:

- `moon.work` contains 42 workspace members, including the root, Rabbita,
  submodules, Loom modules/examples, in-tree libraries, and examples.
- `moon.mod` is the root `dowdiness/canopy` manifest and imports
  `dowdiness/incr@0.14.2` at plan time.
- `.gitmodules` currently declares seven submodules:
  `event-graph-walker`, `loom`, `svg-dsl`, `graphviz`, `order-tree`, `alga`, and
  `rabbita`.
- `scripts/package-overview.sh` reads the current workspace and prints the live
  package map used at session start.
- `.github/workflows/ci.yml` is the source of truth for CI fan-out and exception
  handling.

Confirmed stale prose:

- `README.md:61-63` says submodules and example modules need separate suites,
  despite workspace-root coverage.
- `README.md:137-141` copies a small obsolete workspace-member subset.
- `docs/development/monorepo.md:3-5` calls the root manifest
  `moon.mod.json`; lines 31-50 copy an obsolete workspace list and say all
  submodules are separate.
- `docs/development/monorepo.md:55-79` copies obsolete path dependencies and
  `incr` 0.5.2.
- `docs/development/module-package-map.md:13-26,128-136` describes the root as a
  legacy-manifest exception even though `moon.mod` exists.
- `docs/development/module-package-map.md:38` recommends `moon work list`, but
  the installed CLI has no `work list` subcommand; its fallback happens to mask
  the invalid command.
- `docs/architecture/modules.md:47-170` describes a `crdt` module,
  `framework/core`, old nested Loom topology, separate test invocation, and
  `incr@0.11.0`.
- `docs/development/workflow.md` still calls the application the `crdt module`,
  describes two web pages, and lists separate submodule test commands.

### Documentation constraints

- Per `AGENTS.md`, architecture docs contain stable principles, not volatile
  type/field/line inventories.
- `moon.work`, `moon.mod`, `.gitmodules`, and CI are authoritative. Do not copy
  complete member/dependency/matrix lists into prose.
- `docs/development/module-package-map.md` may contain representative current
  package groups because it is a development reference, but it must direct
  readers to manifests/generated output for exhaustive lists.
- Do not edit historical/archive plans merely because their snapshots contain
  old versions.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Live package map | `./scripts/package-overview.sh` | exits 0 and prints workspace/package sections |
| Workspace source | `sed -n '/members = \[/,/\]/p' moon.work` | prints current member array |
| Submodule source | `git config --file .gitmodules --get-regexp '^submodule\..*\.path$'` | prints seven current paths |
| Root check | `NEW_MOON_MOD=0 moon check` | exits 0 |
| Strict check | `NEW_MOON_MOD=0 ./scripts/check-strict.sh` | exits 0; vendored diagnostics may be printed and suppressed |
| Link guard | `bash ./scripts/check-agent-doc-links.sh` | exits 0 |
| Diff hygiene | `git diff --check` | exits 0 |

## Suggested executor toolkit

- Use a documentation-writing or Slopless skill if available, but retain the
  project's concise technical tone.
- Use `moonbit-agent-guide` only to verify command semantics; do not change
  MoonBit source.

## Scope

**In scope**:

- `README.md`
- `docs/development/monorepo.md`
- `docs/development/module-package-map.md`
- `docs/development/workflow.md`
- `docs/architecture/modules.md`
- `README.md` status row only

**Read-only sources of truth**:

- `moon.work`
- `moon.mod`
- `.gitmodules`
- `.github/workflows/ci.yml`
- `.github/actions/setup-moonbit/action.yml`
- `scripts/package-overview.sh`
- `scripts/check-strict.sh`
- `AGENTS.md`
- `examples/README.md`

**Out of scope**:

- Do not change any manifest, workspace member, submodule pointer, CI job,
  script, source file, archived document, or accepted ADR.
- Do not enumerate all 42 workspace members or every dependency in prose.
- Do not update versioned historical evidence under `docs/archive`,
  `docs/plans`, `docs/research`, or `docs/superpowers`.
- Do not rewrite product vision or architecture decisions.
- Do not copy the exact MoonBit compiler/core version out of
  `.github/actions/setup-moonbit/action.yml`; link to that single source.
- Work in an isolated branch or worktree.

## Git workflow

- Branch: `advisor/003-refresh-topology-docs`
- Suggested commit: `docs: refresh repository topology guidance`
- Do not push or open a PR without explicit operator instruction.

## Steps

### Step 1: Capture live topology before editing prose

Run:

```bash
./scripts/package-overview.sh > /tmp/canopy-package-overview.txt
sed -n '/members = \[/,/\]/p' moon.work > /tmp/canopy-workspace-members.txt
git config --file .gitmodules --get-regexp '^submodule\..*\.path$' \
  > /tmp/canopy-submodules.txt
rg -n '^name\s*=|^version\s*=|^import\s*\{' moon.mod
rg -n 'Test Submodules|Test MoonBit Examples|all-checks-passed' .github/workflows/ci.yml
```

Expected: all commands exit 0; the generated files show the current 42-member
workspace and seven top-level submodules. These files are temporary evidence,
not repository artifacts.

### Step 2: Correct the root README without adding another inventory

In `README.md`:

1. Change Quick Start to say workspace-root `moon check`/`moon test` covers all
   current `moon.work` members, including the in-repo submodule modules now in
   the workspace. Point to CI for exact fan-out and vendored exceptions.
2. Replace the copied workspace-member sentence with a link to `moon.work` and
   `scripts/package-overview.sh`. Keep the representative library table only if
   every named role remains true.
3. Keep the Git submodule table if useful, but say `.gitmodules` is exhaustive
   and avoid claiming removed `rle` is still a submodule. At plan time the live
   list has seven entries and excludes `rle`.
4. Do not alter product copy or example descriptions outside topology claims.

**Verify**:

```bash
rg -n 'moon\.work|package-overview\.sh|\.gitmodules|workspace-root' README.md
! rg -n '^\| \[rle/' README.md
```

Expected: live sources are linked and no `rle` submodule row remains.

### Step 3: Rewrite the monorepo guide around workflows and authorities

Refactor `docs/development/monorepo.md` so it retains useful setup, submodule
commit/push ordering, pulling, pitfalls, and debt-routing guidance, while:

- naming the root `moon.mod` correctly;
- defining the difference between MoonBit workspace membership and Git
  submodule ownership;
- stating root commands cover all members in `moon.work`;
- linking CI for exact test fan-out and vendored leniency;
- replacing copied workspace/dependency/version tables with links to
  `moon.work`, `moon.mod`, `.gitmodules`, and `scripts/package-overview.sh`;
- removing separate-test instructions that duplicate workspace-root execution;
- retaining the proof-package exception (`moon prove` from its package root).

Do not claim every submodule edit can be pushed directly to `main`; preserve the
repository rule that submodule changes use PRs and are pushed before parent
pointer updates.

**Verify**:

```bash
rg -n 'moon\.mod|moon\.work|\.gitmodules|package-overview\.sh|ci\.yml|moon prove' \
  docs/development/monorepo.md
! rg -n 'moon\.mod\.json.*root|0\.5\.2|Everything else.*separate|cd loom/incr' \
  docs/development/monorepo.md
```

Expected: all authorities appear and obsolete claims do not.

### Step 4: Correct the development module/package map

In `docs/development/module-package-map.md`:

1. Remove the root from the legacy-manifest exception list; it uses `moon.mod`.
2. Recompute the Canopy-owned manifest migration summary from live files, but
   keep it category-level. Do not copy every workspace member.
3. Replace the unsupported `moon work list` suggestion with
   `./scripts/package-overview.sh` and the existing `sed` command for direct
   `moon.work` inspection.
4. Update representative package groups only where live paths/manifests prove
   them.
5. Clarify that workspace membership controls root command coverage while Git
   submodule ownership still controls where commits are made.

**Verify**:

```bash
rg -n 'scripts/package-overview\.sh|moon\.work|root.*moon\.mod' \
  docs/development/module-package-map.md
! rg -n 'moon work list|root module \(`moon\.mod\.json`\)|root module currently resolves.*legacy' \
  docs/development/module-package-map.md
```

Expected: generated/live discovery is documented and root legacy claims vanish.

### Step 5: Deepen the architecture module instead of copying implementation

Rewrite `docs/architecture/modules.md` as a stable architecture page. It should
explain principles and responsibility boundaries, then link to
`docs/development/module-package-map.md` for current package inventory.

Keep these durable concepts:

- root Canopy application versus reusable substrate modules;
- text CRDT, parsing/CST, projection/editor, protocol/transport, and UI adapter
  responsibility boundaries;
- package ownership follows manifests, while repository ownership follows
  submodule boundaries;
- dependencies point toward reusable substrate and must not grow upward into
  application code;
- manifests and the responsibility map are source of truth.

Remove implementation snapshots:

- `crdt/` as the root module name;
- `framework/core/` paths;
- copied type lists and dependency trees;
- exact dependency versions;
- manual test fan-out.

Link to `docs/architecture/responsibility-map.md`,
`docs/development/module-package-map.md`, `moon.mod`, and `moon.work`.

**Verify**:

```bash
rg -n 'responsibility-map|module-package-map|moon\.mod|moon\.work' docs/architecture/modules.md
! rg -n 'framework/core|## `crdt/`|incr@0\.|cd loom/' docs/architecture/modules.md
```

Expected: the architecture page is principle-oriented and has no stale paths or
versions.

### Step 6: Align the general development workflow

In `docs/development/workflow.md`, correct topology-related drift and add the
missing strict/toolchain guidance:

- require `./scripts/check-strict.sh`, not only bare `moon check`, before
  handing off MoonBit changes;
- link `.github/actions/setup-moonbit/action.yml` as the single source for the
  exact CI compiler/core pair instead of copying its version;
- explain that Canopy-owned diagnostics from newer compilers should be migrated,
  while vendored diagnostics remain governed by
  `scripts/vendored-check-common.sh`;
- retain `NEW_MOON_MOD=0` as the current CI compatibility setting;
- call the root application `dowdiness/canopy`, not `crdt module`;
- state workspace-root commands cover `moon.work`;
- point to CI for exact fan-out instead of listing separate submodule commands;
- describe the current multi-surface web workspace by linking
  `examples/web/README.md`, not by claiming only Lambda and JSON exist;
- use `npm ci` for reproducible install guidance where applicable.

**Verify**:

```bash
rg -n 'dowdiness/canopy|moon\.work|ci\.yml|examples/web/README\.md|check-strict\.sh|setup-moonbit/action\.yml|NEW_MOON_MOD=0' \
  docs/development/workflow.md
! rg -n 'ade96c819|crdt module|Two editor pages are available|cd event-graph-walker && moon test' \
  docs/development/workflow.md
```

Expected: current authorities and strict verification are documented without
copying the exact pin.

### Step 7: Run documentation and command validation

```bash
./scripts/package-overview.sh
bash ./scripts/check-agent-doc-links.sh
NEW_MOON_MOD=0 moon check
NEW_MOON_MOD=0 ./scripts/check-strict.sh

git diff --check
git diff --name-only
git status --short
```

Expected: all checks exit 0; only the five in-scope docs and plan status are
changed by this task. `moon check` may print vendored warnings but must exit 0.

Finally, search active docs for the exact stale patterns this plan targeted:

```bash
! rg -n 'framework/core|## `crdt/`|incr@0\.11\.0|dowdiness/incr.*0\.5\.2|moon work list' \
  README.md docs/architecture/modules.md docs/development/monorepo.md \
  docs/development/module-package-map.md docs/development/workflow.md
```

Expected: no matches.

## Test plan

This plan changes documentation only. Verification is source-backed rather than
snapshot-based:

- compare every topology statement to `moon.work`, `moon.mod`, `.gitmodules`,
  generated package overview, and CI;
- execute every command newly recommended in the docs;
- run the agent-doc link guard and `git diff --check`;
- use negative `rg` assertions for known stale paths, versions, and commands.

Do not run formatters that rewrite MoonBit source.

## Done criteria

- [x] Root and development docs identify `moon.mod` and `moon.work` correctly.
- [x] No active guide copies an exhaustive workspace/dependency list that can
  drift independently.
- [x] Root commands are documented as covering current workspace members.
- [x] Architecture modules page contains principles, not volatile type/path
  inventory.
- [x] The unsupported `moon work list` command is gone.
- [x] Removed `rle` and `framework/core` topology is not presented as current.
- [x] `./scripts/package-overview.sh`, link guard, `moon check`, and the strict
  wrapper exit 0.
- [x] Workflow docs link to the CI toolchain pin and do not duplicate it.
- [x] ~~No manifest, source, CI, script, ADR, or historical doc changed.~~
  Superseded by the approved integrated Phase 2 scope; the broader changes and
  their verification are recorded in the resolution above.

## STOP conditions

Stop and report if:

- `moon.work`, `moon.mod`, or `.gitmodules` changes during execution;
- live topology contradicts the Current state facts materially;
- a documentation correction would require a workspace/manifest/source change;
- strict checking fails for a Canopy-owned reason that requires source changes;
- generated package overview or root `moon check` is broken for reasons unrelated
  to documentation;
- the existing dirty worktree cannot be cleanly isolated.

## Maintenance notes

Reviewers should reject new copied workspace/dependency matrices unless they are
generated. When topology changes, update manifests and generated tooling first;
prose should describe durable rules and point to those authorities. Historical
plans and ADR evidence remain historical and should not be mass-edited by this
plan.

### Temporary migration inventory lifecycle

The manifest-discovery implementation in `scripts/package-overview.sh` and its
`scripts/test-package-overview.sh` contract test are migration instruments, not
permanent repository tooling. Their current single-file implementation is
intentional: do not split or generalize code that will be deleted.

Keep them only until all repository-layout migration phases satisfy these exit
conditions:

1. Every planned module, application, example, and submodule move is complete.
2. The final package/import mapping and root workspace membership pass their
   build, test, and CI gates without relying on migration-era before/after
   counts.
3. SessionStart and contributor navigation no longer depend on the generated
   migration inventory, or have a replacement based on the final layout.

At that point, delete `scripts/test-package-overview.sh` and the temporary
manifest-discovery implementation. Remove or replace links to
`scripts/package-overview.sh` in `README.mbt.md`,
`docs/development/module-package-map.md`, and
`docs/architecture/modules.md` in the same cleanup change so no dead navigation
remains. Retain the durable ownership principles in the documentation.