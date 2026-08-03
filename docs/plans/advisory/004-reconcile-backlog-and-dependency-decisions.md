# Plan 004: Reconcile the active backlog and substrate decisions with live state

> **Executor instructions**: This is a documentation-only consistency plan.
> Preserve historical evidence while removing claims that mutable versions or
> shipped status are current when they are not. Run every verification command
> and stop instead of editing code or CI. Update this plan's status in
> `README.md` when done unless a reviewer owns the index.
>
> **Drift check (run first)**:
> `git diff --stat f6e3a0a5..HEAD -- docs/TODO.md docs/README.md docs/decisions/2026-06-10-shared-substrate-incr-version-lock.md docs/decisions/2026-06-12-substrate-governance.md docs/decisions/2026-07-11-structure-mode-completion-state.md moon.mod moon.work scripts/check-shared-substrate.sh .github/workflows/ci.yml`
> If an in-scope document changed, compare the live status claims with the
> evidence below and stop on a semantic mismatch.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `003-refresh-repository-topology-docs.md`
- **Category**: docs / governance
- **Audit finding**: 6
- **Planned at**: commit `f6e3a0a5`, 2026-07-25

## Why this matters

The active backlog says a removed TypeScript CI matrix is shipped and that
structure-mode completion remains undecided, despite an accepted ADR proving it
complete. Separately, accepted substrate ADRs present old `incr` versions as the
current single source of truth even though all current workspace consumers use
0.14.2. The durable decision is version alignment and bump discipline—not a
number copied into prose. This plan makes active status honest and makes
manifests plus the existing drift guard authoritative for mutable pins.

## Current state

### Active backlog drift

- `docs/TODO.md:92-93` is checked and says `typecheck-ts-examples` exists in
  `.github/workflows/ci.yml`. Current CI has explicit web/prosemirror checks but
  no job with that ID and no `demo-react` TypeScript gate. Commit `17441b27`
  removed the matrix during a broad CI rewrite.
- `docs/TODO.md:287-288` says structure mode is incomplete and its decision is
  pending.
- Accepted ADR `docs/decisions/2026-07-11-structure-mode-completion-state.md`
  says structure mode is complete, actively maintained, lazy-loaded, and covered
  by two Playwright suites. It explicitly directs the TODO to be checked off or
  narrowed.

### Substrate decision drift

- `moon.mod` currently pins `dowdiness/incr@0.14.2`.
- `./scripts/check-shared-substrate.sh` currently reports nine workspace members
  agreeing on minor `0.14`, each at `0.14.2`.
- `docs/decisions/2026-06-10-shared-substrate-incr-version-lock.md` records the
  initial 0.9.0 baseline but calls it the current exact target and says the ADR
  is the single source of truth for that mutable value.
- `docs/decisions/2026-06-12-substrate-governance.md:82` copies `registry 0.13.0`.
  Its own `Source of truth on drift` section says manifests and gitlinks are
  authoritative and the table must be updated when they disagree.
- `docs/README.md:156` summarizes the old 0.9 lock as if current.

### Required semantic distinction

Preserve historical facts with dates:

- 0.9.0 was the verified initial lock baseline on 2026-06-10.
- 0.13.0 was a point-in-time later snapshot if the ADR says so.

Make current mutable state derive from:

- workspace manifests for exact pins;
- `scripts/check-shared-substrate.sh` for same-major/minor agreement;
- the ADR for the policy, consumer coordination, bump order, and compat-handle
  removal process.

Do not simply replace every old number with 0.14.2; that would drift again at
the next bump.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Live pin guard | `./scripts/check-shared-substrate.sh` | exits 0 and reports one agreed minor |
| Manifest pin | `rg -n 'dowdiness/incr@' moon.mod` | prints current root pin |
| CI status | `rg -n 'typecheck-ts-examples|demo-react|Type check' .github/workflows/ci.yml` | confirms no matrix job; demo-react appears only in E2E at plan time |
| Structure evidence | `rg -n 'Status:|complete, actively maintained|Lazy-loading|Tested' docs/decisions/2026-07-11-structure-mode-completion-state.md` | accepted evidence found |
| Link guard | `bash ./scripts/check-agent-doc-links.sh` | exits 0 |
| Diff hygiene | `git diff --check` | exits 0 |

## Suggested executor toolkit

Use a documentation-writing or Slopless skill if available. Do not invoke an
implementation worker: this plan changes only status and decision prose.

## Scope

**In scope**:

- `docs/TODO.md`
- `docs/README.md`
- `docs/decisions/2026-06-10-shared-substrate-incr-version-lock.md`
- `docs/decisions/2026-06-12-substrate-governance.md`
- `README.md` status row only

**Read-only evidence**:

- `docs/decisions/2026-07-11-structure-mode-completion-state.md`
- `moon.mod`
- member manifests reported by `scripts/check-shared-substrate.sh`
- `moon.work`
- `scripts/check-shared-substrate.sh`
- `.github/workflows/ci.yml`
- `examples/ideal/web/e2e/structure-mode-switch.spec.ts`
- `examples/ideal/web/e2e/structural-editing.spec.ts`

**Out of scope**:

- Do not restore the missing TypeScript CI job; audit finding 4 was not selected
  for implementation planning. Represent it honestly as open work only.
- Do not change any manifest, dependency version, lockfile, CI workflow, script,
  structure-mode source, test, accepted status, or historical/archive plan.
- Do not verify or change `dowdiness/moondsp` remotely. If current cross-repo
  claims require fresh verification, retain them as dated historical claims or
  stop.
- Do not mass-replace `0.9.0` in historical evidence.
- Preserve unrelated current edits in `docs/TODO.md`.

## Git workflow

- Branch: `advisor/004-reconcile-active-decisions`
- Suggested commit: `docs: reconcile backlog and substrate decisions`
- Do not push or open a PR without explicit operator instruction.

## Steps

### Step 1: Reconfirm live evidence before editing

Run:

```bash
./scripts/check-shared-substrate.sh
rg -n 'dowdiness/incr@' moon.mod
rg -n 'typecheck-ts-examples|demo-react-e2e|Type check web|Type check prosemirror' \
  .github/workflows/ci.yml
rg -n 'complete, actively maintained|Lazy-loading, verified|Tested, verified' \
  docs/decisions/2026-07-11-structure-mode-completion-state.md
```

Expected at plan time:

- nine members agree on minor 0.14 and exact 0.14.2;
- no `typecheck-ts-examples` job exists;
- structure ADR evidence is present.

The exact future pin/count may legitimately change; the invariant is one agreed
minor. Stop only if consumers disagree, the CI matrix has been restored, or the
structure ADR was superseded.

### Step 2: Make the TypeScript CI backlog status honest

In `docs/TODO.md`, change the checked TypeScript item to an open restoration
item. Keep its original shipment history, but explicitly say the matrix was
removed by the later CI rewrite and is not currently gated. Include machine-
checkable exit criteria:

- `demo-react` runs `npx tsc --noEmit` in CI after MoonBit JS artifacts exist;
- the job is included in the `all-checks-passed` dependency/aggregate;
- the TODO can be checked only after the live workflow contains the gate.

Do not edit `.github/workflows/ci.yml` or write an implementation plan for this
skipped finding.

**Verify**:

```bash
rg -n '^-[[:space:]]\[ \].*tsc --noEmit|removed.*CI|all-checks-passed' docs/TODO.md
! rg -n '^-[[:space:]]\[x\].*tsc --noEmit' docs/TODO.md
```

Expected: the item is open and the old false-shipped status is gone.

### Step 3: Close the stale structure-mode TODO

Replace the broad open item and its pending-decision note with a checked item
that cites `docs/decisions/2026-07-11-structure-mode-completion-state.md` and
summarizes the verified outcomes:

- first-class maintained mode;
- ProseMirror lazy loading confirmed;
- switch and structural-edit Playwright coverage exists.

Do not invent a new generic “polish” item. If a concrete defect remains, it must
have its own reproducible backlog entry rather than reopening completion state.

**Verify**:

```bash
rg -n '^-[[:space:]]\[x\].*Structure mode|2026-07-11-structure-mode-completion-state' docs/TODO.md
! rg -n 'completion state is unclear|structure-mode.*decision pending' docs/TODO.md
```

Expected: the completion item is checked and no pending-decision claim remains.

### Step 4: Separate historical baseline from live pin authority in the incr ADR

Edit `docs/decisions/2026-06-10-shared-substrate-incr-version-lock.md` carefully:

1. Keep the date, Accepted status, initial 0.9.0 facts, and dated verified
   topology as historical evidence.
2. Rename the lock snapshot heading/table fields so they clearly say
   `initial`/`historical` rather than `current`.
3. Add a short `Live pin authority` subsection near the snapshot:
   - exact current versions live in member manifests;
   - same-major/minor agreement is enforced by
     `scripts/check-shared-substrate.sh` over `moon.work`;
   - run that script to inspect current consumers and pins;
   - this ADR remains authoritative for policy, bump order, paired-repo
     coordination, and compat-handle removal—not the mutable exact number.
4. Rewrite Decision item 1 to require aligned major/minor consumers without
   naming 0.9 as current. Preserve that 0.9 was the acceptance baseline.
5. Preserve the bottom-up bump protocol and dated cross-repo claims. Do not
   claim current moondsp state without verification.

**Verify**:

```bash
rg -n 'initial|historical|Live pin authority|check-shared-substrate\.sh|manifests' \
  docs/decisions/2026-06-10-shared-substrate-incr-version-lock.md
! rg -n '0\.9\.0 as the current exact target|single source of truth.*value' \
  docs/decisions/2026-06-10-shared-substrate-incr-version-lock.md
```

Expected: historical 0.9 remains, but no sentence presents it as the live pin.

### Step 5: Remove mutable version duplication from governance docs

In `docs/decisions/2026-06-12-substrate-governance.md`:

- change the `dowdiness/incr` mechanism from `registry 0.13.0` to
  `registry (version in manifests)` or equivalent;
- retain the version-lock ADR and drift-guard references;
- keep the table's ownership mechanism and all historical resolver evidence;
- do not update unrelated dependency versions.

In `docs/README.md`, change the incr ADR summary from “locks ... at minor 0.9”
to a stable statement: it requires aligned Canopy/Loom/moondsp consumption,
defines bottom-up paired bumps, and names the drift guard. Do not copy 0.14.2.

**Verify**:

```bash
! rg -n 'registry 0\.13\.0|locks canopy/loom/moondsp at incr minor 0\.9' \
  docs/decisions/2026-06-12-substrate-governance.md docs/README.md
rg -n 'version in manifests|check-shared-substrate|paired' \
  docs/decisions/2026-06-12-substrate-governance.md docs/README.md
```

Expected: mutable versions are absent from current summaries while policy links
remain.

### Step 6: Run consistency and documentation gates

```bash
./scripts/check-shared-substrate.sh
bash ./scripts/check-agent-doc-links.sh

git diff --check
git diff --name-only
git status --short
```

Expected:

- the guard exits 0 with one agreed minor;
- links are valid;
- only the four in-scope docs plus plan status changed for this task.

Run final active-doc searches:

```bash
! rg -n 'completion state is unclear|0\.9\.0 as the current exact target|registry 0\.13\.0' \
  docs/TODO.md docs/README.md docs/decisions
! rg -n '^-[[:space:]]\[x\].*tsc --noEmit' docs/TODO.md
```

Expected: no stale active claims.

## Test plan

Documentation consistency is tested through live authorities:

- execute `scripts/check-shared-substrate.sh` rather than copying expected pins;
- compare active TODO status to live CI and the accepted structure ADR;
- use negative searches for the exact false-current phrases;
- run link and whitespace checks.

No source test or snapshot update is needed because source, CI, and manifests
remain untouched.

## Done criteria

- [ ] Missing `demo-react` TypeScript CI coverage is represented as open work,
  not shipped.
- [ ] Structure mode completion is checked and cites the accepted ADR.
- [ ] The incr ADR preserves 0.9.0 as dated historical evidence only.
- [ ] Current pin authority is manifests plus the shared-substrate guard.
- [ ] Governance and docs-index summaries do not duplicate mutable incr versions.
- [ ] `./scripts/check-shared-substrate.sh` and link checks exit 0.
- [ ] No source, CI, manifest, script, test, or out-of-scope doc changed.

## STOP conditions

Stop and report if:

- workspace members disagree on the `incr` major/minor;
- CI already restored a `demo-react` TypeScript gate and aggregate dependency;
- the structure-mode ADR was superseded or its cited tests no longer exist;
- preserving cross-repo policy requires unverifiable current moondsp claims;
- another task's edits to `docs/TODO.md` cannot be separated safely;
- a correction appears to require changing code, CI, manifests, or dependency
  versions.

## Maintenance notes

ADRs may retain dated version evidence, but mutable “current version” claims
belong in manifests and executable guards. Future dependency bumps should not
edit historical baseline numbers; they should update manifests, satisfy the
guard, and amend only policy or topology facts that genuinely changed. Backlog
checkboxes must be checked against live CI and accepted decisions, not prior PR
claims.