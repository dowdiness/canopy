# Plan 002: Enforce positive leaf spans at every public construction boundary

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If a
> STOP condition occurs, stop and report — do not improvise. Update this plan's
> row in `plans/README.md` when complete unless a reviewer owns the index.
>
> **Drift check (run first)**:
> `git diff --stat 8e400bbb..HEAD -- lib/btree/btree.mbt lib/btree/walker_propagate.mbt lib/btree/utils.mbt lib/btree/btree_wbtest.mbt lib/btree/pkg.generated.mbti`
> Plan 001 is expected to change `utils.mbt` and the test file. Reconcile those
> changes rather than reverting them. Any unrelated semantic drift is a STOP
> condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/001-bound-btree-min-degree.md`
- **Category**: bug
- **Planned at**: commit `8e400bbb`, 2026-07-28

## Why this matters

The counted tree assumes each leaf contributes a strictly positive amount to
its positional coordinate space. Today, `from_sorted`, `init_root`, and
callback-produced `Splice.new_leaves` accept arbitrary `Int` spans. A zero or
negative span can produce a tree that is structurally non-empty while reporting
zero or negative total span; such leaves are unreachable through `find` and can
make cumulative counts non-monotonic. Reject invalid spans before any tree
array or cached counter is mutated.

## Current state

Raw spans enter through three paths:

`lib/btree/btree.mbt:188-199`:

```moonbit
pub fn[T] BTree::from_sorted(items : Array[(T, Int)], ...) -> BTree[T] {
  ...
  let mut nodes : Array[BTreeNode[T]] = items.map(fn(pair) {
    Leaf(elem=pair.0, span=pair.1)
  })
```

`lib/btree/btree.mbt:229-233`:

```moonbit
pub fn[T] BTree::init_root(self : BTree[T], elem : T, span : Int) -> Unit {
  let leaf = Leaf(elem~, span~)
```

`lib/btree/walker_propagate.mbt:37-55` inserts every callback pair without
validation. The test invariant currently accepts all leaves
(`lib/btree/btree_wbtest.mbt:1395-1402`):

```moonbit
match node {
  Leaf(..) => (true, depth, 1)
```

The direct higher-level consumer already establishes the intended policy:
`order-tree/bulk_build.mbt:19-24` filters elements whose reported span is
`<= 0`, and `order-tree/invariant_wbtest.mbt:110-120` treats a non-positive
leaf span as an invariant violation.

Applicable architecture rules:

- Validation is deterministic functional-core work and must happen before the
  imperative shell mutates tree arrays.
- Existing API First applies. Relevant candidates:
  - `ArrayView::all` / `Iter::all` — use one of these to validate a batch
    declaratively.
  - `@rle.Spanning::span` — checked but not used in the generic B-tree
    boundary, because `BTree[T]` intentionally supports explicit spans for `T`
    without a `BTreeElem` bound.
  - `Result` and typed suberrors — checked but not used in this plan because
    changing all three established public signatures is a larger compatibility
    migration. Match the package's existing invariant-failure behavior
    (`abort` in `mutate_for_insert` and `must_slice`).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| API preflight | `NEW_MOON_MOD=0 moon ide doc 'ArrayView::all' && NEW_MOON_MOD=0 moon ide doc 'Iter::all'` | at least one declarative predicate API is available |
| Targeted check | `moon check --deny-warn lib/btree` | exit 0, no warnings |
| Span tests | `moon test --release lib/btree -f '*non-positive span*'` | all matching panic tests pass |
| Full package tests | `moon test --release lib/btree` | all tests pass; count includes Plan 001 additions |
| Interface refresh | `NEW_MOON_MOD=0 moon fmt lib/btree && NEW_MOON_MOD=0 moon info lib/btree` | exit 0; only the selected package is refreshed |

## Suggested executor toolkit

Use `moonbit-error-handling`, `moonbit-refactoring`, and
`moonbit-verification` if available. Before introducing a private validation
helper, run the API preflight and prefer `ArrayView::all`/`Iter::all` over a
manual index loop.

## Scope

**In scope**:

- `lib/btree/utils.mbt` — one private positive-span validation boundary
- `lib/btree/btree.mbt` — validate `from_sorted` and `init_root`
- `lib/btree/walker_propagate.mbt` — validate callback-produced new leaves
  before mutation
- `lib/btree/btree_wbtest.mbt` — regression and invariant tests
- `lib/btree/pkg.generated.mbti` — generated inspection only

**Out of scope**:

- Changing public methods to return `Result` or raise typed errors.
- Comparing explicit spans with `@rle.Spanning::span(elem)`; generic B-tree
  operations intentionally do not require `BTreeElem`.
- Total-span addition overflow.
- Validating splice index ranges; Plan 005 documents that existing caller
  contract, but a future API-hardening plan may enforce it.
- Automatically filtering invalid input in `BTree`; silent filtering would make
  callback leaf deltas and caller payloads ambiguous.
- Any `order-tree` change.

## Git workflow

- Branch: `advisor/002-enforce-positive-btree-spans`
- Suggested commit: `fix(btree): reject non-positive leaf spans`
- Do not push or open a PR without explicit operator instruction.
- Preserve unrelated modified submodules and Plan 001 changes.

## Steps

### Step 1: Add red tests for every entry path

In `lib/btree/btree_wbtest.mbt`, add named panic tests following the existing
`test "panic insert on empty tree aborts"` pattern. Cover:

1. `BTree::from_sorted` with span `0`.
2. `BTree::from_sorted` with span `-1`.
3. `BTree::init_root` with span `0`.
4. `BTree::init_root` with span `-1`.
5. `mutate_for_insert` returning a splice containing a zero-span new leaf.
6. `mutate_for_delete` returning a replacement splice containing a
   negative-span new leaf.

Also change the white-box invariant checker so `Leaf(span~, ..)` returns false
when `span <= 0`. This assertion is test-only and must not become a second
production validator.

Use operation-specific expected abort messages:

- `BTree::from_sorted: leaf spans must be positive`
- `BTree::init_root: leaf span must be positive`
- `BTree splice: leaf spans must be positive`

**Verify**: before production changes,
`moon test --release lib/btree -f '*non-positive span*'` must fail because the
invalid operations currently return. If all new tests pass before the fix,
STOP and report.

### Step 2: Add one private batch validator

In `lib/btree/utils.mbt`, add a private function whose sole responsibility is:
accept an `Array[(T, Int)]` and an operation label, confirm every `.1 > 0`, and
abort with the operation-specific message otherwise.

Implementation constraints:

- Use `ArrayView::all`, `Iter::all`, or an equivalent declarative core API.
- Do not mutate the input.
- Do not compare the supplied integer with the element's `Spanning::span`.
- Do not introduce a public error type or widen a public trait bound.

A single-span check in `init_root` may remain an inline `guard`; do not force a
one-element array allocation merely to reuse the batch helper.

**Verify**: `moon check --deny-warn lib/btree` exits 0.

### Step 3: Validate before allocation or mutation

Wire validation into these exact boundaries:

1. `BTree::from_sorted`: validate the full `items` array before mapping it to
   leaves. Empty input remains valid.
2. `BTree::init_root`: guard `span > 0` before assigning `self.root` or
   `self.size`.
3. `propagate`: validate `splice.new_leaves` before `apply_splice` mutates the
   leaf parent's `children` and `counts` arrays.

`mutate_for_insert` and `mutate_for_delete` both route through `propagate`, so
do not duplicate validation in both public methods.

**Verify**:

```bash
moon check --deny-warn lib/btree
moon test --release lib/btree -f '*non-positive span*'
```

Both exit 0.

### Step 4: Confirm failures are atomic

For the splice panic tests, capture the tree's `size`, `span`, and `to_array`
before invoking the invalid callback where the test harness permits observing
a caught failure. If MoonBit's uncatchable `abort` prevents post-failure
inspection, verify by source ordering that validation occurs before
`apply_splice`, and add a comment in the test explaining why post-abort state
cannot be asserted.

Do not change `abort` to `fail` solely to make this test catchable.

**Verify**: `rg -n 'validate.*span|apply_splice' lib/btree/walker_propagate.mbt`
shows validation textually before `apply_splice` in `propagate`.

### Step 5: Run full validation and inspect the interface

Run package tests, format, and interface generation. The helper is private and
public signatures must remain unchanged.

**Verify**:

```bash
moon test --release lib/btree
NEW_MOON_MOD=0 moon fmt lib/btree
NEW_MOON_MOD=0 moon info lib/btree
git diff --check
git diff -- lib/btree/pkg.generated.mbti
git status --short
```

Expected: all tests pass; no public signature drift; only in-scope files plus
known pre-existing changes appear.

## Test plan

Add six named panic regressions in `lib/btree/btree_wbtest.mbt` and strengthen
`check_node_invariants` for leaf positivity. Keep property generators positive;
they model valid trees and should not be widened to generate invalid values
that merely abort.

Use these existing patterns:

- Panic test: `lib/btree/btree_wbtest.mbt:214-218`.
- Constructor tests: `lib/btree/btree_wbtest.mbt:2123-2263`.
- Invariant checker: `lib/btree/btree_wbtest.mbt:1388-1458`.

## Done criteria

- [ ] All leaf-producing public paths reject spans `<= 0` before mutation.
- [ ] Empty `from_sorted([])` remains valid.
- [ ] Six non-positive-span tests exist and pass.
- [ ] The white-box invariant checker rejects non-positive leaves.
- [ ] `moon check --deny-warn lib/btree` exits 0.
- [ ] `moon test --release lib/btree` exits 0.
- [ ] `pkg.generated.mbti` has no unintended signature or trait-bound changes.
- [ ] No out-of-scope files are modified.
- [ ] The Plan 002 row in `plans/README.md` is updated.

## STOP conditions

Stop and report if:

- Existing in-repo production code intentionally inserts zero-span B-tree
  leaves.
- A valid existing package test begins failing because it relies on a
  non-positive span.
- Enforcing positivity requires adding `BTreeElem` to generic constructor or
  mutation signatures.
- The only available implementation requires mutating before validation.
- Public `.mbti` signatures change unexpectedly.
- A step fails twice after one reasonable correction.

## Maintenance notes

- Any future leaf-construction path must call the same positive-span validator
  before touching arrays or cached totals.
- Reviewers should reject implementations that silently drop bad callback
  leaves: doing so would desynchronize `leaf_delta` from caller intent.
- Typed recoverable constructor errors may be a future major-version API
  design; this plan deliberately preserves signatures and treats invalid
  low-level spans as invariant violations.
