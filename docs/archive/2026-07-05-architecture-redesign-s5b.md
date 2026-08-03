# S5b — Architecture Redesign De-dup Execution

**Date:** 2026-07-05
**Status:** Executed (2026-07-05)
**Expiry:** RESOLVED by execution on 2026-07-05. Re-evaluation deadline
2026-09-12 was met. The dual-source exception is closed; the `./rle` submodule
was removed.
**Direction:** Per S5a ADR
([substrate governance](../decisions/2026-06-12-substrate-governance.md)):
loom migrates to registry `event-graph-walker`; canopy keeps its direct
submodule.

## Current State

### Loom (submodule at `loom/`, HEAD `1888d83` on `chore/changelog-619`)

- `loom/moon.work` lists `"./event-graph-walker"` as workspace member
- `loom/.gitmodules` has a nested event-graph-walker submodule
- **No loom package outside `event-graph-walker/` itself imports egw** — the
  sole consumer is `loom/examples/lambda`, which already declares egw from
  **registry** (`dowdiness/event-graph-walker@0.3.0` in its `moon.mod`)
- loom core (`loom/loom/moon.pkg`) has zero egw dependency
- `.mooncakes/dowdiness/event-graph-walker/` is empty locally (shadowed by
  workspace member path-dep)

### Canopy

- `moon.work` lists `"./event-graph-walker"` as member — **KEPT** per S5a
- `moon.mod` declares `dowdiness/event-graph-walker@0.3.0` (registry pin for
  non-workspace consumers; workspace member takes precedence)
- egw submodule SHA `a7d813c` = registry v0.3.0 (in sync)
- `./rle` submodule at `a6ffa40` — **BUILD-INERT**: no moon.pkg/moon.mod in
  canopy references it as path-dep; all consumers (`event-graph-walker`,
  `order-tree`, `lib/btree`) use registry `dowdiness/rle@0.2.x`

### Guard script

`scripts/check-egw-resolver-identity.sh` currently compares two gitlinks:
canopy's `HEAD:event-graph-walker` vs loom's nested
`<HEAD:loom>:event-graph-walker`.  Lines 43-48 have a pre-written fail message
telling the S5b PR to update the guard: after S5b there is no nested gitlink to
compare against; the guard must shift to verifying that the canopy submodule's
version matches the version pinned in loom's examples/lambda manifest
(registry pin). The version consistency check (Python block, lines 76-137)
already covers all `moon.work` members including `loom/examples/lambda` —
that section stays.

## Scope

**In:**

1. Canopy: remove BUILD-INERT `./rle` submodule (`.gitmodules`, `moon.work`,
   working tree)
2. Loom: remove BUILD-INERT `./event-graph-walker` workspace member (nested
   submodule + `moon.work` entry)
3. Canopy: update `scripts/check-egw-resolver-identity.sh` to compare canopy's
   submodule version against loom's registry pin (the old gitlink cross-check
   is dead)
4. Canopy: bump loom submodule pointer to a loom commit that has the egw
   submodule removed

**Out:**

- Canopy's egw submodule — KEPT per S5a
- Loom's other submodules (incr, egraph, egglog) — unchanged
- Loom's own rle submodule — loom has its own copy, unchanged
- `scripts/check-shared-substrate.sh` — unchanged (it only checks incr version
  coherence, unaffected by this change)

## Execution Steps

### Phase 1 — Loom: remove egw workspace member

The loom submodule is on local-only `chore/changelog-619`. Create a fresh
branch from `origin/main`.

```bash
cd loom
git fetch origin
git checkout -b chore/remove-egw-submodule origin/main
```

Edit `loom/moon.work` — remove `"./event-graph-walker"` from the members array.
Remove it as a line deletion; no other members change.

Edit `loom/.gitmodules` — remove the `[submodule "event-graph-walker"]` section
(3 lines: header + path + url).

```bash
git submodule deinit event-graph-walker
git rm event-graph-walker
git add moon.work .gitmodules
git commit -m "chore: remove event-graph-walker workspace member

The nested event-graph-walker submodule is BUILD-INERT — no package
outside event-graph-walker/ itself imports it. The sole downstream
consumer (examples/lambda) already uses the registry pin
(dowdiness/event-graph-walker@0.3.0 in its moon.mod).

Part of canopy S5b de-dup (architecture redesign).

See https://github.com/dowdiness/canopy"
git push origin chore/remove-egw-submodule
```

Create PR in loom repo (`dowdiness/loom`). Title:
`chore: remove event-graph-walker workspace member (S5b de-dup)`.


### Phase 2 — Canopy: update loom parent pointer

After loom PR #N merges to `origin/main`:

```bash
cd loom
git fetch origin
git checkout origin/main   # or the merge commit
cd ..
git add loom
```

### Phase 3 — Canopy: remove BUILD-INERT rle submodule

Independent of loom changes; can be in the same canopy PR as Phase 2.

Edit `moon.work` — remove `"./rle"` from the members array.

Edit `.gitmodules` — remove the `[submodule "rle"]` section (3 lines).

```bash
git submodule deinit rle
git rm rle
git commit -m "chore: remove BUILD-INERT rle submodule

All consumers (event-graph-walker, order-tree, lib/btree) use the
registry pin dowdiness/rle@0.2.x. The submodule at ./rle is unreferenced
as a path-dep by any moon.pkg/moon.mod.

See https://github.com/dowdiness/canopy"
```

### Phase 4 — Canopy: update resolver-identity guard script

The guard at `scripts/check-egw-resolver-identity.sh` currently compares two
gitlinks. After S5b, there is only one gitlink (canopy's direct submodule).
The guard must be rewritten to:

1. **Remove** the nested-gitlink comparison (lines 33-58: `direct_sha`,
   `loom_sha`, nested SHA fetch/verify, drift check).
2. **Replace** with: extract the version from loom's registry pin
   (`loom/examples/lambda/moon.mod` declares
   `dowdiness/event-graph-walker@0.3.0`) and compare it to the canopy
   submodule's pinned commit version.
3. **Keep** the version-consistency Python block (lines 76-137) — it already
   scans all `moon.work` members, including `loom/examples/lambda`.

New guard logic sketch:

```
direct_sha=$(git rev-parse HEAD:event-graph-walker)
pinned_version=$(git -C event-graph-walker show "${direct_sha}:moon.mod" \
  | sed -n 's/^version = "\(.*\)"/\1/p')

# Extract loom's registry pin
lam_version=$(sed -n 's/.*dowdiness\/event-graph-walker@\([^"]*\).*/\1/p' \
  loom/examples/lambda/moon.mod)

[ "${pinned_version}" = "${lam_version}" ] \
  || fail "version mismatch: canopy submodule pins ${pinned_version}, \
           loom registry pin declares ${lam_version}"

# Run the existing workspace-member version consistency check
PINNED_VERSION="${pinned_version}" python3 - <<'PY' ...
```

Replace the final line from `"OK — both egw resolution paths pin..."` to
`"OK — legacy-submodule pin ${direct_sha} (${pinned_version}) matches loom
registry pin (${lam_version}) and all N workspace manifests agree."`

> **Same-PR requirement:** The guard update MUST land in the same canopy PR as
> the loom pointer bump (Phase 2). If the guard runs against a loom commit
> that still has the nested gitlink, the old guard checks pass; if against one
> that has removed it, the old guard crashes. The guard and the pointer bump
> must flip together.

### Phase 5 — Canopy: amend substrate governance ADR

The governance ADR (`docs/decisions/2026-06-12-substrate-governance.md`) must
be updated to reflect the post-S5b topology:

| Section | Current text | Change |
|---------|-------------|--------|
| §2 (line 57) | `event-graph-walker` is the **sole dual-source exception**, transitional | egw is no longer a dual-source exception. Rewrite: `event-graph-walker` is resolved from a **single source** (canopy's direct submodule). The nested copy in loom has been removed (S5b executed). |
| §3 (lines 70-79) | "After S5b executes, loom's nested copy disappears..." and "The guard fails loudly if the nested gitlink disappears" | Replace with: "S5b executed 2026-07-05. Loom's nested egw copy removed; canopy's direct submodule is the single source. The guard was updated to compare submodule version against loom's registry pin." |
| §4 (lines 82-84) | Re-evaluation date 2026-09-12 | Mark as "Resolved by S5b (2026-07-05)" |
| Policy table egw row (line 94-95) | `dual` (direct submodule + loom nested copy) | `submodule` — single source. Remove exception notes. |
| Policy table rle row (line 102-103) | "build-inert; remove or wire in at S5b re-evaluation" | rle submodule removed. Remove the build-inert flag. |

### Phase 6 — Canopy: commit and PR

```bash
grep -rn "dowdiness\/event-graph-walker" moon.pkg --include="moon.*" \
  2>/dev/null | grep -v ".mooncakes"
# Verify: no path-deps to ./event-graph-walker outside the intended submodule

git add -A
git commit -m "architecture-redesign S5b: remove BUILD-INERT submodules

- Loom pointer bumped to commit {LOOM_SHA} (egw workspace member removed)
- ./rle submodule removed (BUILD-INERT — all consumers use registry)
- scripts/check-egw-resolver-identity.sh updated: post-removal, compares
  canopy submodule version against loom's registry pin instead of two
  gitlinks
- docs/decisions/2026-06-12-substrate-governance.md amended: egw mechanism
  changed from `dual` to `submodule`; rle build-inert flag removed

Expires: 2026-09-12 (dual-source exception; ./rle re-evaluation).
Closes: #TBD"
```

## Verification

# Phase 1 (within loom submodule)
cd loom
moon check                           # workspace lint — must pass
moon test                            # workspace tests — must pass
cd ..

# Phases 2–6 (canopy root)
cd ..
moon check                           # workspace lint — must pass
moon test                            # workspace tests — must pass
scripts/check-egw-resolver-identity.sh  # guard script must exit 0
NEW_MOON_MOD=0 moon info && git diff '*.mbti'  # no unexpected API changes
```

**Known timing:** The first `moon check` after removing egw from loom's
workspace will actually resolve from registry for the first time (the
`.mooncakes/dowdiness/event-graph-walker/` was empty locally, shadowed by the
workspace member path-dep). This is the real registry-resolution test — if it
passes, the de-dup is sound.

## Risks

| Risk | Mitigation |
|---|---|
| Loom submodule on local-only branch | Phase 1 creates fresh branch off `origin/main` — no local-only history risk |
| Submodule push order violation | Phase 1 PR must merge before Phase 2. CI blocks if loom SHA not on remote |
| Guard script crashes after removal | Phase 4 rewrites it in the same PR (pre-written fail message at lines 44-48 would fire if skipped) |
| Some loom package silently path-deps the member egw | Scan before Phase 1: only `examples/lambda/moon.pkg` imports egw, and it uses registry. Confirm no other `moon.pkg` has a path-dep to `event-graph-walker` without `@version` |
| MoonBit workspace resolves egw name differently without the member | The member shadowed registry — removing it means registry resolution activates. This IS the desired state. If a package depended on the member's specific SHA, the registry might serve a different version. But `examples/lambda` already pins `@0.3.0` matching the member's `moon.mod` version — no drift. |
| Loom PR CI fails | Fix in loom repo first, then re-pin canopy pointer |

## Acceptance Criteria

Verified 2026-07-05, post-execution audit. Evidence per item:

- [x] `loom/moon.work` no longer lists `"./event-graph-walker"` — `git show
  f56e497:moon.work` (the committed pointer): zero matches
- [x] `loom/.gitmodules` no longer has an egw submodule entry — same commit,
  zero matches
- [x] `moon check` passes in loom workspace — loom PR #623 merged; check-runs
  on merge commit `f56e497`: 0 non-success
- [x] `moon test` passes in loom workspace — same CI run
- [x] `moon.work` no longer lists `"./rle"`
- [x] `.gitmodules` no longer has an rle submodule entry
- [x] `./rle/` directory is gone from working tree
- [x] `scripts/check-egw-resolver-identity.sh` exits 0 — re-run 2026-07-05:
  "OK — submodule pin a7d813c (0.3.0) matches loom registry pin (0.3.0) and
  all workspace manifests agree"
- [x] `moon check` passes at canopy root — check-runs on main HEAD `c6ae2e1`:
  0 non-success (incl. Test Main Module, Test Submodules, Format Check)
- [x] `moon test` passes at canopy root — same CI run
- [x] No `.mbti` drift — companion interface regen committed as `cd35793`;
  Format Check green
- [x] Loom pointer bump AND guard script update landed together — both in
  commit `528c80a`. **Deviation:** landed as a direct push to main, not the
  canopy PR this plan specified (Phase 6); the same-commit atomicity
  requirement itself was met
- [x] `docs/decisions/2026-06-12-substrate-governance.md` amended per
  Phase 5 — in `528c80a`
