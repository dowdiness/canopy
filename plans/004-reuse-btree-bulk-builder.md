# Plan 004: Reuse `BTree::from_sorted` in order-tree and make B-tree state opaque

> **Executor instructions**: This is a cross-repository migration. Read the
> whole plan before editing. Complete the `order-tree` submodule phase first,
> verify it independently, and do not update the Canopy gitlink until the
> submodule commit exists on its remote. Never push, open a PR, or publish
> without explicit operator approval. Stop rather than weakening tests or
> exposing replacement internals.
>
> **Parent drift check (run first)**:
> `git diff --stat 8e400bbb..HEAD -- lib/btree/types.mbt lib/btree/pkg.generated.mbti order-tree`
>
> **Submodule drift check (run first)**:
> `git -C order-tree diff --stat ccbcda8..HEAD -- bulk_build.mbt invariant_wbtest.mbt walker_wbtest.mbt pkg.generated.mbti`
>
> Plans 001–003 are expected to alter other B-tree files. Any drift in the
> files above or a dirty `order-tree` working tree is a STOP condition until
> reconciled with the operator.

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: `plans/003-snapshot-leaf-context-neighbors.md`
- **Category**: migration
- **Planned at**: Canopy `8e400bbb`, order-tree `ccbcda8`, 2026-07-28

## Why this matters

`order-tree` duplicates `BTree::from_sorted`'s bottom-up construction and then
writes `BTree.root` and `BTree.size` directly. This creates two occupancy and
redistribution algorithms to maintain and forces invariant-bearing B-tree
state to remain externally writable. Keep order-tree's domain-specific
filter/pre-merge transformation, delegate structural construction to the B-tree
package, remove tests that re-test imported B-tree internals, and mark B-tree
state fields private.

## Current state

Owning implementation (`lib/btree/btree.mbt:188-226`):

```moonbit
pub fn[T] BTree::from_sorted(
  items : Array[(T, Int)],
  min_degree? : Int = DEFAULT_MIN_DEGREE,
) -> BTree[T] {
  ...
  { root: Some(root), min_degree, size: items.length() }
}
```

Duplicate consumer implementation (`order-tree/bulk_build.mbt:39-116`) builds
leaf/internal layers manually, then installs them by direct field mutation:

```moonbit
let btree : @btree.BTree[T] = @btree.BTree::new(min_degree=t)
btree.root = Some(root_node)
btree.size = leaf_count
{ tree: btree }
```

The fields are externally writable (`lib/btree/types.mbt:11-15`):

```moonbit
pub(all) struct BTree[T] {
  mut root : BTreeNode[T]?
  min_degree : Int
  mut size : Int
}
```

`order-tree/invariant_wbtest.mbt:50-246` traverses B-tree nodes and cached fields
to test imported B-tree occupancy/count logic. `lib/btree/btree_wbtest.mbt`
already owns extensive structural invariant and property coverage. The
order-tree-specific test at `order-tree/walker_wbtest.mbt:50-78` already checks
public sequence behavior, then additionally inspects root child count; that
last shape assertion belongs to B-tree, not the wrapper.

Existing API First results:

- `BTree::from_sorted` — **reuse**; it already owns O(n) bottom-up grouping,
  root wrapping, degree normalization, and size initialization.
- `Array::map` — **reuse** to map pre-merged elements to `(elem, span)` pairs.
- `@rle.Spanning::span` — **reuse** for pair spans.
- `OrderTree::to_array`, `size`, `span`, `find`, and `view` — **reuse** for
  wrapper-owned black-box tests.
- `Iter::fold` / `ArrayView` — checked but not used for the adjacent pre-merge
  accumulator; its local builder mutation is clear, bounded, and justified.
- No new construction helper is needed.

Applicable repository constraints:

- Each package tests its own logic. Do not keep order-tree tests coupled to
  B-tree occupancy representation.
- B-tree fields become opaque with `priv` fields in a named public struct; do
  not invent public root/inspection escape hatches.
- Submodule changes must be committed and pushed to their own remote before a
  parent pointer update or parent PR.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| State preflight | `git status --short && git -C order-tree status --short && git submodule status order-tree` | no new order-tree dirt; unrelated parent changes preserved |
| API preflight | `NEW_MOON_MOD=0 moon ide peek-def BTree::from_sorted` | signature accepts `Array[(T, Int)]` and optional degree; if IDE segfaults, source excerpt matches |
| Reference fallback | `rg -n --hidden --no-ignore --glob '!**/_build/**' --glob '!**/.mooncakes/**' '\.root|\.size|\.min_degree|BTreeNode' order-tree event-graph-walker` | all direct BTree-state consumers are accounted for |
| Submodule check | `(cd order-tree && moon check --deny-warn)` | exit 0 |
| Submodule tests | `(cd order-tree && moon test --release)` | all tests pass |
| B-tree check | `moon check --deny-warn lib/btree` | exit 0 |
| Workspace tests | `moon test` | all workspace tests pass |
| Interface refresh | `(cd order-tree && NEW_MOON_MOD=0 moon fmt . && NEW_MOON_MOD=0 moon info .) && NEW_MOON_MOD=0 moon fmt lib/btree && NEW_MOON_MOD=0 moon info lib/btree` | exit 0; only affected modules/packages are refreshed |

## Suggested executor toolkit

Use `moonbit-refactoring-safety`, `moonbit-refactoring`,
`moonbit-opaque-types`, and `moonbit-verification` if available. If delegating,
use a MoonBit worker in an isolated worktree and review both the submodule diff
and parent gitlink explicitly.

## Scope

### Phase A — order-tree submodule

**In scope**:

- `order-tree/bulk_build.mbt`
- `order-tree/order_tree_test.mbt` — add only missing public `from_array` characterization cases
- `order-tree/invariant_wbtest.mbt`
- `order-tree/walker_wbtest.mbt`
- `order-tree/pkg.generated.mbti` only if regenerated output changes

### Phase B — Canopy parent

**In scope**:

- `lib/btree/types.mbt`
- `lib/btree/pkg.generated.mbti` as generated output
- parent `order-tree` gitlink, only after the submodule commit is remotely
  reachable

**Out of scope**:

- Making `BTreeNode` private or changing its variants/methods.
- Changing `BTree::from_sorted`'s algorithm.
- Moving order-tree production logic into B-tree.
- Adding public inspection helpers solely to preserve representation-coupled
  tests.
- Editing `event-graph-walker` unless preflight finds a direct BTree-state
  access, in which case STOP.
- Pushing or opening either repository's PR without explicit approval.

## Git workflow

1. Confirm `order-tree` is clean and pinned at or intentionally descended from
   `ccbcda8`.
2. Create submodule branch `advisor/004-reuse-btree-from-sorted`.
3. Commit Phase A in the submodule with
   `refactor: reuse btree bulk construction`.
4. Obtain explicit approval before pushing/opening an order-tree PR.
5. Push the submodule commit before staging a parent gitlink.
6. Create/use parent branch `advisor/004-opaque-btree-state`.
7. Commit Phase B and the reachable gitlink with
   `refactor(btree): hide mutable tree state`.
8. Do not push/open a parent PR unless explicitly instructed.

If approval to push is absent, complete and validate local Phase A, then STOP
before staging a parent pointer; report the submodule commit/patch that must be
published first.

## Steps

### Step 1: Establish clean baselines and references

Run all preflight commands. Retry `moon ide find-references`; planning-time
attempts segfaulted, so source grep is mandatory even if IDE works. Account for
every direct access to BTree fields and BTreeNode under current non-archive
source.

**Verify**: the production direct writes are confined to
`order-tree/bulk_build.mbt`; representation-coupled reads are confined to the
two named order-tree wbtest files. Otherwise STOP.

### Step 2: Add/confirm black-box `from_array` characterization

Before deleting structural checks, ensure `order-tree/order_tree_test.mbt`
contains public-behavior tests for:

- empty input;
- zero/non-positive span filtering;
- adjacent mergeable pre-merge;
- order preservation;
- sizes around degree grouping boundaries (for `min_degree=2`: 4, 5, and a
  multi-level case);
- `size`, `span`, `to_array`, `find`, and `view` agreement.

Prefer extending the existing `order_tree_test.mbt:325-389,590-610` tests only
when a required case is missing. Keep additions black-box and limited to the
public `OrderTree` API.

**Verify**: `(cd order-tree && moon test --release -f '*from_array*')` passes
before migration.

### Step 3: Replace the duplicate builder

In `order-tree/bulk_build.mbt`:

1. Keep the existing degree normalization and domain-specific filtering/
   adjacent pre-merge loop.
2. Remove `using @btree {type BTreeNode}`.
3. Delete manual leaf-layer, child-group redistribution, internal-node, and
   root installation code.
4. Map `merged` to `Array[(T, Int)]` using `Array::map` and
   `@rle.Spanning::span`.
5. Return `{ tree: @btree.BTree::from_sorted(pairs, min_degree=t) }`.
6. Preserve empty behavior; either let `from_sorted([])` handle it or retain an
   early return only if it improves clarity without duplicating construction.

**Verify**:

```bash
(cd order-tree && moon check --deny-warn)
(cd order-tree && moon test --release -f '*from_array*')
```

Both exit 0.

### Step 4: Remove wrong-module structural assertions

In `order-tree/invariant_wbtest.mbt`, remove helpers and tests whose only purpose
is validating B-tree node depth, occupancy, cached counts/totals, root variant,
or internal leaf count. Preserve or replace only OrderTree-owned assertions:

- public sequence/model agreement after insert/delete/from_array;
- wrapper `size`/`span` behavior;
- canonical no-adjacent-mergeable behavior observable via `to_array`.

Use public `OrderTree` APIs, not BTree fields or BTreeNode variants. If equivalent
public-model coverage already exists in `order_tree_test.mbt`, delete duplicate
wbtests rather than reimplementing them.

In `order-tree/walker_wbtest.mbt`, keep the public span/find assertions in
`delete_at collapses root after propagated child removal` and remove the final
root child-count match.

**Verify**:

```bash
! rg -n 'tree\.tree\.(root|size|min_degree)|\bBTreeNode\b|\bLeaf\(|\bInternal\(' order-tree --glob '*.mbt'
(cd order-tree && moon test --release)
```

The grep exits 0 because no matches exist; all order-tree tests pass.

### Step 5: Benchmark the migration

Run order-tree release benchmarks before and after the submodule change in
comparable environments. Record results in the PR description or executor
report, not a source file. Treat noise below the benchmark harness's normal
variance as neutral.

**Verify**: `(cd order-tree && moon bench --release)` exits 0. STOP if bulk
construction materially regresses; report numbers rather than optimizing.

### Step 6: Commit and publish the submodule in the required order

Format and refresh order-tree interfaces, review the diff, then commit locally.
Do not push until approved. After approval, push the feature branch and ensure
the commit is fetchable from the submodule remote before touching the parent
pointer.

**Verify**:

```bash
(cd order-tree && NEW_MOON_MOD=0 moon fmt . && NEW_MOON_MOD=0 moon info .)
git -C order-tree diff --check
git -C order-tree status --short
```

Only intended order-tree files change. After an approved push,
`git -C order-tree branch -r --contains HEAD` reports the remote branch.

### Step 7: Make B-tree state fields private

Only after Phase A tests pass, edit `lib/btree/types.mbt` so the existing
`pub(all) struct BTree[T]` retains its public type and methods but marks these
named fields `priv`:

- `priv mut root`
- `priv min_degree`
- `priv mut size`

Do not change `BTreeNode`, `FindResult`, derives, or public method signatures.
Same-package white-box tests may continue reading private fields.

**Verify**: `moon check --deny-warn lib/btree order-tree` exits 0. Any external
field access means Phase A was incomplete; STOP rather than adding accessors.

### Step 8: Run complete validation and inspect API drift

Run B-tree, order-tree, and full workspace tests. Then regenerate interfaces.
The expected B-tree `.mbti` change is that `BTree` reports private fields while
all existing public methods remain unchanged.

**Verify**:

```bash
moon test --release lib/btree
moon test --release -p dowdiness/order-tree
moon test
NEW_MOON_MOD=0 moon fmt lib/btree
NEW_MOON_MOD=0 moon info lib/btree
git diff -- lib/btree/pkg.generated.mbti order-tree/pkg.generated.mbti
git diff --check
git diff --stat
git status --short
```

All commands pass; no BTree method or trait-bound drift appears.

### Step 9: Update the parent pointer only when safe

Stage the parent `order-tree` gitlink only after its commit is pushed and
fetchable. Confirm the parent diff contains the intended gitlink and B-tree
field-visibility change, not unrelated submodule pointers.

**Verify**:

```bash
git diff --submodule=short -- order-tree
git diff --stat
git status --short
```

`alga`, `event-graph-walker`, and `loom` remain untouched and unstaged.

## Test plan

Order-tree must retain black-box tests for filtering, pre-merge, order, degree
boundaries, and public query agreement. Delete imported B-tree representation
checks only after confirming equivalent B-tree-owned invariant/property tests
remain in `lib/btree/btree_wbtest.mbt` and
`lib/btree/btree_property_wbtest.mbt`.

Validation layers:

1. order-tree `from_array` focused tests;
2. complete order-tree tests and benchmarks;
3. B-tree package tests;
4. root workspace tests after private-field change.

## Done criteria

- [ ] `order-tree/bulk_build.mbt` contains no BTreeNode construction, manual
      grouping, or direct BTree field assignment.
- [ ] Order-tree tests contain no BTree field/variant inspection.
- [ ] OrderTree-owned filtering, merging, ordering, and public query behavior
      remain tested.
- [ ] `BTree.root`, `min_degree`, and `size` are private fields.
- [ ] `BTreeNode` and all public BTree method signatures remain unchanged.
- [ ] Submodule check, test, and benchmark commands pass.
- [ ] B-tree package and full workspace tests pass.
- [ ] The order-tree commit is remotely reachable before the parent gitlink is
      staged or committed.
- [ ] No unrelated submodule pointer is staged.
- [ ] The Plan 004 row in `plans/README.md` is updated.

## STOP conditions

Stop and report if:

- `order-tree` is dirty, detached at an unexpected commit, or contains operator
  work not represented by `ccbcda8`.
- A non-test production consumer besides `bulk_build.mbt` directly accesses
  BTree state or constructs BTreeNode for installation.
- `BTree::from_sorted` changes order-tree's public sequence, merge, size, or
  span behavior.
- A benchmark shows a material bulk-build regression.
- Preserving an order-tree test requires adding a public B-tree inspection
  escape hatch.
- Private BTree fields break `event-graph-walker` or another unplanned package.
- The operator has not approved pushing the submodule; stop before parent
  pointer integration.
- Any required CI gate fails twice after one reasonable correction.

## Maintenance notes

- Future bulk-build policy belongs in `BTree::from_sorted`; order-tree should
  own only filtering and merge canonicalization.
- Reviewers must inspect submodule push order and raw gitlink changes.
- Keeping `BTreeNode` public is deliberate in this plan. A later API-removal
  proposal needs independent evidence about published consumers and versioning.
- Do not reintroduce structural tests in order-tree; package ownership puts
  occupancy/count invariants in lib/btree.
