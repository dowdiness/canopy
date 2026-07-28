# Plan 005: Document the complete B-tree construction, mutation, and range contracts

> **Executor instructions**: Execute only after Plans 001–004 have landed or
> been explicitly rejected, because this plan documents their final behavior.
> Follow every verification gate. Do not change runtime behavior in a docs plan;
> if documentation exposes a behavior mismatch, stop and report it.
>
> **Drift check (run first)**:
> `git diff --stat 8e400bbb..HEAD -- lib/btree/README.md lib/btree/btree.mbt lib/btree/walker_types.mbt lib/btree/pkg.generated.mbti`
> Changes from Plans 001–004 are expected. Re-read the live signatures and
> behavior before drafting. Any unresolved plan dependency is a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/001-bound-btree-min-degree.md`,
  `plans/002-enforce-positive-btree-spans.md`,
  `plans/003-snapshot-leaf-context-neighbors.md`,
  `plans/004-reuse-btree-bulk-builder.md`
- **Category**: docs
- **Planned at**: commit `8e400bbb`, 2026-07-28

## Why this matters

The README lists operations and complexity but does not define the contracts
needed to use its low-level callback API safely. Users cannot currently tell
which ranges clamp or no-op, when insertion aborts, what splice indices mean,
or which span values are valid. Add one authoritative contract section and
matching public doc comments so external users do not need to infer behavior
from walker internals.

## Current state

The API table at `lib/btree/README.md:56-66` gives one-line descriptions but
omits invalid-input behavior. Relevant source behavior at planning time:

- `mutate_for_insert` requires a non-empty tree and aborts if descent fails
  (`lib/btree/btree.mbt:41-72`).
- `mutate_for_delete` returns `None` for empty/out-of-range positions and
  validates before its prepare hook mutates (`lib/btree/btree.mbt:77-109`).
- `delete_range` uses half-open `[start, end)`, no-ops for negative/empty/
  reversed/out-of-start bounds, and clamps an oversized end
  (`lib/btree/btree.mbt:112-132`).
- `view` clamps negative start to zero and oversized end to total, while an
  empty/reversed/negative-end result is empty (`lib/btree/btree.mbt:258-280`).
- `Splice` has public fields but no source doc comment defining their interval
  (`lib/btree/walker_types.mbt:64-69`).
- `from_sorted` says callers own canonical adjacent-merge policy but does not
  specify the span validity requirement (`lib/btree/btree.mbt:182-190`).

After earlier plans, re-read rather than copying these facts blindly:

- Plan 001 bounds normalized degree.
- Plan 002 makes positive spans an enforced invariant.
- Plan 003 removes the live `LeafContext.children` array and makes neighbors a
  snapshot.
- Plan 004 makes B-tree state fields private and leaves `BTreeNode` visibility
  unchanged.

Documented design constraints:

- Ranges are half-open. The accepted unit-boundary decision requires edge-case
  behavior for negative, reversed, zero-length, and clamped deletion ranges to
  be explicit (`docs/decisions/2026-06-13-range-span-unit-boundaries.md:49-64`).
- B-tree is the low-level engine; order-tree is the standard sequence API
  (`lib/btree/README.md:72-86`). Preserve that vocabulary.
- Documentation should describe behavior, not restate implementation structure.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Signature preflight | `NEW_MOON_MOD=0 moon ide outline lib/btree` | public signatures match live `.mbti` |
| B-tree check | `moon check --deny-warn lib/btree` | exit 0, including doc comments/examples |
| B-tree tests | `moon test --release lib/btree` | all tests pass |
| Downstream tests | `moon test --release -p dowdiness/order-tree` | all tests pass |
| Format/interface | `NEW_MOON_MOD=0 moon fmt lib/btree && NEW_MOON_MOD=0 moon info lib/btree` | exit 0; only the selected package is refreshed |
| Markdown hygiene | `git diff --check -- lib/btree/README.md` | exit 0 |

There is no Canopy-root docs checker for this standalone README; do not run
`loom/check-docs.sh`, which owns a different module.

## Suggested executor toolkit

Use `moonbit-agent-guide`, `slopless`, or a documentation reviewer if available.
Any MoonBit examples added to source doc comments should use `mbt check` fences
where the package's docs tooling supports them.

## Scope

**In scope**:

- `lib/btree/README.md`
- `lib/btree/btree.mbt` — public doc comments only
- `lib/btree/walker_types.mbt` — `LeafContext`/`Splice` doc comments only
- `lib/btree/pkg.generated.mbti` only as generated output

**Out of scope**:

- Runtime behavior, validation, or signatures.
- New error types or constructor APIs.
- `order-tree` documentation.
- Changing advertised complexity without new measurement.
- Documenting BTreeNode as a stable construction API.
- The formal-verification direction option.

## Git workflow

- Branch: `advisor/005-document-btree-contracts`
- Suggested commit: `docs(btree): define mutation and range contracts`
- Do not push/open a PR without explicit operator instruction.
- Preserve unrelated modified submodules.

## Steps

### Step 1: Build a live behavior matrix

Before writing prose, inspect the final implementations and tests for:

- `BTree::new`
- `init_root`
- `from_sorted`
- `mutate_for_insert`
- `mutate_for_delete`
- `delete_range`
- `view`
- `LeafContext`
- `Splice`

Create a scratch matrix in the executor report, not a repository file, with
valid range, invalid range, empty tree, degree handling, span handling, and
failure mode. Cross-check named tests, especially range tests and Plans 001–003
regressions.

**Verify**: every row has a source `file:line` and a test name. If source and
test disagree, STOP and report rather than choosing one.

### Step 2: Add an API contracts section to the README

In `lib/btree/README.md`, add a concise section after the API table and before
Relationship to Other Libraries. It must cover:

#### Construction

- normalized `min_degree` interval from Plan 001;
- empty construction;
- `init_root` use for the first element;
- `from_sorted` preserves input order and expects caller canonicalization;
- strictly positive explicit spans and the exact invalid-span failure mode from
  Plan 002.

#### Position and range semantics

- coordinate unit is each element's supplied span;
- all ranges are half-open `[start, end)`;
- a compact table for `find/get_at`, insert, delete callback, `delete_range`,
  and `view`, listing valid bounds and invalid behavior;
- distinguish clamp, empty result/no-op, `None`, and abort precisely.

#### Callback/splice contract

- `LeafContext` is a value snapshot containing current element, span, offset,
  child index, and optional adjacent leaf values; it exposes no live tree
  collection after Plan 003;
- callback code computes and returns a description; propagation alone mutates
  the tree;
- `Splice.start_idx` is inclusive and `end_idx` exclusive in the current leaf
  parent's child array;
- valid relationship `0 <= start_idx <= end_idx <= parent child count`;
- `new_leaves` replace that interval in order and every span must be positive;
- show the four canonical shapes: insert, replace, delete, split. Use symbolic
  indices, not a large implementation listing.

Do not promise that arbitrary invalid splice indices are validated if the code
still relies on caller correctness.

**Verify**: manually compare every claim against the Step 1 matrix, then run
`git diff --check -- lib/btree/README.md`.

### Step 3: Align public source doc comments

Update public doc comments in `lib/btree/btree.mbt` and
`lib/btree/walker_types.mbt` so generated API documentation carries the same
contract:

- constructor degree and positive-span constraints;
- insert/delete callback bounds and outcomes;
- delete_range/view invalid-bound behavior;
- `LeafContext` snapshot semantics;
- field-level `Splice` interval semantics.

Keep comments short and link conceptual detail back to README where appropriate.
Do not add implementation-specific repair details to public docs.

**Verify**: `moon check --deny-warn lib/btree` exits 0.

### Step 4: Validate examples and consumers

Run package and direct-consumer tests. Documentation-only changes must not alter
behavior or public signatures.

**Verify**:

```bash
moon test --release lib/btree
moon test --release -p dowdiness/order-tree
```

Both exit 0.

### Step 5: Format, regenerate, and review drift

Run formatter and interface generation because MoonBit doc comments may affect
generated API artifacts. Review the diff for behavior edits.

**Verify**:

```bash
NEW_MOON_MOD=0 moon fmt lib/btree
NEW_MOON_MOD=0 moon info lib/btree
git diff --check
git diff --stat
git diff -- lib/btree/btree.mbt lib/btree/walker_types.mbt
git status --short
```

Expected: source diffs contain comments only; README is the only prose file;
no unrelated files or submodule pointers are staged.

## Test plan

No new behavioral test is required if Plans 001–003 already landed and all
documented rows have named coverage. If the behavior matrix finds an
undocumented edge with no test, STOP and create a separate test-plan amendment
instead of adding runtime/test scope silently.

Required verification:

- all B-tree tests;
- direct order-tree consumer tests;
- strict package check;
- Markdown whitespace check.

## Done criteria

- [ ] README defines degree, span, position, range, callback, and splice
      contracts without requiring source-code inference.
- [ ] Clamp/no-op/empty/None/abort outcomes are distinguished accurately.
- [ ] Source doc comments agree with README and final implementations.
- [ ] No claim says invalid splice indices are validated unless code proves it.
- [ ] `moon check --deny-warn lib/btree` passes.
- [ ] B-tree and order-tree tests pass.
- [ ] No runtime code or public signature changes appear in the diff.
- [ ] No out-of-scope files are modified.
- [ ] The Plan 005 row in `plans/README.md` is updated.

## STOP conditions

Stop and report if:

- Any dependency plan is incomplete, blocked, or rejected without an updated
  final contract.
- Source and tests disagree on an edge-case outcome.
- Accurate docs would require a runtime behavior change.
- `Splice` index validity cannot be stated from current code and consumers.
- Interface generation shows a signature or trait-bound change.
- A verification command fails twice after one reasonable correction.

## Maintenance notes

- Update the contract table whenever range clamping, callback failure behavior,
  or span validation changes.
- Reviewers should compare docs against tests, not only prose readability.
- Keep complexity claims conservative. Issue #515 already tracks measured
  investigation of worst-case `delete_range` repair; do not preempt it here.
