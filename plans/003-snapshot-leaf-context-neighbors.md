# Plan 003: Make `LeafContext` a mutation-free snapshot

> **Executor instructions**: Follow this plan step by step and run every
> verification gate. Stop on any condition listed below; do not broaden the
> public API or improvise compatibility shims. Update the Plan 003 status in
> `plans/README.md` when complete unless a reviewer owns the index.
>
> **Drift check (run first)**:
> `git diff --stat 8e400bbb..HEAD -- lib/btree/walker_types.mbt lib/btree/btree.mbt lib/btree/walker_propagate.mbt lib/btree/btree_wbtest.mbt lib/btree/pkg.generated.mbti order-tree/walker_insert.mbt order-tree/walker_delete.mbt`
> Plans 001–002 may have changed B-tree tests and propagation. Reconcile those
> expected changes. Any change to `LeafContext` itself is a STOP condition until
> compared with this plan.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/002-enforce-positive-btree-spans.md`
- **Category**: tech-debt
- **Planned at**: commit `8e400bbb`, 2026-07-28

## Why this matters

The source calls `LeafContext` read-only, but it currently exposes the live
mutable `children` array from a B-tree path frame. A callback can mutate or
retain that array before propagation updates its parallel `counts` array,
violating the tree's cached-count and size invariants. Replace the live array
with captured left/right neighbor values while preserving the callback-facing
fields and `left_neighbor`/`right_neighbor` methods used by `order-tree`.

## Current state

`lib/btree/walker_types.mbt:55-68`:

```moonbit
/// Read-only context passed to pure leaf splice computations.
pub(all) struct LeafContext[T] {
  elem : T
  span : Int
  offset : Int
  children : Array[BTreeNode[T]]
  child_idx : Int
}
```

`LeafContext::from_cursor` stores the parent frame's actual array
(`lib/btree/walker_types.mbt:97-109`):

```moonbit
let frame = cursor.path[cursor.path.length() - 1]
{
  ...
  children: frame.children,
  child_idx: cursor.child_idx,
}
```

The public callbacks receive that object at `lib/btree/btree.mbt:67-72` and
`:101-107`; propagation later mutates the same parent arrays in
`lib/btree/walker_propagate.mbt:37-55`.

Direct consumer evidence:

- `order-tree/walker_insert.mbt:2-109` reads `ctx.elem`, `ctx.span`,
  `ctx.offset`, `ctx.child_idx`, and the two neighbor methods.
- `order-tree/walker_delete.mbt:2-111` uses the same surface.
- No current production consumer reads `ctx.children` directly; confirm this
  again before editing.

Applicable design rule: do not expose internal mutable collections from a
validated core result. A callback snapshot is the functional core; tree-array
mutation remains in propagation's imperative shell.

Existing API candidates:

- `Array::get` — reuse for optional index-safe neighbor extraction if available
  under the pinned toolchain.
- Pattern matching on `BTreeNode` — reuse to return only leaf elements and keep
  internal nodes invisible to callback code.
- `Array::copy` / `ArrayView` — checked but rejected. A copied array adds O(b)
  allocation per operation, while a view still aliases the mutable array and
  exposes `BTreeNode` values containing nested mutable arrays.
- `Option` — reuse for captured absent/present neighbors.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| API/reference preflight | `NEW_MOON_MOD=0 moon ide doc 'Array::get'; NEW_MOON_MOD=0 moon ide find-references LeafContext` | `Array::get` is available; references are listed, or IDE failure is recorded and grep fallback used |
| Grep fallback | `rg -n --hidden --no-ignore --glob '!**/_build/**' --glob '!**/.mooncakes/**' 'LeafContext|\.children' lib/btree order-tree event-graph-walker` | no production `ctx.children` consumer outside `lib/btree` |
| B-tree tests | `moon test --release lib/btree` | all pass |
| Downstream tests | `moon test --release -p dowdiness/order-tree` | all order-tree tests pass |
| Strict check | `moon check --deny-warn lib/btree order-tree` | exit 0, no owned-source warnings |
| Interface refresh | `NEW_MOON_MOD=0 moon fmt lib/btree && NEW_MOON_MOD=0 moon info lib/btree` | exit 0; only the selected package is refreshed |

`moon ide find-references` was observed segfaulting at planning time. A repeated
segfault is not permission to skip the search: record it and use the exact grep
fallback.

## Suggested executor toolkit

Use `moonbit-refactoring`, `moonbit-verification`, and the opaque-types guidance
if available. The target pattern is `pub(all) struct` with private snapshot
fields, not a defensive copy of the live tree.

## Scope

**In scope**:

- `lib/btree/walker_types.mbt`
- `lib/btree/btree_wbtest.mbt`
- `lib/btree/pkg.generated.mbti` as generated output

**Read/validate but do not modify unless a compile error proves necessary**:

- `order-tree/walker_insert.mbt`
- `order-tree/walker_delete.mbt`
- `order-tree/pkg.generated.mbti`

**Out of scope**:

- Changing `Splice` fields or callback signatures.
- Making the entire `BTree` opaque; Plan 004 addresses tree state.
- Deep-copying elements of generic type `T`.
- Iterator invalidation behavior.
- Rewriting order-tree insertion/deletion algorithms.
- Any submodule commit or pointer update.

## Git workflow

- Branch: `advisor/003-snapshot-leaf-context-neighbors`
- Suggested commit: `refactor(btree): snapshot leaf context neighbors`
- Do not push or open a PR without explicit operator instruction.
- Do not stage unrelated modified submodules.

## Steps

### Step 1: Confirm the callback surface and add a red alias test

Run the IDE/grep preflight. STOP if any production consumer reads
`LeafContext.children`; that requires a separate compatibility design.

In `lib/btree/btree_wbtest.mbt`, add a white-box test modeled after
`LeafContext neighbors return adjacent siblings` at lines 808–824. The new test
must:

1. Build a parent containing at least three leaves.
2. Descend to the middle leaf and construct a context.
3. Mutate the original parent `children` array to replace one adjacent leaf.
4. Assert the already-created context still returns the original neighbor.

This test expresses snapshot semantics. It should fail or be impossible to
write against the current `children`-derived methods.

**Verify**: `moon test --release lib/btree -f '*LeafContext snapshot*'` fails
before the implementation. If it passes without changing production code,
STOP and inspect whether the test accidentally copied the array.

### Step 2: Replace the live array with captured neighbors

In `lib/btree/walker_types.mbt`:

1. Remove `children : Array[BTreeNode[T]]` from `LeafContext`.
2. Add two private immutable fields, for example `priv left_elem : T?` and
   `priv right_elem : T?`.
3. Keep `elem`, `span`, `offset`, and `child_idx` readable with their current
   names so current callbacks remain source-compatible.
4. Update `LeafContext::left_neighbor` and `right_neighbor` to return the
   captured options directly.
5. Update `LeafContext::from_cursor` to inspect `frame.children` once and
   capture only adjacent leaf elements. Preserve current behavior: a missing
   index or adjacent internal node yields `None`.

Do not store an `Array`, `ArrayView`, `BTreeNode`, cursor, or path frame in the
public context. Do not add mutation methods.

**Verify**: `moon check --deny-warn lib/btree` exits 0.

### Step 3: Run focused B-tree tests

Run all LeafContext tests, including the new snapshot test and existing
boundary tests.

**Verify**:

```bash
moon test --release lib/btree -f '*LeafContext*'
```

All matching tests pass.

### Step 4: Validate the direct consumer

Compile and test the workspace's `dowdiness/order-tree` package without
modifying it. Its callbacks must continue to read the four existing fields and
neighbor methods unchanged.

**Verify**:

```bash
moon test --release -p dowdiness/order-tree
moon check --deny-warn lib/btree order-tree
```

Both exit 0. If source changes in `order-tree` are required, STOP: this plan's
compatibility assumption was false.

### Step 5: Refresh and review the public interface

Run format and interface generation. The intended `.mbti` change is narrowly:

- `LeafContext.children` disappears.
- Captured neighbor fields appear as private implementation fields or are
  omitted according to generator behavior.
- `elem`, `span`, `offset`, `child_idx`, and both neighbor methods remain.
- No BTree/BTreeNode/Splice signature changes.

**Verify**:

```bash
NEW_MOON_MOD=0 moon fmt lib/btree
NEW_MOON_MOD=0 moon info lib/btree
git diff -- lib/btree/pkg.generated.mbti
git diff --check
git status --short
```

A reviewer must explicitly approve this breaking field removal before release;
the method-level callback surface remains compatible.

## Test plan

Add one white-box regression proving a context's captured neighbor does not
change when the source parent array changes. Keep and run the existing tests:

- `LeafContext::from_cursor extracts leaf info`
- `LeafContext neighbors return adjacent siblings`
- `LeafContext boundary neighbors are None`

Then run all B-tree tests and all order-tree tests to cover real callback use.

## Done criteria

- [ ] `LeafContext` stores no `Array`, `ArrayView`, `BTreeNode`, cursor, or path
      reference.
- [ ] Existing callback fields and neighbor methods remain source-compatible.
- [ ] The snapshot regression and all existing LeafContext tests pass.
- [ ] `moon test --release lib/btree` passes.
- [ ] `moon test --release -p dowdiness/order-tree` passes without order-tree
      source edits.
- [ ] `.mbti` drift is limited to removing the unsafe field and hiding captured
      neighbor storage.
- [ ] No out-of-scope file is modified.
- [ ] The Plan 003 row in `plans/README.md` is updated.

## STOP conditions

Stop and report if:

- Any current production consumer reads `ctx.children`.
- MoonBit does not allow private fields alongside the required readable fields
  in this public struct under the pinned toolchain.
- Preserving callbacks requires copying the entire children array.
- Order-tree compilation requires source changes.
- The new snapshot test does not fail before implementation.
- Interface generation removes or changes any field/method other than the
  planned `children` removal and private storage.
- A verification command fails twice after one reasonable correction.

## Maintenance notes

- Future callback context additions should expose values or immutable summaries,
  never live arrays from path frames.
- This plan does not deep-copy `T`; callers remain responsible for their
  element type's own mutation semantics.
- Reviewers should inspect the `.mbti` diff carefully because field removal is
  a public compatibility change even though no in-repo caller uses it.
