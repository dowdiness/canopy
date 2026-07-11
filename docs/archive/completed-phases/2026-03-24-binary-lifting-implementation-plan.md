**Status:** Complete

# Binary Lifting (Jump Pointers) for Incremental LCA — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Euler Tour + Sparse Table LCA index with incremental binary lifting jump pointers, eliminating O(n log n) rebuild per mutation.

**Architecture:** `JumpAncestors` struct with two arrays (depth + jump pointers) lives in `jump_ancestors.mbt` alongside FugueTree. Each insert computes O(log depth) permanent jump pointers. `FugueTree::is_ancestor()` delegates to binary lifting. The `LcaIndex`, `batch_inserting` mode, and naive fallback are all removed.

**Tech Stack:** MoonBit, moon test, moon bench --release

**Spec:** `docs/plans/2026-03-24-incremental-lca-binary-lifting.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `internal/fugue/jump_ancestors.mbt` | **Create** | `JumpAncestors` struct, `new()`, `add()`, `is_ancestor()` |
| `internal/fugue/jump_ancestors_wbtest.mbt` | **Create** | Whitebox unit tests for JumpAncestors internals |
| `internal/fugue/tree.mbt` | **Modify** | Replace `lca_index`/`batch_inserting` fields with `jump_ancestors`, simplify `is_ancestor()`, update `add_item()` and constructors |
| `internal/fugue/lca_index.mbt` | **Delete** | Remove entire file (~150 lines) |
| `internal/fugue/tree_test.mbt` | **Modify** | Remove `build_lca_index()` calls, update test names |
| `internal/fugue/tree_properties_test.mbt` | **Modify** | Remove `build_lca_index()` call, add branching property test |
| `internal/branch/branch.mbt` | **Modify** | Remove `set_batch_inserting()` calls (lines 67,71,116,120) |
| `internal/branch/branch_merge.mbt` | **Modify** | Remove `set_batch_inserting()` calls (lines 34,122) |
| `internal/document/document.mbt` | **Modify** | Remove `set_batch_inserting()` calls (lines 431,503) |
| `internal/fugue/jump_ancestors_benchmark.mbt` | **Create** | Before/after benchmarks for is_ancestor performance |

---

### Task 1: Capture baseline benchmarks

**Files:**
- Read: `internal/branch/branch_benchmark.mbt`

Capture current performance before any changes, so we have a comparison baseline.

- [ ] **Step 1: Run existing benchmarks and record output**

Run from the event-graph-walker directory:
```bash
cd event-graph-walker && moon bench --release -p dowdiness/eg-walker/internal/branch 2>&1 | tee /tmp/lca-baseline.txt
```

- [ ] **Step 2: Commit baseline note (no code changes)**

No commit needed — baseline is saved to `/tmp/lca-baseline.txt` for later comparison.

---

### Task 2: Implement JumpAncestors with TDD

**Files:**
- Create: `internal/fugue/jump_ancestors.mbt`
- Create: `internal/fugue/jump_ancestors_wbtest.mbt`

- [ ] **Step 1: Write failing test — root children have depth 1**

In `internal/fugue/jump_ancestors_wbtest.mbt`:

```moonbit
///|
test "jump: root children have depth 1" {
  let ja = JumpAncestors::new()
  ja.add(Lv(0), root_lv)
  inspect(ja.depth[0], content="1")
  inspect(ja.jump[0].length(), content="1")
  inspect(ja.jump[0][0], content="Lv(-1)")
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd event-graph-walker && moon test -p dowdiness/eg-walker/internal/fugue -f jump_ancestors_wbtest.mbt
```
Expected: FAIL — `JumpAncestors` not defined.

- [ ] **Step 3: Write minimal JumpAncestors implementation**

In `internal/fugue/jump_ancestors.mbt`:

```moonbit
///| Binary lifting (jump pointers) for O(log n) incremental ancestor queries.
///  Exploits FugueTree's append-only structure: jump pointers are permanent.

///|
struct JumpAncestors {
  depth : Array[Int]        // depth[lv.0], -1 = gap (non-tree LV)
  jump : Array[Array[Lv]]  // jump[lv.0][k] = 2^k-th ancestor, [] = gap
}

///|
fn JumpAncestors::new() -> JumpAncestors {
  { depth: [], jump: [] }
}

///|
/// Register a new tree node with its parent. O(log depth).
/// Precondition: parent was already added (or is root_lv).
fn JumpAncestors::add(self : JumpAncestors, lv : Lv, parent : Lv) -> Unit {
  let idx = lv.0
  // Grow arrays with sentinel padding for gap LVs
  while self.depth.length() <= idx {
    self.depth.push(-1)
  }
  while self.jump.length() <= idx {
    self.jump.push([])
  }
  // Assert precondition: parent already added (or is root)
  guard parent == root_lv || self.depth[parent.0] != -1
  // Compute depth
  self.depth[idx] = if parent == root_lv {
    1
  } else {
    self.depth[parent.0] + 1
  }
  // Build jump pointers: jump[0] = parent, jump[k] = 2^k-th ancestor
  let jumps : Array[Lv] = [parent]
  while true {
    let k = jumps.length()
    let prev = jumps[k - 1]
    if prev == root_lv {
      break
    }
    if k - 1 >= self.jump[prev.0].length() {
      break
    }
    jumps.push(self.jump[prev.0][k - 1])
  }
  self.jump[idx] = jumps
}

///|
/// Check if `ancestor` is an ancestor of `descendant`. O(log depth).
/// Both must be non-root tree nodes. Caller handles root_lv and equality.
/// Returns false for absent or gap LVs.
fn JumpAncestors::is_ancestor(
  self : JumpAncestors,
  ancestor : Lv,
  descendant : Lv,
) -> Bool {
  let a = ancestor.0
  let b = descendant.0
  // Bounds + gap checks
  if a >= self.depth.length() || self.depth[a] == -1 {
    return false
  }
  if b >= self.depth.length() || self.depth[b] == -1 {
    return false
  }
  let depth_a = self.depth[a]
  let depth_b = self.depth[b]
  if depth_a > depth_b {
    return false
  }
  // Lift descendant to ancestor's depth
  let mut diff = depth_b - depth_a
  let mut current = descendant
  let mut k = self.jump[current.0].length() - 1
  while diff > 0 && k >= 0 {
    if diff >= (1 << k) && k < self.jump[current.0].length() {
      current = self.jump[current.0][k]
      diff = diff - (1 << k)
    }
    k = k - 1
  }
  current == ancestor
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd event-graph-walker && moon test -p dowdiness/eg-walker/internal/fugue -f jump_ancestors_wbtest.mbt
```
Expected: PASS

- [ ] **Step 5: Write test — deep chain ancestry**

Append to `internal/fugue/jump_ancestors_wbtest.mbt`:

```moonbit
///|
test "jump: deep chain — all ancestor pairs" {
  let ja = JumpAncestors::new()
  // Build chain: root → 0 → 1 → 2 → ... → 9
  ja.add(Lv(0), root_lv)
  for i = 1; i < 10; i = i + 1 {
    ja.add(Lv(i), Lv(i - 1))
  }
  // Every earlier node is ancestor of every later node
  for a = 0; a < 10; a = a + 1 {
    for b = a; b < 10; b = b + 1 {
      assert_true(ja.is_ancestor(Lv(a), Lv(b)))
    }
  }
  // Non-ancestor: later node is NOT ancestor of earlier
  assert_false(ja.is_ancestor(Lv(5), Lv(2)))
  assert_false(ja.is_ancestor(Lv(9), Lv(0)))
}
```

- [ ] **Step 6: Run test to verify it passes**

```bash
cd event-graph-walker && moon test -p dowdiness/eg-walker/internal/fugue -f jump_ancestors_wbtest.mbt
```
Expected: PASS

- [ ] **Step 7: Write test — branching tree**

Append to `internal/fugue/jump_ancestors_wbtest.mbt`:

```moonbit
///|
test "jump: branching tree — cross-branch is not ancestor" {
  let ja = JumpAncestors::new()
  // root → 0, root → 1, 0 → 2, 0 → 3, 1 → 4
  ja.add(Lv(0), root_lv)
  ja.add(Lv(1), root_lv)
  ja.add(Lv(2), Lv(0))
  ja.add(Lv(3), Lv(0))
  ja.add(Lv(4), Lv(1))
  // Same branch
  assert_true(ja.is_ancestor(Lv(0), Lv(2)))
  assert_true(ja.is_ancestor(Lv(0), Lv(3)))
  assert_true(ja.is_ancestor(Lv(1), Lv(4)))
  // Cross-branch: not ancestor
  assert_false(ja.is_ancestor(Lv(0), Lv(4)))
  assert_false(ja.is_ancestor(Lv(1), Lv(2)))
  assert_false(ja.is_ancestor(Lv(2), Lv(3)))
  assert_false(ja.is_ancestor(Lv(3), Lv(2)))
}
```

- [ ] **Step 8: Write test — sparse LVs (gaps)**

```moonbit
///|
test "jump: sparse LVs — gaps from non-insert ops" {
  let ja = JumpAncestors::new()
  // Items at LV 0, 2, 5 (gaps at 1, 3, 4 simulate delete/undelete ops)
  ja.add(Lv(0), root_lv)
  ja.add(Lv(2), Lv(0))
  ja.add(Lv(5), Lv(2))
  // Ancestry works across gaps
  assert_true(ja.is_ancestor(Lv(0), Lv(5)))
  assert_true(ja.is_ancestor(Lv(2), Lv(5)))
  // Gap LVs return false
  assert_false(ja.is_ancestor(Lv(1), Lv(5)))
  assert_false(ja.is_ancestor(Lv(0), Lv(1)))
  assert_false(ja.is_ancestor(Lv(3), Lv(5)))
}
```

- [ ] **Step 9: Write test — wide tree (siblings are not ancestors)**

```moonbit
///|
test "jump: wide tree — siblings are not ancestors" {
  let ja = JumpAncestors::new()
  // root → 0, root → 1, ..., root → 9
  for i = 0; i < 10; i = i + 1 {
    ja.add(Lv(i), root_lv)
  }
  // All are at depth 1
  for i = 0; i < 10; i = i + 1 {
    inspect(ja.depth[i], content="1")
  }
  // No sibling is ancestor of another
  for i = 0; i < 10; i = i + 1 {
    for j = 0; j < 10; j = j + 1 {
      if i != j {
        assert_false(ja.is_ancestor(Lv(i), Lv(j)))
      }
    }
  }
}
```

- [ ] **Step 10: Write test — absent/out-of-bounds LVs**

```moonbit
///|
test "jump: absent LV returns false" {
  let ja = JumpAncestors::new()
  ja.add(Lv(0), root_lv)
  assert_false(ja.is_ancestor(Lv(999), Lv(0)))
  assert_false(ja.is_ancestor(Lv(0), Lv(999)))
  assert_false(ja.is_ancestor(Lv(999), Lv(888)))
}
```

- [ ] **Step 11: Run all JumpAncestors tests**

```bash
cd event-graph-walker && moon test -p dowdiness/eg-walker/internal/fugue -f jump_ancestors_wbtest.mbt
```
Expected: All PASS

- [ ] **Step 12: Commit**

```bash
cd event-graph-walker && git add internal/fugue/jump_ancestors.mbt internal/fugue/jump_ancestors_wbtest.mbt && git commit -m "feat(fugue): add JumpAncestors — binary lifting for O(log n) ancestor queries"
```

---

### Task 3: Wire JumpAncestors into FugueTree

**Files:**
- Modify: `internal/fugue/tree.mbt:7-15` (struct fields)
- Modify: `internal/fugue/tree.mbt:37-47` (constructors)
- Modify: `internal/fugue/tree.mbt:356-376` (add_item)
- Modify: `internal/fugue/tree.mbt:441-462` (is_ancestor)

- [ ] **Step 1: Replace `lca_index` and `batch_inserting` fields with `jump_ancestors`**

In `internal/fugue/tree.mbt`, change the FugueTree struct (lines 7-15):

Replace:
```moonbit
  mut lca_index : LcaIndex? // Euler Tour + Sparse Table for O(1) ancestor queries
  mut batch_inserting : Bool // True during batch operations (use naive walk instead of LCA)
```
With:
```moonbit
  jump_ancestors : JumpAncestors // Binary lifting for O(log n) ancestor queries
```

- [ ] **Step 2: Update constructors**

In `FugueTree::make()` (line 37-47), replace:
```moonbit
    lca_index: None,
    batch_inserting: false,
```
With:
```moonbit
    jump_ancestors: JumpAncestors::new(),
```

- [ ] **Step 3: Update `add_item()` — replace invalidation with incremental add**

In `add_item()` (line 374-375), replace:
```moonbit
  // Invalidate LCA index — tree structure has changed
  self.lca_index = None
```
With:
```moonbit
  // Register jump pointers for the new item (O(log depth), permanent)
  match item.parent {
    Some(p) => self.jump_ancestors.add(item.id, p)
    None => () // No parent — skip jump pointer setup
  }
```

- [ ] **Step 4: Simplify `is_ancestor()`**

Replace the entire body of `FugueTree::is_ancestor()` (lines 441-462) with:

```moonbit
///|
/// Check whether `ancestor_id` is an ancestor of `descendant_id`.
/// Uses binary lifting jump pointers for O(log depth) queries.
pub fn[T] FugueTree::is_ancestor(
  self : FugueTree[T],
  ancestor_id : Lv,
  descendant_id : Lv,
) -> Bool {
  if ancestor_id == descendant_id {
    return true
  }
  if ancestor_id == root_lv {
    return true
  }
  if descendant_id == root_lv {
    return false
  }
  self.jump_ancestors.is_ancestor(ancestor_id, descendant_id)
}
```

- [ ] **Step 5: Remove `build_lca_index()`, `set_batch_inserting()` methods**

Delete `build_lca_index()` (lines 393-397) and `set_batch_inserting()` (lines 399-411) from `tree.mbt`.

Keep `is_ancestor_naive()` (lines 413-436) in `tree.mbt` for now — it will be moved to the test file in Task 4. This avoids staging test files in this commit.

- [ ] **Step 6: Run fugue package tests**

```bash
cd event-graph-walker && moon test -p dowdiness/eg-walker/internal/fugue
```
Expected: Compilation errors from test files still calling `build_lca_index()`.

- [ ] **Step 7: Commit**

```bash
cd event-graph-walker && git add internal/fugue/tree.mbt && git commit -m "feat(fugue): wire JumpAncestors into FugueTree, replace LCA index"
```

---

### Task 4: Update tests — remove old LCA calls

**Files:**
- Modify: `internal/fugue/tree_test.mbt:490,571`
- Modify: `internal/fugue/tree_properties_test.mbt:219-255`

- [ ] **Step 1: Remove `build_lca_index()` from tree_test.mbt**

At line 490: remove `tree.build_lca_index()` — the test "LCA: missing node returns false" should still pass because `is_ancestor` now delegates directly to jump pointers (which were set up by `insert()`).

At line 571: remove `tree.build_lca_index()` — the test "LCA: not invalidated by delete/undelete" verifies that ancestry survives delete/undelete. With binary lifting, jump pointers are permanent, so this test passes without any explicit build step.

- [ ] **Step 2: Update property test — remove `build_lca_index()` call**

In `tree_properties_test.mbt`, line 239: remove `tree.build_lca_index()`.

Replace `prop_lca_matches_naive` with a version that uses a local `is_ancestor_naive` helper (since the public method was removed from FugueTree). Or keep calling `is_ancestor_naive` if it's still accessible in the whitebox test.

If `is_ancestor_naive` was moved to test file, paste it into `tree_properties_test.mbt` as a local helper:

```moonbit
///|
/// Naive parent-walk ancestor check (test-only reference).
fn is_ancestor_naive[T](
  tree : @fugue.FugueTree[T],
  ancestor_id : @fugue.Lv,
  descendant_id : @fugue.Lv,
) -> Bool {
  if ancestor_id == descendant_id {
    return true
  }
  if ancestor_id == @fugue.root_lv {
    return true
  }
  loop tree[descendant_id] {
    Some(item) =>
      match item.parent {
        Some(parent_lv) => {
          if parent_lv == ancestor_id {
            return true
          }
          continue tree[parent_lv]
        }
        None => break false
      }
    None => break false
  }
}
```

- [ ] **Step 3: Run all fugue tests**

```bash
cd event-graph-walker && moon test -p dowdiness/eg-walker/internal/fugue
```
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
cd event-graph-walker && git add internal/fugue/tree_test.mbt internal/fugue/tree_properties_test.mbt && git commit -m "test(fugue): update tests for binary lifting — remove build_lca_index calls"
```

---

### Task 5: Remove batch_inserting call sites

**Files:**
- Modify: `internal/branch/branch.mbt:67,71,116,120`
- Modify: `internal/branch/branch_merge.mbt:34,122`
- Modify: `internal/document/document.mbt:431,503`

- [ ] **Step 1: Remove from branch.mbt**

In `Branch::checkout()` (line 67): delete `tree.set_batch_inserting(true)`
In `Branch::checkout()` (line 71): delete `tree.set_batch_inserting(false)`

In `Branch::advance()` (line 116): delete `tree.set_batch_inserting(true)`
In `Branch::advance()` (line 120): delete `tree.set_batch_inserting(false)`

- [ ] **Step 2: Remove from branch_merge.mbt**

In `MergeContext::apply_operations()` (line 34): delete `self.tree.set_batch_inserting(true)`
In `MergeContext::apply_operations()` (line 122): delete `self.tree.set_batch_inserting(false)`

- [ ] **Step 3: Remove from document.mbt**

In `Document::apply_remote()` (line 431): delete `self.tree.set_batch_inserting(true)`
In `Document::apply_remote()` (line 503): delete `self.tree.set_batch_inserting(false)`

- [ ] **Step 4: Run all event-graph-walker tests**

```bash
cd event-graph-walker && moon test
```
Expected: All PASS — no code references `set_batch_inserting` anymore.

- [ ] **Step 5: Commit**

```bash
cd event-graph-walker && git add internal/branch/branch.mbt internal/branch/branch_merge.mbt internal/document/document.mbt && git commit -m "refactor: remove batch_inserting mode — binary lifting is always O(log n)"
```

---

### Task 6: Delete lca_index.mbt

**Files:**
- Delete: `internal/fugue/lca_index.mbt`

- [ ] **Step 1: Delete the file**

```bash
cd event-graph-walker && rm internal/fugue/lca_index.mbt
```

- [ ] **Step 2: Run all tests to verify no remaining references**

```bash
cd event-graph-walker && moon test
```
Expected: All PASS — `LcaIndex` is no longer referenced anywhere.

- [ ] **Step 3: Update interfaces**

```bash
cd event-graph-walker && moon info && moon fmt
```

- [ ] **Step 4: Verify `.mbti` changes look correct**

```bash
cd event-graph-walker && git diff internal/fugue/pkg.generated.mbti
```

Expect: `LcaIndex` struct removed, `build_lca_index` removed, `set_batch_inserting` removed, `batch_inserting` field removed. `JumpAncestors` may or may not appear (it's `priv`).

- [ ] **Step 5: Commit**

```bash
cd event-graph-walker && git add -A internal/fugue/ && git commit -m "chore(fugue): delete lca_index.mbt — replaced by jump_ancestors.mbt"
```

---

### Task 7: Add property tests for binary lifting

**Files:**
- Modify: `internal/fugue/tree_properties_test.mbt`

- [ ] **Step 1: Add branching-tree property test**

Append to `tree_properties_test.mbt`:

```moonbit
///|
/// Random tree generator: each new node picks a random existing node as parent.
struct BranchingTree {
  len : Int
} derive(Show)

///|
pub impl @qc.Arbitrary for BranchingTree with arbitrary(size, rs) {
  let len = if size < 3 { 3 } else if size > 50 { 50 } else { size }
  { len: rs.next_positive_int() % len + 3 }
}

///|
/// Property: binary lifting agrees with naive walk on random branching trees.
fn prop_jump_matches_naive_branching(bt : BranchingTree) -> Bool {
  let tree : @fugue.FugueTree[String] = @fugue.FugueTree::new()
  let parents : Array[Int] = []
  // First item: parent is root
  tree.insert({
    id: @fugue.Lv(0),
    content: "A",
    origin_left: None,
    origin_right: None,
    timestamp: @fugue.Timestamp(0),
    agent: @fugue.ReplicaId("a"),
  })
  parents.push(-1)
  for i = 1; i < bt.len; i = i + 1 {
    // Pick a random existing item as origin_left (creates parent-child relationship)
    let parent_idx = i % parents.length()
    let parent_lv = if parent_idx == 0 && i % 3 == 0 {
      // Sometimes insert at root level
      None
    } else {
      Some(@fugue.Lv(parent_idx))
    }
    tree.insert({
      id: @fugue.Lv(i),
      content: "A",
      origin_left: parent_lv,
      origin_right: None,
      timestamp: @fugue.Timestamp(i),
      agent: @fugue.ReplicaId("a"),
    })
    parents.push(parent_idx)
  }
  // Check all pairs
  for a = 0; a < bt.len; a = a + 1 {
    for b = a; b < bt.len; b = b + 1 {
      let jump_result = tree.is_ancestor(@fugue.Lv(a), @fugue.Lv(b))
      let naive_result = is_ancestor_naive(tree, @fugue.Lv(a), @fugue.Lv(b))
      if jump_result != naive_result {
        return false
      }
    }
  }
  true
}

///|
test "property: binary lifting matches naive on branching trees" {
  @qc.quick_check_fn(prop_jump_matches_naive_branching)
}
```

- [ ] **Step 2: Add depth consistency property test**

```moonbit
///|
/// Property: depth[x] == depth[parent] + 1 for all non-root items.
fn prop_jump_depth_consistency(bt : BranchingTree) -> Bool {
  let tree : @fugue.FugueTree[String] = @fugue.FugueTree::new()
  tree.insert({
    id: @fugue.Lv(0),
    content: "A",
    origin_left: None,
    origin_right: None,
    timestamp: @fugue.Timestamp(0),
    agent: @fugue.ReplicaId("a"),
  })
  for i = 1; i < bt.len; i = i + 1 {
    let parent_idx = i % i // use varying parents
    tree.insert({
      id: @fugue.Lv(i),
      content: "A",
      origin_left: if parent_idx == 0 && i % 3 == 0 {
        None
      } else {
        Some(@fugue.Lv(parent_idx))
      },
      origin_right: None,
      timestamp: @fugue.Timestamp(i),
      agent: @fugue.ReplicaId("a"),
    })
  }
  // Verify: for each item, is_ancestor(parent, item) must be true
  for i = 0; i < bt.len; i = i + 1 {
    let item = tree[@fugue.Lv(i)]
    match item {
      Some(it) =>
        match it.parent {
          Some(p) =>
            if not(tree.is_ancestor(p, @fugue.Lv(i))) {
              return false
            }
          None => ()
        }
      None => ()
    }
  }
  true
}

///|
test "property: depth consistency — parent is always ancestor" {
  @qc.quick_check_fn(prop_jump_depth_consistency)
}
```

- [ ] **Step 3: Add integration property test — concurrent ops via insert()**

```moonbit
///|
/// Property: binary lifting agrees with naive walk even for concurrent inserts
/// that trigger find_parent_and_side -> is_ancestor during insert().
fn prop_jump_via_concurrent_insert(chain : ChainLen) -> Bool {
  let tree : @fugue.FugueTree[String] = @fugue.FugueTree::new()
  // Build a base chain
  tree.insert({
    id: @fugue.Lv(0),
    content: "A",
    origin_left: None,
    origin_right: None,
    timestamp: @fugue.Timestamp(0),
    agent: @fugue.ReplicaId("a"),
  })
  for i = 1; i < chain.len; i = i + 1 {
    tree.insert({
      id: @fugue.Lv(i),
      content: "A",
      origin_left: Some(@fugue.Lv(i - 1)),
      origin_right: None,
      timestamp: @fugue.Timestamp(i),
      agent: @fugue.ReplicaId("a"),
    })
  }
  // Insert concurrent ops (both origin_left and origin_right set)
  let base = chain.len
  for i = 0; i < 5 && i + 1 < chain.len; i = i + 1 {
    tree.insert({
      id: @fugue.Lv(base + i),
      content: "X",
      origin_left: Some(@fugue.Lv(i)),
      origin_right: Some(@fugue.Lv(i + 1)),
      timestamp: @fugue.Timestamp(base + i),
      agent: @fugue.ReplicaId("b"),
    })
  }
  // Verify all pairs
  let total = base + 5
  for a = 0; a < total; a = a + 1 {
    for b = a; b < total; b = b + 1 {
      let jump_result = tree.is_ancestor(@fugue.Lv(a), @fugue.Lv(b))
      let naive_result = is_ancestor_naive(tree, @fugue.Lv(a), @fugue.Lv(b))
      if jump_result != naive_result {
        return false
      }
    }
  }
  true
}

///|
test "property: binary lifting correct with concurrent inserts" {
  @qc.quick_check_fn(prop_jump_via_concurrent_insert)
}
```

- [ ] **Step 4: Run all property tests**

```bash
cd event-graph-walker && moon test -p dowdiness/eg-walker/internal/fugue -f tree_properties_test.mbt
```
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
cd event-graph-walker && git add internal/fugue/tree_properties_test.mbt && git commit -m "test(fugue): add depth consistency and concurrent insert property tests"
```

---

### Task 8: Add benchmarks and compare

**Files:**
- Create: `internal/fugue/jump_ancestors_benchmark.mbt`

- [ ] **Step 1: Write benchmarks**

Create `internal/fugue/jump_ancestors_benchmark.mbt`:

```moonbit
///|
/// Benchmark: sequential append 1K — is_ancestor never called (regression check)
test "jump - sequential append 1K" (b : @bench.T) {
  b.bench(fn() {
    let tree : FugueTree[String] = FugueTree::new()
    let mut prev = -1
    for i = 0; i < 1000; i = i + 1 {
      tree.insert({
        id: Lv(i),
        content: "a",
        origin_left: if prev == -1 { None } else { Some(Lv(prev)) },
        origin_right: None,
        timestamp: Timestamp(i),
        agent: ReplicaId("agent0"),
      })
      prev = i
    }
    b.keep(tree)
  })
}

///|
/// Benchmark: concurrent insert into 1K doc — forces is_ancestor
/// Uses fresh tree per iteration to avoid duplicate LV issues.
test "jump - concurrent insert into 1K doc" (b : @bench.T) {
  b.bench(fn() {
    let tree : FugueTree[String] = FugueTree::new()
    let mut prev = -1
    for i = 0; i < 1000; i = i + 1 {
      tree.insert({
        id: Lv(i),
        content: "a",
        origin_left: if prev == -1 { None } else { Some(Lv(prev)) },
        origin_right: None,
        timestamp: Timestamp(i),
        agent: ReplicaId("agent0"),
      })
      prev = i
    }
    // Concurrent insert: both origin_left and origin_right set → triggers is_ancestor
    tree.insert({
      id: Lv(1000),
      content: "X",
      origin_left: Some(Lv(0)),
      origin_right: Some(Lv(500)),
      timestamp: Timestamp(1000),
      agent: ReplicaId("agent1"),
    })
    b.keep(tree)
  })
}

///|
/// Benchmark: concurrent insert into 10K doc — larger scale
test "jump - concurrent insert into 10K doc" (b : @bench.T) {
  b.bench(fn() {
    let tree : FugueTree[String] = FugueTree::new()
    let mut prev = -1
    for i = 0; i < 10000; i = i + 1 {
      tree.insert({
        id: Lv(i),
        content: "a",
        origin_left: if prev == -1 { None } else { Some(Lv(prev)) },
        origin_right: None,
        timestamp: Timestamp(i),
        agent: ReplicaId("agent0"),
      })
      prev = i
    }
    tree.insert({
      id: Lv(10000),
      content: "X",
      origin_left: Some(Lv(0)),
      origin_right: Some(Lv(5000)),
      timestamp: Timestamp(10000),
      agent: ReplicaId("agent1"),
    })
    b.keep(tree)
  })
}

///|
/// Benchmark: degenerate chain + remote insert (worst case for old naive walk)
test "jump - degenerate chain remote insert" (b : @bench.T) {
  b.bench(fn() {
    let tree : FugueTree[String] = FugueTree::new()
    let mut prev = -1
    for i = 0; i < 1000; i = i + 1 {
      tree.insert({
        id: Lv(i),
        content: "a",
        origin_left: if prev == -1 { None } else { Some(Lv(prev)) },
        origin_right: None,
        timestamp: Timestamp(i),
        agent: ReplicaId("agent0"),
      })
      prev = i
    }
    // Remote insert that forces is_ancestor(0, 999) — worst case depth
    tree.insert({
      id: Lv(1000),
      content: "X",
      origin_left: Some(Lv(0)),
      origin_right: Some(Lv(999)),
      timestamp: Timestamp(1000),
      agent: ReplicaId("agent1"),
    })
    b.keep(tree)
  })
}
```

- [ ] **Step 2: Run benchmarks**

```bash
cd event-graph-walker && moon bench --release -p dowdiness/eg-walker/internal/fugue
```

- [ ] **Step 3: Run branch benchmarks for comparison with baseline**

```bash
cd event-graph-walker && moon bench --release -p dowdiness/eg-walker/internal/branch
```

Compare output with `/tmp/lca-baseline.txt` from Task 1.

- [ ] **Step 4: Commit**

```bash
cd event-graph-walker && git add internal/fugue/jump_ancestors_benchmark.mbt && git commit -m "bench(fugue): add binary lifting benchmarks — concurrent insert, degenerate chain"
```

---

### Task 9: Full test suite verification and cleanup

**Files:**
- All modified files

- [ ] **Step 1: Run full event-graph-walker test suite**

```bash
cd event-graph-walker && moon test
```
Expected: All PASS

- [ ] **Step 2: Run full monorepo tests**

```bash
moon test
```
Expected: All PASS (editor, projection, etc. that depend on event-graph-walker)

- [ ] **Step 3: Run moon check and moon fmt**

```bash
cd event-graph-walker && moon check && moon info && moon fmt
```

- [ ] **Step 4: Verify no remaining references to removed APIs**

```bash
cd event-graph-walker && grep -r "build_lca_index\|set_batch_inserting\|batch_inserting\|LcaIndex\|lca_index" --include="*.mbt" internal/ | grep -v "_build/"
```
Expected: No matches (except possibly comments or the benchmark baseline file).

- [ ] **Step 5: Final commit if any formatting changes**

```bash
cd event-graph-walker && git add -A && git diff --cached --stat && git commit -m "chore: format and update interfaces after binary lifting migration"
```

---

## Task Dependency Graph

```
Task 1 (baseline) ──→ Task 2 (implement JumpAncestors)
                          │
                          ↓
                      Task 3 (wire into FugueTree)
                          │
                    ┌─────┼─────┐
                    ↓     ↓     ↓
               Task 4  Task 5  Task 6
             (update  (remove  (delete
              tests)  batch)   lca_index)
                    └─────┬─────┘
                          ↓
                      Task 7 (property tests)
                          ↓
                      Task 8 (benchmarks)
                          ↓
                      Task 9 (full verification)
```

Tasks 4, 5, 6 can be done in any order after Task 3. All must complete before Task 7.
