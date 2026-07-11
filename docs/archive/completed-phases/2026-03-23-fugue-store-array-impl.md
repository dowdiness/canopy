# Phase 2b: FugueTree Array Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace FugueTree's immutable HashMap storage with dense Array storage, reducing per-keystroke cost from ~30ms to ~1-2ms at 1000 items.

**Architecture:** In-place migration of FugueTree fields: `items: HashMap[Lv, Item[T]]` → `items: Array[Item[T]?]` (Option-wrapped for sparse LV support), `children: HashMap[Lv, Array[Lv]]` → `children: Array[Array[Lv]]` + `root_children: Array[Lv]`. LcaIndex `first: HashMap` → `first: Array[Int]` + `root_first: Int`. Item[T] fields `deleted`/`deleted_ts`/`deleted_agent`/`deleted_is_undelete` made `mut` for in-place updates. Public `FugueTree[T]` type preserved. Non-sequential LVs (used by tests for concurrent scenarios) are handled by padding with `None`.

**Tech Stack:** MoonBit, event-graph-walker submodule

**Spec:** `docs/plans/2026-03-23-fugue-store-array-design.md`

---

## File Structure

| File | Responsibility | Change |
|------|---------------|--------|
| `event-graph-walker/internal/fugue/item.mbt` | Item/Lv/Side types | Make 4 fields `mut` |
| `event-graph-walker/internal/fugue/tree.mbt` | FugueTree struct + all methods | Replace HashMap fields with Array, update all methods |
| `event-graph-walker/internal/fugue/lca_index.mbt` | LCA Euler Tour + Sparse Table | Replace `first` HashMap with Array + `root_first` |
| `event-graph-walker/internal/fugue/moon.pkg` | Package deps | Remove `@immut/hashmap` import |
| `event-graph-walker/internal/document/document.mbt` | Document API | Incremental cache delete, LCA fix |
| `event-graph-walker/internal/fugue/tree_test.mbt` | Blackbox tests | Add new tests (no existing test changes) |
| `event-graph-walker/internal/fugue/tree_properties_test.mbt` | Property tests | Add LV invariant test |

No new files created. All changes are modifications to existing files.

---

### Task 1: Spike — MoonBit struct field mutability in arrays

**Files:**
- Modify: `event-graph-walker/internal/fugue/tree_test.mbt`

This is a gate for the entire implementation. We need to verify that mutating a `mut` field on a struct stored in an Array modifies the original, not a copy.

- [ ] **Step 1: Write the spike test**

Add to the end of `event-graph-walker/internal/fugue/tree_test.mbt`:

```moonbit
///|
test "spike: struct mut field in array modifies in-place" {
  // Gate test for Phase 2b: verify MoonBit arrays store struct references
  // so that mutating a `mut` field on arr[i] changes the stored value.
  //
  // Item[T] will gain `mut deleted` etc. — if this test fails, all
  // delete/undelete code needs explicit read-modify-write.
  struct MutSpike {
    mut flag : Bool
  }

  let arr : Array[MutSpike] = [{ flag: false }, { flag: false }]
  arr[0].flag = true
  inspect!(arr[0].flag, content="true")
  inspect!(arr[1].flag, content="false")
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/fugue -f tree_test.mbt -i 0 -u "spike"`
Expected: PASS — MoonBit stores structs by reference in arrays.

If FAIL: every `items[idx].deleted = true` must become `let item = items[idx]; ... ; items[idx] = { ..item, deleted: true, ... }`. Adjust all subsequent tasks.

- [ ] **Step 3: Commit**

```bash
cd event-graph-walker && git add internal/fugue/tree_test.mbt && git commit -m "test: spike — verify MoonBit struct mut field in array mutates in-place"
```

---

### Task 2: Make Item[T] delete fields mutable

**Files:**
- Modify: `event-graph-walker/internal/fugue/item.mbt:31-57`

Change four fields from immutable to `mut`. This is safe with the current HashMap storage because `self.items.add(id, {...item, deleted: true})` still works — it just creates a new Item. But now in-place mutation also works, which Task 4 will use.

- [ ] **Step 1: Update Item[T] struct definition**

In `event-graph-walker/internal/fugue/item.mbt`, change lines 44, 46, 48, 50:

```moonbit
  /// `true` if the item has been deleted (tombstone). Tombstones remain in the
  /// tree so concurrent operations that reference this item remain valid.
  mut deleted : Bool
  /// Lamport timestamp of the winning Delete/Undelete op (0 = initial/no winner).
  mut deleted_ts : Int
  /// Agent ID of the winning Delete/Undelete op ("" = initial/no winner).
  mut deleted_agent : String
  /// `true` if the winner was an Undelete op, `false` if Delete or initial.
  mut deleted_is_undelete : Bool
```

- [ ] **Step 2: Run all tests to verify nothing breaks**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass. Adding `mut` to fields is backwards-compatible — existing code that creates new structs with `{..item, deleted: true}` still works.

- [ ] **Step 3: Update `.mbti` interface**

Run: `cd event-graph-walker && moon info`

- [ ] **Step 4: Commit**

```bash
cd event-graph-walker && git add internal/fugue/item.mbt pkg.generated.mbti internal/fugue/pkg.generated.mbti && git commit -m "refactor(fugue): make Item delete fields mutable for Phase 2b"
```

---

### Task 3: Replace FugueTree.items HashMap with Array

**Files:**
- Modify: `event-graph-walker/internal/fugue/tree.mbt:7-14` (struct), `:28-57` (constructors), `:64-66` (get), `:345-364` (add_item), `:173-322` (delete/undelete methods)

This is the core change. Replace `items : @immut/hashmap.HashMap[Lv, Item[T]]` with `items : Array[Item[T]?]` (Option-wrapped) and a separate `root_item : Item[T]` field. Option wrapping handles non-sequential LVs used by concurrent-insert tests: gaps are padded with `None`, preserving exact `get` semantics.

- [ ] **Step 1: Write test for array indexing including sparse LVs**

Add to `event-graph-walker/internal/fugue/tree_test.mbt`:

```moonbit
///|
test "item array indexing: LV lookup after migration" {
  let tree : FugueTree[String] = FugueTree::new()
  tree.insert({
    id: Lv(0),
    content: "A",
    origin_left: None,
    origin_right: None,
    timestamp: Timestamp(0),
    agent: ReplicaId("a"),
  })
  tree.insert({
    id: Lv(1),
    content: "B",
    origin_left: Some(Lv(0)),
    origin_right: None,
    timestamp: Timestamp(1),
    agent: ReplicaId("a"),
  })
  // Verify items are accessible by LV
  inspect!(tree[Lv(0)].map(fn(i) { i.content }), content="Some(\"A\")")
  inspect!(tree[Lv(1)].map(fn(i) { i.content }), content="Some(\"B\")")
  inspect!(tree[Lv(-1)].map(fn(i) { i.content }), content="Some(\"\")")
  inspect!(tree[Lv(99)], content="None")
}
```

- [ ] **Step 2: Run to verify it passes with current HashMap (baseline)**

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/fugue -f tree_test.mbt -u "item array indexing"`
Expected: PASS (existing behavior preserved).

- [ ] **Step 3: Replace `items` field on FugueTree struct**

In `event-graph-walker/internal/fugue/tree.mbt`, change the struct (lines 7-14):

```moonbit
pub struct FugueTree[T] {
  root_item : Item[T] // Virtual root, separate from array (LV = -1)
  mut items : Array[Item[T]?] // Sparse array indexed by LV. None = unused slot (padding for non-sequential LVs in tests).
  mut length : Int
  mut visible : Int
  mut children : @immut/hashmap.HashMap[Lv, Array[Lv]]
  mut lca_index : LcaIndex?
  mut batch_inserting : Bool
} derive(Show)
```

- [ ] **Step 4: Update constructors (`new`, `make`)**

Replace lines 28-57:

```moonbit
pub fn[T : Default] FugueTree::new() -> FugueTree[T] {
  FugueTree::make(T::default())
}

pub fn[T] FugueTree::make(root_content : T) -> FugueTree[T] {
  let root_item = Item::new(
    root_lv,
    root_content,
    None,
    Left,
    Timestamp(0),
    ReplicaId("root"),
  )
  let mut children = @immut/hashmap.HashMap::new()
  children = children.add(root_lv, [])
  {
    root_item,
    items: Array::new(capacity=1024),
    length: 0,
    visible: 0,
    children,
    lca_index: None,
    batch_inserting: false,
  }
}
```

- [ ] **Step 5: Update `get` method**

Replace lines 63-66:

```moonbit
#alias("_[_]")
pub fn[T] FugueTree::get(self : FugueTree[T], id : Lv) -> Item[T]? {
  if id == root_lv {
    Some(self.root_item)
  } else if id.0 >= 0 && id.0 < self.items.length() {
    self.items[id.0]  // Already Item[T]? — None for unused slots
  } else {
    None
  }
}
```

- [ ] **Step 6: Update `add_item` — pad with None for non-sequential LVs**

Replace lines 345-364. Handles both sequential (production: `lv == items.length()`, O(1)) and non-sequential (tests: `lv > items.length()`, pads with `None`):

```moonbit
fn[T] FugueTree::add_item(self : FugueTree[T], item : Item[T]) -> Unit {
  let lv = item.id.0
  // Grow array to accommodate this LV, padding gaps with None
  while self.items.length() <= lv {
    self.items.push(None)
  }
  self.items[lv] = Some(item)
  self.length = self.length + 1
  self.visible = self.visible + 1
  // Update children index
  match item.parent {
    Some(parent_lv) =>
      match self.children.get(parent_lv) {
        Some(arr) => arr.push(item.id)
        None => self.children = self.children.add(parent_lv, [item.id])
      }
    None => ()
  }
  self.children = self.children.add(item.id, [])
  self.lca_index = None
}
```

- [ ] **Step 7: Update delete/undelete methods to mutate in-place**

Replace `delete_with_ts` (lines 173-205) — use in-place mutation instead of `self.items.add(id, {..item, ...})`:

```moonbit
pub fn[T] FugueTree::delete_with_ts(
  self : FugueTree[T],
  id : Lv,
  ts : Int,
  agent : String,
) -> Unit raise FugueError {
  if id == root_lv {
    return
  }
  match self[id] {
    Some(item) =>
      if should_win_delete(
          ts,
          agent,
          false,
          item.deleted_ts,
          item.deleted_agent,
          item.deleted_is_undelete,
        ) {
        if not(item.deleted) {
          self.visible = self.visible - 1
        }
        item.deleted = true
        item.deleted_ts = ts
        item.deleted_agent = agent
        item.deleted_is_undelete = false
      }
    None => raise FugueError::MissingItem(id~)
  }
}
```

Apply same pattern to `undelete_with_ts` (lines 209-238):

```moonbit
pub fn[T] FugueTree::undelete_with_ts(
  self : FugueTree[T],
  id : Lv,
  ts : Int,
  agent : String,
) -> Unit raise FugueError {
  match self[id] {
    Some(item) =>
      if should_win_delete(
          ts,
          agent,
          true,
          item.deleted_ts,
          item.deleted_agent,
          item.deleted_is_undelete,
        ) {
        if item.deleted {
          self.visible = self.visible + 1
        }
        item.deleted = false
        item.deleted_ts = ts
        item.deleted_agent = agent
        item.deleted_is_undelete = true
      }
    None => raise FugueError::MissingItem(id~)
  }
}
```

Apply to `set_delete_winner` (lines 243-268):

```moonbit
pub fn[T] FugueTree::set_delete_winner(
  self : FugueTree[T],
  id : Lv,
  deleted : Bool,
  ts : Int,
  agent : String,
  is_undelete : Bool,
) -> Unit raise FugueError {
  match self[id] {
    Some(item) => {
      if item.deleted && not(deleted) {
        self.visible = self.visible + 1
      } else if not(item.deleted) && deleted {
        self.visible = self.visible - 1
      }
      item.deleted = deleted
      item.deleted_ts = ts
      item.deleted_agent = agent
      item.deleted_is_undelete = is_undelete
    }
    None => raise FugueError::MissingItem(id~)
  }
}
```

Apply to `delete` (lines 274-299):

```moonbit
pub fn[T] FugueTree::delete(
  self : FugueTree[T],
  id : Lv,
) -> Unit raise FugueError {
  if id == root_lv {
    return
  }
  match self[id] {
    Some(item) => {
      if not(item.deleted) {
        self.visible = self.visible - 1
      }
      item.deleted = true
      item.deleted_ts = 0
      item.deleted_agent = ""
      item.deleted_is_undelete = false
    }
    None => raise FugueError::MissingItem(id~)
  }
}
```

Apply to `undelete` (lines 304-322):

```moonbit
pub fn[T] FugueTree::undelete(
  self : FugueTree[T],
  id : Lv,
) -> Unit raise FugueError {
  match self[id] {
    Some(item) =>
      if item.deleted {
        self.visible = self.visible + 1
        item.deleted = false
        item.deleted_ts = 0
        item.deleted_agent = ""
        item.deleted_is_undelete = true
      }
    None => raise FugueError::MissingItem(id~)
  }
}
```

- [ ] **Step 8: Run all tests**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass. The items field is now an Array; delete/undelete mutate in-place.

- [ ] **Step 9: Run `moon info && moon fmt`**

Run: `cd event-graph-walker && moon info && moon fmt`

- [ ] **Step 10: Commit**

```bash
cd event-graph-walker && git add internal/fugue/item.mbt internal/fugue/tree.mbt internal/fugue/tree_test.mbt internal/fugue/pkg.generated.mbti && git commit -m "feat(fugue): replace items HashMap with Array + in-place delete mutation"
```

---

### Task 4: Replace FugueTree.children HashMap with Array + root_children

**Files:**
- Modify: `event-graph-walker/internal/fugue/tree.mbt:7-14` (struct), constructors, `add_item`, `get_children_raw`, `get_children_index`, `traverse_tree`

- [ ] **Step 1: Update struct — replace children HashMap**

In the struct definition, change:

```moonbit
pub struct FugueTree[T] {
  root_item : Item[T]
  mut items : Array[Item[T]?]
  mut length : Int
  mut visible : Int
  root_children : Array[Lv] // Root's children (root not in items array)
  mut children : Array[Array[Lv]] // Children index, sparse array indexed by LV
  mut lca_index : LcaIndex?
  mut batch_inserting : Bool
} derive(Show)
```

- [ ] **Step 2: Add get_children helper**

Add after the struct definition:

```moonbit
///|
/// Get children for a node. Handles root (LV=-1) separately.
fn[T] FugueTree::get_children(self : FugueTree[T], id : Lv) -> Array[Lv] {
  if id == root_lv {
    self.root_children
  } else if id.0 >= 0 && id.0 < self.children.length() {
    self.children[id.0]
  } else {
    []
  }
}
```

- [ ] **Step 3: Update constructor**

```moonbit
pub fn[T] FugueTree::make(root_content : T) -> FugueTree[T] {
  let root_item = Item::new(
    root_lv,
    root_content,
    None,
    Left,
    Timestamp(0),
    ReplicaId("root"),
  )
  {
    root_item,
    items: Array::new(capacity=1024),
    length: 0,
    visible: 0,
    root_children: [],
    children: Array::new(capacity=1024),
    lca_index: None,
    batch_inserting: false,
  }
}
```

- [ ] **Step 4: Update `add_item` — use array for children, pad for non-sequential LVs**

```moonbit
fn[T] FugueTree::add_item(self : FugueTree[T], item : Item[T]) -> Unit {
  let lv = item.id.0
  // Grow items array to accommodate this LV
  while self.items.length() <= lv {
    self.items.push(None)
  }
  self.items[lv] = Some(item)
  self.length = self.length + 1
  self.visible = self.visible + 1
  // Register as child of parent
  match item.parent {
    Some(parent_lv) => self.get_children(parent_lv).push(item.id)
    None => ()
  }
  // Grow children array and initialize empty entry for the new item
  while self.children.length() <= lv {
    self.children.push([])
  }
  self.lca_index = None
}
```

- [ ] **Step 5: Update `get_children_index` and `get_children_raw`**

```moonbit
pub fn[T] FugueTree::get_children_index(
  self : FugueTree[T],
  parent_id : Lv,
) -> Array[Lv] {
  self.get_children(parent_id).copy()
}

fn[T] FugueTree::get_children_raw(
  self : FugueTree[T],
  parent_id : Lv,
) -> Array[Lv] {
  self.get_children(parent_id)
}
```

- [ ] **Step 6: Update `is_ancestor_naive` — terminate at parent == None (root)**

No change needed — `item.parent` is `Lv?`, and `None` means root. The existing code already handles this correctly:

```moonbit
// Existing code is correct:
// match item.parent {
//   Some(parent_lv) => ...
//   None => break false // Reached root
// }
```

Verify this is still correct after migration.

- [ ] **Step 7: Run all tests**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass.

- [ ] **Step 8: Run `moon info && moon fmt`**

Run: `cd event-graph-walker && moon info && moon fmt`

- [ ] **Step 9: Commit**

```bash
cd event-graph-walker && git add internal/fugue/tree.mbt internal/fugue/pkg.generated.mbti && git commit -m "feat(fugue): replace children HashMap with Array + root_children"
```

---

### Task 5: Update LcaIndex to Array-backed `first` field

**Files:**
- Modify: `event-graph-walker/internal/fugue/lca_index.mbt:4-10` (struct), `:24-92` (build), `:95-115` (is_ancestor)

- [ ] **Step 1: Write test for LCA root edge case**

Add to `event-graph-walker/internal/fugue/tree_test.mbt`:

```moonbit
///|
test "LCA: root is ancestor of all items" {
  let tree : FugueTree[String] = FugueTree::new()
  tree.insert({
    id: Lv(0),
    content: "A",
    origin_left: None,
    origin_right: None,
    timestamp: Timestamp(0),
    agent: ReplicaId("a"),
  })
  // Root (-1) is ancestor of everything
  inspect!(tree.is_ancestor(Lv(-1), Lv(0)), content="true")
  inspect!(tree.is_ancestor(Lv(0), Lv(-1)), content="false")
}

///|
test "LCA: empty document — root only" {
  let tree : FugueTree[String] = FugueTree::new()
  inspect!(tree.is_ancestor(Lv(-1), Lv(-1)), content="true")
}
```

- [ ] **Step 2: Run to verify they pass with current HashMap (baseline)**

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/fugue -f tree_test.mbt -u "LCA"`
Expected: PASS.

- [ ] **Step 3: Replace LcaIndex struct**

In `event-graph-walker/internal/fugue/lca_index.mbt`, replace lines 4-10:

```moonbit
struct LcaIndex {
  euler_tour : Array[Lv]
  depth : Array[Int]
  first : Array[Int] // first[lv] = first occurrence index in euler_tour (non-root items)
  root_first : Int // First occurrence of root in euler_tour
  sparse : Array[Array[Int]]
  tour_len : Int
} derive(Show)
```

- [ ] **Step 4: Update `LcaIndex::build` — use Array for `first`**

Replace lines 24-92. Key changes: `first` is now an `Array[Int]` sized to `tree.items.length()`, initialized to -1. Root's first occurrence stored in `root_first`. First-occurrence tracking is inlined (not a closure) to avoid MoonBit `mut` local capture issues.

```moonbit
fn[T] LcaIndex::build(tree : FugueTree[T]) -> LcaIndex {
  let euler_tour : Array[Lv] = []
  let depth_arr : Array[Int] = []
  // Dense array for first occurrence. -1 = not yet seen.
  let first : Array[Int] = Array::make(tree.items.length(), -1)
  let mut root_first = -1

  // Iterative DFS using explicit stack
  let stack : Array[(Lv, Int, Int)] = [(root_lv, 0, -1)]
  while stack.length() > 0 {
    let (node_id, d, child_idx) = stack[stack.length() - 1]
    if child_idx == -1 {
      euler_tour.push(node_id)
      depth_arr.push(d)
      // Record first occurrence (inlined, not a closure — avoids mut capture issues)
      let tour_idx = euler_tour.length() - 1
      if node_id == root_lv {
        if root_first == -1 {
          root_first = tour_idx
        }
      } else if node_id.0 >= 0 && node_id.0 < first.length() && first[node_id.0] == -1 {
        first[node_id.0] = tour_idx
      }
      stack[stack.length() - 1] = (node_id, d, 0)
    } else {
      let child_lvs = tree.get_children_raw(node_id)
      if child_idx < child_lvs.length() {
        stack[stack.length() - 1] = (node_id, d, child_idx + 1)
        let child_lv = child_lvs[child_idx]
        stack.push((child_lv, d + 1, -1))
      } else {
        let _ = stack.pop()
        if stack.length() > 0 {
          let (parent_id, parent_d, _) = stack[stack.length() - 1]
          euler_tour.push(parent_id)
          depth_arr.push(parent_d)
        }
      }
    }
  }

  // Build sparse table for RMQ (unchanged algorithm)
  let tour_len = euler_tour.length()
  let log_n = if tour_len <= 1 { 1 } else { log2_floor(tour_len) + 1 }
  let sparse : Array[Array[Int]] = []

  let level0 : Array[Int] = Array::make(tour_len, 0)
  for i = 0; i < tour_len; i = i + 1 {
    level0[i] = i
  }
  sparse.push(level0)

  for k = 1; k < log_n; k = k + 1 {
    let prev = sparse[k - 1]
    let range = 1 << k
    let len = if tour_len >= range { tour_len - range + 1 } else { 0 }
    let level : Array[Int] = Array::make(len, 0)
    let half = range / 2
    for i = 0; i < len; i = i + 1 {
      let left = prev[i]
      let right = prev[i + half]
      level[i] = if depth_arr[left] <= depth_arr[right] { left } else { right }
    }
    sparse.push(level)
  }

  { euler_tour, depth: depth_arr, first, root_first, sparse, tour_len }
}
```

- [ ] **Step 5: Update `LcaIndex::is_ancestor` — use Array lookup**

Replace lines 95-115:

```moonbit
fn LcaIndex::is_ancestor(
  self : LcaIndex,
  ancestor_id : Lv,
  descendant_id : Lv,
) -> Bool {
  if ancestor_id == descendant_id {
    return true
  }
  let a_idx = if ancestor_id == root_lv {
    if self.root_first == -1 { return false } else { self.root_first }
  } else if ancestor_id.0 >= 0 && ancestor_id.0 < self.first.length() {
    let idx = self.first[ancestor_id.0]
    if idx == -1 { return false } else { idx }
  } else {
    return false
  }
  let b_idx = if descendant_id == root_lv {
    if self.root_first == -1 { return false } else { self.root_first }
  } else if descendant_id.0 >= 0 && descendant_id.0 < self.first.length() {
    let idx = self.first[descendant_id.0]
    if idx == -1 { return false } else { idx }
  } else {
    return false
  }
  let lo = if a_idx < b_idx { a_idx } else { b_idx }
  let hi = if a_idx > b_idx { a_idx } else { b_idx }
  let lca_idx = self.rmq(lo, hi)
  self.euler_tour[lca_idx] == ancestor_id
}
```

- [ ] **Step 6: Run all tests**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass, including the new LCA root edge case tests.

- [ ] **Step 7: Run `moon info && moon fmt`**

Run: `cd event-graph-walker && moon info && moon fmt`

- [ ] **Step 8: Commit**

```bash
cd event-graph-walker && git add internal/fugue/lca_index.mbt internal/fugue/tree_test.mbt internal/fugue/pkg.generated.mbti && git commit -m "feat(fugue): replace LcaIndex first HashMap with Array + root_first"
```

---

### Task 6: Remove `@immut/hashmap` dependency from fugue package

**Files:**
- Modify: `event-graph-walker/internal/fugue/moon.pkg`

After Tasks 3-5, no code in the fugue package uses `@immut/hashmap`.

- [ ] **Step 1: Verify no remaining HashMap usage**

Run: `cd event-graph-walker && grep -r "immut/hashmap\|@immut/hashmap\|HashMap" internal/fugue/`
Expected: No matches (or only in test files if any).

- [ ] **Step 2: Remove import from moon.pkg**

In `event-graph-walker/internal/fugue/moon.pkg`, remove lines 1-3:

Change from:
```json
import {
  "moonbitlang/core/immut/hashmap" @immut/hashmap,
}
```

To: (remove the entire import block, keep test imports)

```json
import {
  "moonbitlang/core/cmp",
  "moonbitlang/core/quickcheck",
  "moonbitlang/quickcheck" @qc,
} for "test"

options(
  is_main: false,
)
```

- [ ] **Step 3: Run all tests**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass. No HashMap usage remains.

- [ ] **Step 4: Run `moon check && moon info && moon fmt`**

Run: `cd event-graph-walker && moon check && moon info && moon fmt`

- [ ] **Step 5: Commit**

```bash
cd event-graph-walker && git add internal/fugue/moon.pkg internal/fugue/pkg.generated.mbti && git commit -m "chore(fugue): remove @immut/hashmap dependency — all storage now Array-backed"
```

---

### Task 7: Fix LCA invalidation — don't invalidate on delete/undelete

**Files:**
- Modify: `event-graph-walker/internal/fugue/tree.mbt` (delete/undelete methods already updated in Task 3)

Currently delete/undelete don't explicitly invalidate LCA (the old code did it via `self.items = self.items.add(...)` which didn't touch `lca_index`). But `add_item` sets `self.lca_index = None`. We need to verify delete/undelete do NOT invalidate.

- [ ] **Step 1: Write test — LCA survives delete/undelete**

Add to `event-graph-walker/internal/fugue/tree_test.mbt`:

```moonbit
///|
test "LCA: not invalidated by delete/undelete" {
  let tree : FugueTree[String] = FugueTree::new()
  tree.insert({
    id: Lv(0),
    content: "A",
    origin_left: None,
    origin_right: None,
    timestamp: Timestamp(0),
    agent: ReplicaId("a"),
  })
  tree.insert({
    id: Lv(1),
    content: "B",
    origin_left: Some(Lv(0)),
    origin_right: None,
    timestamp: Timestamp(1),
    agent: ReplicaId("a"),
  })

  // Force LCA build
  tree.build_lca_index()

  // Delete should NOT invalidate LCA
  tree.delete!(Lv(1))
  // Ancestor check should still work (LCA intact)
  inspect!(tree.is_ancestor(Lv(0), Lv(1)), content="true")

  // Undelete should NOT invalidate LCA
  tree.undelete!(Lv(1))
  inspect!(tree.is_ancestor(Lv(0), Lv(1)), content="true")
}
```

- [ ] **Step 2: Run test**

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/fugue -f tree_test.mbt -u "LCA: not invalidated"`
Expected: PASS — delete/undelete don't touch `lca_index` in the new code (Task 3 already removed the `self.items = self.items.add(...)` pattern which was the only thing that could have triggered it indirectly).

If FAIL: verify that none of the delete/undelete methods set `self.lca_index = None`. Only `add_item` and `set_batch_inserting(false)` should.

- [ ] **Step 3: Commit**

```bash
cd event-graph-walker && git add internal/fugue/tree_test.mbt && git commit -m "test(fugue): verify LCA not invalidated by delete/undelete"
```

---

### Task 8: Incremental position cache — delete at known position

**Files:**
- Modify: `event-graph-walker/internal/document/document.mbt:246-283` (delete method)

Currently `Document::delete` always invalidates the cache (line 281). Since delete at a known position is safe for incremental update, use `cache.delete_at(position)` instead.

- [ ] **Step 1: Write test for incremental delete**

Add to `event-graph-walker/internal/document/document_test.mbt`:

```moonbit
///|
test "delete: position cache incrementally updated" {
  let doc = @document.Document::new("test")
  let _ = doc.insert!(0, "abc")
  // Cache is built on first position query
  inspect!(doc.visible_count(), content="3")
  inspect!(doc.to_text(), content="abc")

  // Delete middle character — cache should be incrementally updated
  let _ = doc.delete!(1) // delete 'b'
  inspect!(doc.to_text(), content="ac")
  inspect!(doc.visible_count(), content="2")

  // Verify position lookups still work after incremental delete
  let _ = doc.delete!(0) // delete 'a'
  inspect!(doc.to_text(), content="c")
}
```

- [ ] **Step 2: Run to verify it passes with current invalidation (baseline)**

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/document -f document_test.mbt -u "delete: position cache"`
Expected: PASS.

- [ ] **Step 3: Modify `Document::delete` for incremental cache update**

In `event-graph-walker/internal/document/document.mbt`, replace line 281 (`self.invalidate_cache()`) with:

```moonbit
  // Incremental cache update: delete at known position
  match self.position_cache {
    Some(cache) => cache.delete_at(position) |> ignore
    None => ()
  }
```

The full method becomes (lines 246-283):

```moonbit
pub fn Document::delete(
  self : Document,
  position : Int,
) -> @core.Op raise DocumentError {
  self.cursor = None
  if position < 0 {
    raise DocumentError::InvalidPosition(pos=position)
  }

  let cache = self.get_position_cache()
  let total = @rle.Spanning::span(cache)
  if position >= total {
    raise DocumentError::InvalidPosition(pos=position)
  }

  let target_lv = match self.lv_at_position(position) {
    Some(lv) => lv
    None => raise DocumentError::InvalidPosition(pos=position)
  }

  let op = self.oplog.delete(target_lv) catch {
    e => raise DocumentError::OpLog(e)
  }
  let cg = self.oplog.causal_graph()
  let (del_ts, del_agent) = match cg[op.lv()] {
    Some(entry) => (entry.timestamp, entry.agent)
    None =>
      raise DocumentError::OpLog(
        @oplog.OpLogError::MissingLocalVersion(lv=op.lv()),
      )
  }
  self.tree.delete_with_ts(@fugue.Lv(target_lv), del_ts, del_agent) catch {
    e => raise DocumentError::Fugue(e)
  }

  // Incremental cache update: delete at known position
  match self.position_cache {
    Some(cache) => cache.delete_at(position) |> ignore
    None => ()
  }
  op
}
```

- [ ] **Step 4: Run all document tests**

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/document`
Expected: All tests pass.

- [ ] **Step 5: Run all tests (full suite)**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass.

- [ ] **Step 6: Run `moon info && moon fmt`**

Run: `cd event-graph-walker && moon info && moon fmt`

- [ ] **Step 7: Commit**

```bash
cd event-graph-walker && git add internal/document/document.mbt internal/document/document_test.mbt && git commit -m "perf(document): incremental position cache delete instead of full rebuild"
```

---

### Task 8b: Additional spec-required tests

**Files:**
- Modify: `event-graph-walker/internal/document/document_test.mbt`

These tests are required by the design spec but were not covered by earlier tasks.

- [ ] **Step 1: Write cursor fast-path → non-sequential insert test**

Add to `event-graph-walker/internal/document/document_test.mbt`:

```moonbit
///|
test "cursor fast-path to non-sequential insert invalidates cache" {
  let doc = @document.Document::new("test")
  // Sequential inserts (cursor fast-path)
  let _ = doc.insert!(0, "abc")
  inspect!(doc.to_text(), content="abc")

  // Non-sequential insert at position 1 (cursor miss — should invalidate cache)
  let _ = doc.insert!(1, "X")
  inspect!(doc.to_text(), content="aXbc")

  // Verify further operations work after cache invalidation
  let _ = doc.delete!(2) // delete 'b'
  inspect!(doc.to_text(), content="aXc")
}
```

- [ ] **Step 2: Write delete_range across multiple VisibleRuns test**

```moonbit
///|
test "delete_range across split VisibleRuns" {
  let doc = @document.Document::new("test")
  let _ = doc.insert!(0, "abcde")
  inspect!(doc.to_text(), content="abcde")

  // Delete middle char to split the VisibleRun
  let _ = doc.delete!(2) // delete 'c', now "abde"
  inspect!(doc.to_text(), content="abde")

  // delete_range across the split boundary
  doc.delete_range!(1, 3) // delete 'b','d'
  inspect!(doc.to_text(), content="ae")
}
```

- [ ] **Step 3: Run tests**

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/document`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
cd event-graph-walker && git add internal/document/document_test.mbt && git commit -m "test(document): add cursor transition and delete_range spec tests"
```

---

### Task 9: Benchmark and verify performance

**Files:**
- Run existing benchmarks, no file changes needed

- [ ] **Step 1: Run benchmarks**

Run: `cd event-graph-walker && moon bench --release`

Record results for comparison with pre-Phase-2b baseline. Key metrics:
- `bench_append_1000_chars`: should show significant improvement (HashMap allocation eliminated)
- `bench_get_text_1000`: should be similar or slightly faster (Array access vs HashMap)
- Any position cache related benchmarks

- [ ] **Step 2: Run full test suite one final time**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass.

- [ ] **Step 3: Run `moon check && moon info && moon fmt`**

Run: `cd event-graph-walker && moon check && moon info && moon fmt`

- [ ] **Step 4: Verify git diff of `.mbti` interfaces**

Run: `cd event-graph-walker && git diff *.mbti internal/**/*.mbti`
Expected: Changes should show:
- `Item[T]` fields now `mut` for delete-related fields
- `FugueTree[T]` struct field types changed
- No unexpected public API removals

- [ ] **Step 5: Commit any remaining interface updates**

```bash
cd event-graph-walker && git add -A && git commit -m "chore: update interfaces after Phase 2b array migration"
```

---

## Task Dependency Graph

```
Task 1 (spike) ──→ Task 2 (mut fields) ──→ Task 3 (items Array) ──→ Task 4 (children Array) ──→ Task 5 (LCA Array) ──→ Task 6 (remove dep)
                                                                                                                            │
                                                                                                 Task 7 (LCA invalidation) ─┤
                                                                                                                            │
                                                                                                 Task 8 (incremental cache) ┤
                                                                                                                            │
                                                                                                 Task 8b (spec tests) ──────┤
                                                                                                                            │
                                                                                                 Task 9 (benchmark) ────────┘
```

Tasks 7, 8, and 8b can run in parallel after Task 6. Task 9 runs last.

**Note:** After any task that changes struct definitions (Tasks 3, 4, 5), run `moon test --update` if snapshot tests fail due to `derive(Show)` output changes.
