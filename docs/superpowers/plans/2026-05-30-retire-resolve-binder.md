# Plan: Retire `resolve_binder` — finish the binder-lookup consolidation

**Status:** Ready to execute (fresh session). Scope validated by Codex (verdict
SOUND, 2026-05-30). Follow-on to PR #396 (`lang/lambda/scope/` binding index,
squash `4875da6`).

**Parent docs:**
- Design spec: `docs/superpowers/specs/2026-05-30-lambda-scope-graph-design.md`
- Parent plan: `docs/superpowers/plans/2026-05-30-lambda-scope-graph.md`

---

## Why this, and why only this

PR #396 introduced `@scope` (`build`/`declaration`/`references`/`enclosing_env`)
and migrated **one** consumer — `rename_from_var` — from the old
`resolve_binder()` to `@scope.declaration()`, proving equivalence in
`scope_equivalence_wbtest.mbt`. That left the codebase at the *worst* point on
the consolidation curve: **two** name-resolution implementations that must stay
in agreement, with only one of the old binder-lookup sites migrated.

This plan migrates the **last** `resolve_binder` caller and deletes
`resolve_binder` entirely, removing the duplicated binder-lookup path. It is
deliberately scoped to the **equivalence-preserving** part only.

**Explicitly out of scope** (separate, behavior-*changing* work — do NOT fold in):
- `find_usages` → `references()`: name-based vs identity-based; a latent-bug fix,
  not a move. Needs its own behavioral tests.
- `collect_lam_env` → `enclosing_env()`: `enclosing_env` is a *superset* (adds
  module defs); changes capture-avoidance rejection logic. Needs its own analysis.
- `free_vars`: different query class (term fold, no NodeId). Leave in place.

Those three keep their current behavior after this plan. The single migrated
function (`compute_inline_definition`) will use `@scope.declaration()` for the
binder lookup while still calling the old `find_usages`/`collect_lam_env` — that
mixed state is **intentional and correct** (Codex finding #5): it preserves the
two un-migrated queries' existing behavior rather than silently changing it.

---

## Verified facts (checked against live code 2026-05-30)

- The **only** non-test caller of `resolve_binder` is `compute_inline_definition`
  at `lang/lambda/edits/text_edit_refactor.mbt:143`. It uses the returned
  `BindingSite` solely to (1) reject `LamBinder` with an error, and (2) read
  `def_index` from `ModuleBinder`. (`text_edit_refactor.mbt:147-150`)
- `@scope.declaration()` returns `Decl?`; `Decl.kind` is `DeclKind::LamParam(lam_id~)`
  / `DeclKind::ModuleDef(def_index~)` (`lang/lambda/scope/graph.mbt:16`), carrying
  the identical Lam-vs-Module + `def_index` split. The shipped `rename_from_var`
  migration is the exact template (`text_edit_rename.mbt`: `using @scope { type
  DeclKind }`, `let g = @scope.build(...)`, `guard @scope.declaration(g, id) is
  Some(decl)`, `match decl.kind { DeclKind::LamParam(..) / DeclKind::ModuleDef(..) }`).
- `find_enclosing_lam_binder` (`scope.mbt:57`) is **private** and used **only** by
  `resolve_binder` (`scope.mbt:19,70,72`). It dies with `resolve_binder`.
- `BindingSite` (`scope.mbt:3`) is `pub(all)` and `resolve_binder` is `pub`; both
  appear in `lang/lambda/edits/pkg.generated.mbti` (lines 45, 25). After the
  migration, `BindingSite`'s only producers/consumers are `resolve_binder` and
  the equivalence test — so it becomes dead too.
- **No main-tree consumer outside the edits package** references `resolve_binder`
  or `BindingSite` (verified via `moon ide find-references` + grep over
  `ffi/`, `examples/`, `lang/lambda/top.mbt`). Worktree hits under `.worktrees/`
  and `.claude/worktrees/` are other branches and do not count.
- The equivalence test **uses `resolve_binder` as its oracle**
  (`scope_equivalence_wbtest.mbt:39-41`): it asserts
  `declaration(...) == resolve_binder(...)`. Deleting `resolve_binder` therefore
  breaks the test's reference — this is the critical-path item (Step 3).

---

## Public-API note (call out in the PR)

This removes `resolve_binder` (`pub`) and `BindingSite` (`pub(all)`) from the
edits package's public `.mbti`. That is an intentional API contraction, justified
because (a) no in-repo consumer uses them and (b) `@scope.declaration` +
`@scope.Decl`/`DeclKind` are the canonical replacement. Per the
aspirational-library framing, surface this explicitly in the PR description's
Reuse-check section rather than letting it pass silently in the `.mbti` diff.

---

## Steps

Run `moon check` after **every** file edit (Incremental Edit Rule). Use
`NEW_MOON_MOD=0` on every `moon fmt` / `moon info` / `moon ide` invocation.

### Step 1 — Migrate the last `resolve_binder` caller
**File:** `lang/lambda/edits/text_edit_refactor.mbt` (`compute_inline_definition`,
around line 143).

- Replace the `guard resolve_binder(...) is Some(binder)` block with the
  `@scope.build` + `@scope.declaration` pattern, mirroring `text_edit_rename.mbt`
  line-for-line. Add `using @scope { type DeclKind }` to the file if not present.
- Rewrite the subsequent `match binder { LamBinder(..) => ...; ModuleBinder(..)
  => ... }` to `match decl.kind { DeclKind::LamParam(..) => <same error>;
  DeclKind::ModuleDef(def_index~) => <same body> }`.
- **Leave untouched** the later `free_vars`, `collect_lam_env`, and `find_usages`
  calls in the same function. Only the binder lookup changes.
- **Invariant:** for every input, the new binder lookup yields the same
  Lam-reject / Module-`def_index` decision as before — this is exactly what the
  equivalence test (now standing on its own, Step 3) certifies for `declaration`.

### Step 2 — Delete the retired old-path code
**File:** `lang/lambda/edits/scope.mbt`.

- Delete `resolve_binder` (`:11`), `find_enclosing_lam_binder` (`:57`), and the
  `BindingSite` enum (`:3`) **only after** Step 3 has removed the test's
  dependence on them (do Step 3's test edits first, or do 2+3 together, so the
  package never fails to compile mid-step).
- Keep `find_usages`, `collect_var_usages`, `find_binding_for_init`,
  `collect_lam_env` — still live.
- **Verify before deleting:** re-run `moon ide find-references` on each of the
  three symbols and confirm zero remaining references outside the deletions
  themselves. (Pre-Execution check — the first unexpected hit means stop.)

### Step 3 — Rewrite the equivalence test to a frozen oracle (CRITICAL)
**File:** `lang/lambda/edits/scope_equivalence_wbtest.mbt`.

The test currently certifies "`declaration` agrees with `resolve_binder`." Once
`resolve_binder` is gone, that comparison is impossible **and** would be circular
if re-pointed at any code under test. Convert it to assert `declaration`'s result
against a **frozen, structurally-derived expectation** per case:

- Remove `norm_binder`, the `resolve_binder` arm of `agree`, and `var_name_of`
  (it existed only because `resolve_binder` needed the name string).
- Keep `norm_decl`, `find_var`, `scope_test_registry`, the parse helpers, and the
  full 8-case list (lam param; module body; self-ref→unbound; shadowing/latest;
  earlier-can't-see-later→free; nested lam shadow; lam-param-shadows-module-def;
  later-def-init-resolves-to-earlier).
- For each case, assert the **frozen** outcome of `declaration(g, var_id)`:
  - the **resolve/free distinction** — the two free/unbound cases assert `None`;
  - for resolved cases, the **kind discriminant** (`"lam"` / `"module"`) and, for
    module defs, the **`def_index` integer** (both scalars);
  - the **binder identity** — assert the resolved `Decl.node_id` equals the
    expected binder located **structurally** in the parsed tree (reuse a locator
    like `find_var` / `root.children[..]`), NOT a magic NodeId literal and NOT a
    second call through `declaration`. (Non-circular drift-detector rule.)
- **Constraint to honor:** the repo derives `Debug`/`Eq`, not `Show`. `inspect`
  must target **scalar** fields (the tag `String`, the `def_index` `Int`, a
  structural-equality `Bool`) — never a whole `Decl`/`DeclKind` value.
- Rename the test to drop "matches resolve_binder" (e.g. "declaration() resolves
  each binding rule to the expected decl").
- **This is the bulk of the effort.** Reason each expected value out by hand from
  the source string + the binding rules; do not compute it by re-running the code
  you are testing.

### Step 4 — Regenerate interface, format, verify
- `NEW_MOON_MOD=0 moon info` then inspect `git diff lang/lambda/edits/pkg.generated.mbti`:
  expect `resolve_binder` and `BindingSite` **removed**; no other public-symbol
  changes; no trait-bound widening elsewhere.
- `NEW_MOON_MOD=0 moon fmt`.
- `moon check` (full) and `moon test -p lang/lambda/edits -p lang/lambda/scope`
  green; then full `moon test` to confirm no workspace regression.
- Confirm the rewritten equivalence test actually **ran** (case count matches the
  8 declarations) — green ≠ executed.

### Step 5 — Codex pre-PR review, then PR
- Ask Codex (read-only) to confirm: the inline-refactor migration preserves the
  Lam-reject / Module-`def_index` decision; the rewritten test is non-circular and
  its frozen expectations match the binding rules; the `.mbti` contraction has no
  missed consumer.
- Open the PR with a Reuse-check section flagging the `resolve_binder`/`BindingSite`
  removal as an intentional API contraction.

---

## Verification checklist
- [ ] `compute_inline_definition` uses `@scope.declaration`; `free_vars` /
      `collect_lam_env` / `find_usages` in it unchanged.
- [ ] `resolve_binder`, `find_enclosing_lam_binder`, `BindingSite` deleted; no
      dangling references (`moon ide find-references` clean).
- [ ] Equivalence test self-contained (no `resolve_binder`), frozen + structural
      expectations, scalar-only `inspect`, all 8 cases present and executed.
- [ ] `pkg.generated.mbti` diff shows only the two intended removals.
- [ ] Full `moon test` green; Codex review PASS.

## Risks / watch-items
- **Half-migrated function is intentional** — do not "tidy" by also swapping
  `find_usages`/`collect_lam_env` here; that silently changes behavior (the whole
  reason they're out of scope).
- **Circular test trap** — the single biggest failure mode is re-deriving the
  test's expected values from the code under test. Hand-derive them.
- **Mid-step compile breakage** — sequence Step 3's test edits with Step 2's
  deletions so the `edits` package always compiles.

## Resolved in passing by this plan
- **`containing_def_index` ↔ `resolve_binder` def-range mirror.** A line-level
  review flagged that `containing_def_index` (builder) and `resolve_binder`
  (`scope.mbt`) implement the same def-range containment twice, risking drift.
  This plan **eliminates** that risk rather than managing it: deleting
  `resolve_binder` (Step 2) removes one side of the mirror outright, and
  rewriting the equivalence test to a frozen snapshot (Step 3) means the
  remaining single implementation has no twin to drift against. No shared-helper
  extraction needed — one implementation is simply gone.

## What this unblocks
After `resolve_binder` is retired, the remaining consolidation is the two
behavior-*changing* migrations, each its own scoped unit with its own tests:
(B) `find_usages` → `references()` (identity-based; likely fixes shadow-rename
bugs), (C) `collect_lam_env` → `enclosing_env()` (superset; capture-check impact).
These are the first real consumers of the reserved `references()` /
`enclosing_env()` API.

### (D) Query-side indexing — gated follow-up (from line-level review, 2026-05-30)
The package is named a "NodeId-keyed index," but its query entry points scan
linearly: `declaration` is O(refs); `references` is O(decls) + O(refs);
`enclosing_env` is O(refs) + O(decls) before an O(depth) parent walk. The sharp
framing is **not** "the index lacks a lookup structure" but "**the index already
computed the lookup structure and discarded it**": `Builder.node_scope`
(`Map[NodeId, ScopeId]`) is built and then dropped at `build()`'s return
(`{ scopes, decls, refs }`), and `root_node()` computes the root Module node then
throws it away — forcing `rename_*` to re-scan the registry to recover it. The
fix is "retain what build already computed," not "build something new." This is
also where the spec's motivation #1 (kill O(N²) lookup) is only **half**
delivered: the build side is O(N), the query side is still linear.

Three pieces with **deliberately distinct gates** — do NOT file as one
undifferentiated "add indices" task (that re-imports the over-broad "make it
O(1)" framing this review already corrected):

- **Forward index** — retain `node_scope` (and add `Map[NodeId, RefId]` /
  `Map[NodeId, DeclId]`) so `declaration` becomes genuinely O(1) and
  `references`/`enclosing_env` get O(1) *entry* lookup. **Gate:** justified the
  moment any consumer does *repeated single-entry* lookups against a built graph.
- **Reverse index** — `Map[DeclId, Array[RefId]]` so `references`' *enumeration*
  is O(result) instead of O(refs). **Strictly higher gate:** justified *only if*
  `references`-style enumeration is shown to be a **measured hot path**. Filing it
  with the forward index risks adding the reverse map when only the forward map
  is warranted. `enclosing_env`'s parent walk stays O(depth) irreducibly —
  indexing does not touch it.
- **Module/root NodeId on `ScopeGraph`** (secondary finding (a)) — carry
  `root_node(registry).id()` (already computed during build) so the `rename_*`
  paths stop re-scanning the registry for the Module node. Same "retain, don't
  recompute" family; a constant factor *inside already-O(N)* build+rename, not a
  scaling fix, so it ranks below the forward index.

**API discipline (all three):** hold indices **privately** — do not append them
as fields to the `pub(all)` `ScopeGraph` (compile-non-breaking, but it leaks impl
detail into the public contract). Use the occasion to revisit whether
`ScopeGraph` should be `pub(all)` at all.

**Overall gate (reproduce-bottleneck-first):** none of (D) lands until (B)/(C)
put real consumers on `references`/`enclosing_env` **and** a microbenchmark shows
query latency biting — the same discipline the spec committed to for
incrementality (the p95 trigger metric). Today `declaration` is called once per
rename; adding indices now would optimize a non-bottleneck — exactly the
speculative optimization the spec's own framing warns against.
