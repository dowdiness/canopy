# Plan 004: Reconcile substrate decisions with live state

> **Executor instructions**: This is a documentation-only consistency plan.
> Preserve historical evidence while removing claims that mutable versions or
> shipped status are current when they are not. Run every verification command
> and stop instead of editing code or CI. Record the result in
> [issue #1125](https://github.com/dowdiness/canopy/issues/1125).
>
> **Drift check (run first)**:
> `git diff --stat f6e3a0a5..HEAD -- docs/decisions/2026-06-10-shared-substrate-incr-version-lock.md docs/decisions/2026-06-12-substrate-governance.md moon.mod moon.work scripts/check-shared-substrate.sh .github/workflows/ci.yml`
> If an in-scope document changed, compare the live status claims with the
> evidence below and stop on a semantic mismatch.

> **Resolution (2026-08-03)**: Integrated into repository-layout Phase 2.
> The accepted ADRs now distinguish dated `incr` evidence from live manifest
> authority, `scripts/check-shared-substrate.sh` remains the executable
> consistency guard, and issue
> [#1124](https://github.com/dowdiness/canopy/issues/1124) owns legacy backlog
> validation.
>
> Verification on clean detached HEAD `a4d2fc64` against
> `origin/main` `0263aa79`: the shared-substrate gate found ten consumers aligned
> on minor `0.14`; the documentation lifecycle and agent-link guards passed;
> the full workspace baseline reported zero failures.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `003-refresh-repository-topology-docs.md`
- **Category**: docs / governance
- **Audit finding**: 6
- **Planned at**: commit `f6e3a0a5`, 2026-07-25

## Why this matters

The repository-layout migration moved active backlog ownership to GitHub Issues
and preserved the old Markdown backlog as a historical snapshot. Issue
[#1124](https://github.com/dowdiness/canopy/issues/1124) owns validation of its
legacy candidates, so this plan must not edit or reactivate them.

The remaining problem is accepted substrate ADRs presenting old `incr` versions
as the current single source of truth even though current workspace consumers
use 0.14.2. The durable decision is version alignment and bump discipline—not a
number copied into prose. This plan makes manifests plus the existing drift
guard authoritative for mutable pins.

## Current state

### Legacy backlog finding resolved by tracking migration

- `docs/archive/TODO-snapshot-2026-08-03.md` preserves the former Markdown
  backlog without active status.
- GitHub Issues owns current backlog membership and status.
- Issue [#1124](https://github.com/dowdiness/canopy/issues/1124) must classify
  the stale TypeScript-CI and structure-mode candidates against live evidence;
  this plan does not mutate the snapshot.

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
| Link guard | `bash ./scripts/check-agent-doc-links.sh` | exits 0 |
| Diff hygiene | `git diff --check` | exits 0 |

## Suggested executor toolkit

Use a documentation-writing or Slopless skill if available. Do not invoke an
implementation worker: this plan changes only accepted-decision prose.

## Scope

**In scope**:

- `docs/decisions/2026-06-10-shared-substrate-incr-version-lock.md`
- `docs/decisions/2026-06-12-substrate-governance.md`
- `docs/README.md`

**Read-only evidence**:

- `moon.mod`
- member manifests reported by `scripts/check-shared-substrate.sh`
- `moon.work`
- `scripts/check-shared-substrate.sh`

**Out of scope**:

- Do not edit or reactivate
  `docs/archive/TODO-snapshot-2026-08-03.md`; issue #1124 owns its triage.
- Do not change any manifest, dependency version, lockfile, CI workflow, script,
  source, test, accepted status, or historical/archive plan.
- Do not verify or change `dowdiness/moondsp` remotely. If current cross-repo
  claims require fresh verification, retain them as dated historical claims or
  stop.
- Do not mass-replace `0.9.0` in historical evidence.

## Git workflow

- Branch: `advisor/004-reconcile-substrate-decisions`
- Suggested commit: `docs: reconcile substrate decisions`
- Do not push or open a PR without explicit operator instruction.

## Steps

### Step 1: Reconfirm live evidence before editing

Run:

```bash
./scripts/check-shared-substrate.sh
rg -n 'dowdiness/incr@' moon.mod
```

Expected at plan time: nine members agree on minor 0.14 and exact 0.14.2. The
exact future pin/count may legitimately change; the invariant is one agreed
minor. Stop if consumers disagree.


### Step 2: Separate historical baseline from live pin authority in the incr ADR

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

### Step 3: Remove mutable version duplication from governance docs

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

### Step 4: Run consistency and documentation gates

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
- only the three in-scope docs plus plan/index bookkeeping changed for this
  task.

Run the final active-doc search:

```bash
! rg -n '0\.9\.0 as the current exact target|registry 0\.13\.0|locks canopy/loom/moondsp at incr minor 0\.9' \
  docs/README.md docs/decisions
```

Expected: no mutable version is presented as current policy.

## Test plan

Documentation consistency is tested through live authorities:

- execute `scripts/check-shared-substrate.sh` rather than copying expected pins;
- use negative searches for the exact false-current phrases;
- run link and whitespace checks.

No source test or snapshot update is needed because source, CI, and manifests
remain untouched.

## Done criteria

- [x] The incr ADR preserves 0.9.0 as dated historical evidence only.
- [x] Current pin authority is manifests plus the shared-substrate guard.
- [x] Governance and docs-index summaries do not duplicate mutable incr versions.
- [x] `./scripts/check-shared-substrate.sh` and link checks exit 0.
- [x] ~~No source, CI, manifest, script, test, or out-of-scope doc changed.~~
  Superseded by the approved integrated Phase 2 scope; this plan's ADR changes
  remain documentation-only and the broader changes are recorded separately.

## STOP conditions

Stop and report if:

- workspace members disagree on the `incr` major/minor;
- preserving cross-repo policy requires unverifiable current moondsp claims;
- a correction appears to require changing code, CI, manifests, or dependency
  versions.

## Maintenance notes

ADRs may retain dated version evidence, but mutable “current version” claims
belong in manifests and executable guards. Future dependency bumps should not
edit historical baseline numbers; they should update manifests, satisfy the
guard, and amend only policy or topology facts that genuinely changed.