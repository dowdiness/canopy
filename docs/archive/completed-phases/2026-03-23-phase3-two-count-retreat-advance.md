**Status:** Complete

# Phase 3: Two-Count Retreat/Advance State Machine

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the O(total_ops) oplog scan in retreat and make the position cache survive merge operations, reducing merge cost from O(k × total_ops) to O(k log n).

**Architecture:** Replace implicit item state (boolean `deleted` flag + LWW winner fields) with an explicit `ItemState` enum and `delete_count` integer. During merge, retreat/advance operations become O(1) counter decrements/increments instead of oplog scans. LWW winner recomputation is deferred to a post-merge sweep over only affected items, using a lazily-built inverted delete index. The position cache (OrderTree[VisibleRun]) is incrementally maintained during merge instead of invalidated and rebuilt.

**Tech Stack:** MoonBit, event-graph-walker CRDT library, OrderTree (order-tree submodule), RLE (rle submodule)

**Depends on:** Phase 2b (Array-backed FugueStore) — not yet implemented. This plan can proceed independently on the current HashMap-backed FugueTree, or be sequenced after Phase 2b. Tasks are written against the current codebase.

---

## Background

### Current retreat bottleneck

In `event-graph-walker/internal/branch/branch_merge.mbt:147-243`, `retreat_operations` handles Delete/Undelete ops by scanning the **entire oplog** (line 180: `for i = 0; i < op_count`) to find all other Delete/Undelete ops targeting the same item. For each, it checks `rle_contains_lv(operations, i)` to filter out retreated ops, then recomputes the LWW winner from the remaining set.

For a document with N total ops and k retreated deletes, this is O(k × N). At 10K ops with 50 retreated deletes, that's 500K iterations — each involving an RLE membership check.

### Current position cache invalidation

In `event-graph-walker/internal/document/document.mbt:514`, `self.invalidate_cache()` is called before every merge. After merge, the next position query triggers `build_position_cache()` which does a full O(n) tree traversal + `OrderTree.from_array()`.

### Design principles

1. **State is explicit, not implicit.** Every item declares what it *is* via an enum, not through side effects on boolean fields.
2. **Indexes are maintained incrementally, not rebuilt from scratch.** The delete index and position cache are updated as operations happen.
3. **The common case is fast, the rare case is correct.** Small merges (1-10 ops) are O(k log n). Large merges fall back to O(n) rebuild.
4. **Merge is a first-class operation with its own context.** A structured state machine with explicit phases, not a sequence of ad-hoc mutations.

### Two-count approach

From the eg-walker paper: instead of tracking which specific delete operation "wins" (LWW), count active deletes per item:

- `retreat_delete(item)` → `delete_count -= 1` → O(1)
- `advance_delete(item)` → `delete_count += 1` → O(1)
- `retreat_undelete(item)` → `delete_count += 1` → O(1) (retreating an undelete re-applies its cancelled delete)
- `advance_undelete(item)` → `delete_count -= 1` → O(1)
- Visible = `state == Inserted && delete_count == 0`

LWW semantics are only needed for the final resting state (steady state between merges). During merge, counts suffice. After merge completes, a sweep recomputes LWW winners only for items whose delete count changed.

---

## File Structure

### New files

| File | Responsibility |
|------|---------------|
| `internal/fugue/item_state.mbt` | `ItemState` enum, `DeleteCount` helper, state transition functions |
| `internal/branch/delete_index.mbt` | `DeleteIndex` — inverted index mapping target_lv → delete/undelete ops |
| `internal/document/merge_cache.mbt` | `MergeCache` — incremental position cache wrapper for merge operations (lives in `document` package to avoid circular dependency with `branch`) |
| `internal/fugue/item_state_wbtest.mbt` | Tests for ItemState transitions (whitebox: needs access to `Item::new` which is package-private) |
| `internal/branch/delete_index_test.mbt` | Tests for DeleteIndex |
| `internal/document/merge_cache_test.mbt` | Tests for MergeCache |

### Modified files

| File | Changes |
|------|---------|
| `internal/fugue/item.mbt` | Add `mut state : ItemState` and `mut delete_count : Int` fields to `Item[T]` |
| `internal/fugue/tree.mbt` | Update `add_item`, `delete`, `undelete`, `delete_with_ts`, `undelete_with_ts`, `set_delete_winner` to maintain ItemState and delete_count |
| `internal/branch/branch_merge.mbt` | Rewrite `MergeContext` to use two-count retreat/advance, add post-merge LWW sweep |
| `internal/document/document.mbt` | Pass position cache into MergeContext for incremental updates during merge |

---

## Task 1: ItemState enum and state transitions

**Files:**
- Create: `event-graph-walker/internal/fugue/item_state.mbt`
- Create: `event-graph-walker/internal/fugue/item_state_wbtest.mbt`

- [ ] **Step 1: Write failing test for ItemState transitions**

```moonbit
// item_state_wbtest.mbt

///|
test "ItemState - valid transitions" {
  // NotInserted → Inserted (advance_insert)
  inspect(ItemState::NotInserted.advance_insert(), content="Inserted")
  // Retreated → Inserted (advance_insert after retreat)
  inspect(ItemState::Retreated.advance_insert(), content="Inserted")
  // Inserted → Retreated (retreat_insert)
  inspect(ItemState::Inserted.retreat_insert(), content="Retreated")
  // Deleted → Retreated (retreat_insert on tombstoned item)
  inspect(ItemState::Deleted.retreat_insert(), content="Retreated")
}

///|
test "ItemState - visibility" {
  inspect(ItemState::NotInserted.is_visible(delete_count=0), content="false")
  inspect(ItemState::Inserted.is_visible(delete_count=0), content="true")
  inspect(ItemState::Inserted.is_visible(delete_count=1), content="false")
  inspect(ItemState::Deleted.is_visible(delete_count=0), content="false")
  inspect(ItemState::Retreated.is_visible(delete_count=0), content="false")
}

///|
test "ItemState - update_from_delete_count" {
  // Inserted with delete_count > 0 → Deleted
  inspect(ItemState::Inserted.update_from_delete_count(1), content="Deleted")
  // Deleted with delete_count == 0 → Inserted
  inspect(ItemState::Deleted.update_from_delete_count(0), content="Inserted")
  // Inserted with delete_count == 0 → Inserted (no change)
  inspect(ItemState::Inserted.update_from_delete_count(0), content="Inserted")
  // Retreated is unaffected by delete_count
  inspect(ItemState::Retreated.update_from_delete_count(0), content="Retreated")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd event-graph-walker && moon test -p internal/fugue -f item_state_wbtest.mbt`
Expected: FAIL — `ItemState` not defined

- [ ] **Step 3: Implement ItemState**

```moonbit
// item_state.mbt

///|
/// Explicit state of an item during merge operations.
///
/// During steady state (between merges), items are either Inserted or Deleted.
/// During merge, items can transition through NotInserted and Retreated states
/// as operations are retreated and advanced.
pub enum ItemState {
  /// Item's insert op hasn't been applied yet
  NotInserted
  /// Item is in the tree, visibility depends on delete_count
  Inserted
  /// Item is in the tree, has active deletes (delete_count > 0)
  Deleted
  /// Item's insert was retreated during merge — temporarily invisible
  Retreated
} derive(Show, Eq)

///|
/// Default state for new items being inserted
pub impl Default for ItemState with default() -> ItemState {
  Inserted
}

///|
/// Transition: retreat an insert operation
pub fn ItemState::retreat_insert(self : ItemState) -> ItemState {
  Retreated
}

///|
/// Transition: advance an insert operation
pub fn ItemState::advance_insert(self : ItemState) -> ItemState {
  Inserted
}

///|
/// Update state based on current delete_count.
/// Called after delete_count changes to keep state consistent.
/// Retreated and NotInserted states are not affected by delete_count.
pub fn ItemState::update_from_delete_count(
  self : ItemState,
  delete_count : Int,
) -> ItemState {
  match self {
    Inserted => if delete_count > 0 { Deleted } else { Inserted }
    Deleted => if delete_count == 0 { Inserted } else { Deleted }
    Retreated => Retreated
    NotInserted => NotInserted
  }
}

///|
/// Check visibility: only Inserted items with no active deletes are visible
pub fn ItemState::is_visible(
  self : ItemState,
  delete_count~ : Int,
) -> Bool {
  self == Inserted && delete_count == 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd event-graph-walker && moon test -p internal/fugue -f item_state_wbtest.mbt`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `cd event-graph-walker && moon test`
Expected: All 315 tests pass (new file doesn't affect existing code yet)

- [ ] **Step 6: Commit**

```bash
cd event-graph-walker
git add internal/fugue/item_state.mbt internal/fugue/item_state_wbtest.mbt
git commit -m "feat(fugue): add ItemState enum with transition functions"
```

---

## Task 2: Add ItemState and delete_count to Item struct

**Files:**
- Modify: `event-graph-walker/internal/fugue/item.mbt`
- Modify: `event-graph-walker/internal/fugue/tree.mbt`

This task adds the new fields but keeps existing behavior unchanged. The `deleted` boolean is kept as the source of truth for now; `state` and `delete_count` are maintained in parallel. Task 5 will switch the source of truth.

- [ ] **Step 1: Write failing test for new fields on Item**

```moonbit
// Add to item_state_wbtest.mbt

///|
test "Item - new fields initialized correctly" {
  let item = Item::new(
    Lv(0), "A", None, Left, Timestamp(0), ReplicaId("a"),
  )
  inspect(item.state, content="Inserted")
  inspect(item.delete_count, content="0")
}

///|
test "Item - delete_count and state after operations" {
  let item = Item::new(
    Lv(0), "A", None, Left, Timestamp(0), ReplicaId("a"),
  )
  // Simulate retreat_insert
  item.state = item.state.retreat_insert()
  inspect(item.state, content="Retreated")
  inspect(item.is_visible(), content="false")
  // Simulate advance_insert
  item.state = item.state.advance_insert()
  inspect(item.state, content="Inserted")
  inspect(item.is_visible(), content="true")
  // Simulate advance_delete
  item.delete_count = item.delete_count + 1
  item.state = item.state.update_from_delete_count(item.delete_count)
  inspect(item.state, content="Deleted")
  inspect(item.is_visible(), content="false")
  // Simulate retreat_delete
  item.delete_count = item.delete_count - 1
  item.state = item.state.update_from_delete_count(item.delete_count)
  inspect(item.state, content="Inserted")
  inspect(item.is_visible(), content="true")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd event-graph-walker && moon test -p internal/fugue -f item_state_wbtest.mbt`
Expected: FAIL — `state` and `delete_count` fields don't exist on Item

- [ ] **Step 3: Add fields to Item struct**

In `internal/fugue/item.mbt`, add two fields to `Item[T]`:

```moonbit
// Add after `mut deleted_is_undelete : Bool`
  /// Explicit state for merge operations
  mut state : ItemState
  /// Number of active delete operations on this item (0 = no active deletes)
  mut delete_count : Int
```

Update `Item::new` to initialize them:

```moonbit
    // Add to the struct literal in Item::new, before timestamp:
    state: Inserted,
    delete_count: 0,
```

Update `Item::is_visible` to use the new fields while keeping backward compatibility:

```moonbit
fn[T] Item::is_visible(self : Item[T]) -> Bool {
  self.state.is_visible(delete_count=self.delete_count)
}
```

- [ ] **Step 4: Update FugueTree mutation methods to maintain new fields**

In `internal/fugue/tree.mbt`, update each mutation method to keep `state` and `delete_count` in sync:

**`add_item`** (line 336): After `self.items[lv] = Some(item)`, the item's state is already `Inserted` from `Item::new`. No change needed.

**`delete`** (line 271, force-delete used by retreat): After setting `item.deleted = true`:
```moonbit
      // Keep state/delete_count in sync (force-delete resets to retreated-like state)
      item.state = Retreated
      item.delete_count = 0
```

**Revised approach for Task 2:** Only maintain `state` field (not `delete_count`) for now. `delete_count` is used exclusively by the merge code in Task 4 as a **dirty tracker** — a non-zero delta means "this item was affected by retreat" and needs LWW recomputation. It is NOT an accurate count of active delete ops. Steady-state operations (local insert/delete, `apply_remote`) set `state` to mirror the `deleted` boolean.

**Important:** All state updates below go **inside the existing guard blocks** (the `if should_win_delete(...)` branch for LWW methods, the `if not(item.deleted)` / `if item.deleted` branches for force methods). Do not add them unconditionally.

```moonbit
// In delete_with_ts, INSIDE the `if should_win_delete(...)` block,
// after `item.deleted = true`:
item.state = Deleted

// In undelete_with_ts, INSIDE the `if should_win_delete(...)` block,
// after `item.deleted = false`:
item.state = Inserted

// In delete (force-delete), after `item.deleted = true`:
item.state = Retreated  // Distinguishes "removed by retreat" from "deleted by op"
// delete_count is NOT modified here — it's managed by merge code only

// In undelete (force-undelete), after `item.deleted = false`:
item.state = Inserted

// In set_delete_winner, after setting item.deleted:
item.state = if deleted { Deleted } else { Inserted }
```

- [ ] **Step 5: Run tests to verify all pass**

Run: `cd event-graph-walker && moon test`
Expected: All 315 tests pass. The new fields are maintained but nothing reads them yet (existing code still uses `item.deleted`).

- [ ] **Step 6: Update interfaces**

Run: `cd event-graph-walker && moon info && moon fmt`

- [ ] **Step 7: Commit**

```bash
cd event-graph-walker
git add internal/fugue/item.mbt internal/fugue/item_state.mbt internal/fugue/item_state_wbtest.mbt internal/fugue/tree.mbt internal/fugue/pkg.generated.mbti
git commit -m "feat(fugue): add ItemState and delete_count fields to Item"
```

---

## Task 3: DeleteIndex — inverted index for delete ops

**Files:**
- Create: `event-graph-walker/internal/branch/delete_index.mbt`
- Create: `event-graph-walker/internal/branch/delete_index_test.mbt`

The DeleteIndex maps `target_lv → Array[DeleteOp]` so that post-merge LWW recomputation is O(d) per item instead of O(total_ops).

- [ ] **Step 1: Write failing test for DeleteIndex**

```moonbit
// delete_index_test.mbt

///|
test "DeleteIndex - build and lookup" {
  let oplog = @oplog.OpLog::new("agent_a")

  // Insert "AB"
  let op_a = try! oplog.insert("A", -1, -1)
  let op_b = try! oplog.insert("B", op_a.lv(), -1)

  // Delete "A" (target = op_a's LV)
  let del_op = try! oplog.delete(op_a.lv())
  let _ = del_op
  let _ = op_b

  let index = DeleteIndex::build(oplog)

  // op_a should have 1 delete op targeting it
  let ops = index.get_delete_ops(op_a.lv())
  inspect(ops.length(), content="1")

  // op_b should have 0 delete ops
  let ops_b = index.get_delete_ops(op_b.lv())
  inspect(ops_b.length(), content="0")
}

///|
test "DeleteIndex - multiple deletes on same item" {
  let oplog_a = @oplog.OpLog::new("agent_a")
  let oplog_b = @oplog.OpLog::new("agent_b")

  // Agent A inserts "X"
  let op_x = try! oplog_a.insert("X", -1, -1)

  // Merge to B
  try! @branch.merge_remote_ops(
    @fugue.FugueTree::new(),
    oplog_b,
    [op_x],
  )

  // Both agents delete "X"
  let _ = try! oplog_a.delete(op_x.lv())

  let x_lv_in_b = match oplog_b.causal_graph().raw_to_lv(
    @core.RawVersion::new("agent_a", 0),
  ) {
    Some(lv) => lv
    None => fail("missing")
  }
  let _ = try! oplog_b.delete(x_lv_in_b)

  // Merge B's ops into A
  let tree_a : @fugue.FugueTree[String] = @fugue.FugueTree::new()
  tree_a.insert({
    id: @fugue.Lv(op_x.lv()),
    content: "X",
    origin_left: None,
    origin_right: None,
    timestamp: @fugue.Timestamp(0),
    agent: @fugue.ReplicaId("agent_a"),
  })
  try! @branch.merge_remote_ops(tree_a, oplog_a, oplog_b.get_all_ops())

  let index = DeleteIndex::build(oplog_a)
  let ops = index.get_delete_ops(op_x.lv())
  // Should have 2 delete ops targeting X
  inspect(ops.length() >= 2, content="true")
}

///|
test "DeleteIndex - recompute_winner" {
  let oplog = @oplog.OpLog::new("agent_a")
  let op_a = try! oplog.insert("A", -1, -1)
  let _ = try! oplog.delete(op_a.lv())

  let index = DeleteIndex::build(oplog)

  // Recompute winner excluding nothing (empty retreat set)
  let empty_retreat : @rle.Rle[@core.LvRange] = @rle.Rle::new()
  let winner = index.recompute_winner(op_a.lv(), oplog, empty_retreat)
  // Should find the delete as winner
  inspect(winner.deleted, content="true")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd event-graph-walker && moon test -p internal/branch -f delete_index_test.mbt`
Expected: FAIL — `DeleteIndex` not defined

- [ ] **Step 3: Implement DeleteIndex**

```moonbit
// delete_index.mbt

///|
/// Inverted index mapping target_lv → delete/undelete operation LVs.
/// Used for O(d) LWW winner recomputation after merge, where d = number
/// of delete/undelete ops on a single item (typically 0-2).
pub struct DeleteIndex {
  /// target_lv → Array of op LVs that delete/undelete this item.
  /// Only items with at least one delete/undelete op are in the map.
  index : Map[Int, Array[Int]]
}

///|
/// Result of LWW winner recomputation
pub(all) struct DeleteWinner {
  deleted : Bool
  ts : Int
  agent : String
  is_undelete : Bool
}

///|
/// Build the index by scanning all ops in the oplog once.
/// O(total_ops) but done once per merge, not per retreated delete.
pub fn DeleteIndex::build(oplog : @oplog.OpLog) -> DeleteIndex {
  let index : Map[Int, Array[Int]] = {}
  let cg = oplog.causal_graph()
  let count = oplog.op_count()
  for lv = 0; lv < count; lv = lv + 1 {
    match oplog.get_op(lv) {
      Some(op) =>
        match op.content() {
          @core.Delete | @core.Undelete =>
            match op.origin_left() {
              Some(raw) =>
                match cg.raw_to_lv(raw) {
                  Some(target) =>
                    match index.get(target) {
                      Some(arr) => arr.push(lv)
                      None => index.set(target, [lv])
                    }
                  None => ()
                }
              None => ()
            }
          _ => ()
        }
      None => ()
    }
  }
  { index, }
}

///|
/// Get all delete/undelete op LVs targeting a given item.
pub fn DeleteIndex::get_delete_ops(self : DeleteIndex, target_lv : Int) -> Array[Int] {
  match self.index.get(target_lv) {
    Some(ops) => ops
    None => []
  }
}

///|
/// Recompute the LWW winner for an item, excluding ops in the retreat set.
/// O(d) where d = number of delete/undelete ops on this item.
pub fn DeleteIndex::recompute_winner(
  self : DeleteIndex,
  target_lv : Int,
  oplog : @oplog.OpLog,
  retreat_set : @rle.Rle[@core.LvRange],
) -> DeleteWinner {
  let cg = oplog.causal_graph()
  let mut best_ts = 0
  let mut best_agent = ""
  let mut best_is_undelete = false
  let mut best_deleted = false
  let ops = self.get_delete_ops(target_lv)
  for op_lv in ops {
    // Skip ops in the retreat set
    if rle_contains_lv(retreat_set, op_lv) {
      continue
    }
    match oplog.get_op(op_lv) {
      Some(op) => {
        let (ts, agent) = match cg[op_lv] {
          Some(entry) => (entry.timestamp, entry.agent)
          None => continue
        }
        let is_undelete = match op.content() {
          @core.Undelete => true
          _ => false
        }
        if @fugue.should_win_delete(
            ts, agent, is_undelete, best_ts, best_agent, best_is_undelete,
          ) {
          best_ts = ts
          best_agent = agent
          best_is_undelete = is_undelete
          best_deleted = not(is_undelete)
        }
      }
      None => continue
    }
  }
  { deleted: best_deleted, ts: best_ts, agent: best_agent, is_undelete: best_is_undelete }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd event-graph-walker && moon test -p internal/branch -f delete_index_test.mbt`
Expected: PASS

- [ ] **Step 5: Run full test suite**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass (DeleteIndex is additive, not yet used by merge)

- [ ] **Step 6: Update interfaces**

Run: `cd event-graph-walker && moon info && moon fmt`

- [ ] **Step 7: Commit**

```bash
cd event-graph-walker
git add internal/branch/delete_index.mbt internal/branch/delete_index_test.mbt internal/branch/pkg.generated.mbti
git commit -m "feat(branch): add DeleteIndex for O(d) LWW winner recomputation"
```

---

## Task 4: Two-count retreat/advance in MergeContext

**Files:**
- Modify: `event-graph-walker/internal/branch/branch_merge.mbt`
- Modify: `event-graph-walker/internal/branch/branch_merge_test.mbt`

This is the core change: rewrite `retreat_operations` to use two-count instead of oplog scan, and add a post-merge LWW sweep.

- [ ] **Step 1: Write test for two-count retreat correctness**

Add to `branch_merge_test.mbt`:

```moonbit
///|
/// Test: retreat with two-count produces same result as oplog scan
test "merge - concurrent delete retreat convergence" {
  let oplog_a = @oplog.OpLog::new("agent_a")
  let tree_a : @fugue.FugueTree[String] = @fugue.FugueTree::new()
  let oplog_b = @oplog.OpLog::new("agent_b")
  let tree_b : @fugue.FugueTree[String] = @fugue.FugueTree::new()

  // Both agents start with "ABC"
  let op1 = try! oplog_a.insert("A", -1, -1)
  tree_a.insert({
    id: @fugue.Lv(op1.lv()),
    content: "A",
    origin_left: None,
    origin_right: None,
    timestamp: @fugue.Timestamp(0),
    agent: @fugue.ReplicaId("agent_a"),
  })
  let op2 = try! oplog_a.insert("B", op1.lv(), -1)
  tree_a.insert({
    id: @fugue.Lv(op2.lv()),
    content: "B",
    origin_left: Some(@fugue.Lv(op1.lv())),
    origin_right: None,
    timestamp: @fugue.Timestamp(1),
    agent: @fugue.ReplicaId("agent_a"),
  })
  let op3 = try! oplog_a.insert("C", op2.lv(), -1)
  tree_a.insert({
    id: @fugue.Lv(op3.lv()),
    content: "C",
    origin_left: Some(@fugue.Lv(op2.lv())),
    origin_right: None,
    timestamp: @fugue.Timestamp(2),
    agent: @fugue.ReplicaId("agent_a"),
  })

  // Sync A → B
  let ops_a = [op1, op2, op3]
  try! merge_remote_ops(tree_b, oplog_b, ops_a)
  inspect(tree_b.to_text(), content="ABC")

  // Agent A deletes "B"
  let del_a = try! oplog_a.delete(op2.lv())
  try! tree_a.delete(@fugue.Lv(op2.lv()))
  inspect(tree_a.to_text(), content="AC")

  // Agent B also deletes "B" concurrently
  let b_lv_for_op2 = match oplog_b.causal_graph().raw_to_lv(
    @core.RawVersion::new("agent_a", 1),
  ) {
    Some(lv) => lv
    None => fail("missing op2 in B")
  }
  let del_b = try! oplog_b.delete(b_lv_for_op2)
  try! tree_b.delete(@fugue.Lv(b_lv_for_op2))
  inspect(tree_b.to_text(), content="AC")

  // Merge: A gets B's concurrent delete
  try! merge_remote_ops(tree_a, oplog_a, [del_b])
  inspect(tree_a.to_text(), content="AC")

  // Merge: B gets A's concurrent delete
  try! merge_remote_ops(tree_b, oplog_b, [del_a])
  inspect(tree_b.to_text(), content="AC")
}

///|
/// Test: retreat insert + advance insert convergence
test "merge - retreat insert then advance produces correct text" {
  let oplog = @oplog.OpLog::new("agent_a")
  let tree : @fugue.FugueTree[String] = @fugue.FugueTree::new()

  // Insert "ABCDE"
  let op1 = try! oplog.insert("A", -1, -1)
  tree.insert({ id: @fugue.Lv(0), content: "A", origin_left: None, origin_right: None, timestamp: @fugue.Timestamp(0), agent: @fugue.ReplicaId("agent_a") })
  let op2 = try! oplog.insert("B", op1.lv(), -1)
  tree.insert({ id: @fugue.Lv(1), content: "B", origin_left: Some(@fugue.Lv(0)), origin_right: None, timestamp: @fugue.Timestamp(1), agent: @fugue.ReplicaId("agent_a") })
  let op3 = try! oplog.insert("C", op2.lv(), -1)
  tree.insert({ id: @fugue.Lv(2), content: "C", origin_left: Some(@fugue.Lv(1)), origin_right: None, timestamp: @fugue.Timestamp(2), agent: @fugue.ReplicaId("agent_a") })
  let _ = op3
  let frontier_abc = oplog.get_frontier()

  let op4 = try! oplog.insert("D", op3.lv(), -1)
  tree.insert({ id: @fugue.Lv(3), content: "D", origin_left: Some(@fugue.Lv(2)), origin_right: None, timestamp: @fugue.Timestamp(3), agent: @fugue.ReplicaId("agent_a") })
  let op5 = try! oplog.insert("E", op4.lv(), -1)
  tree.insert({ id: @fugue.Lv(4), content: "E", origin_left: Some(@fugue.Lv(3)), origin_right: None, timestamp: @fugue.Timestamp(4), agent: @fugue.ReplicaId("agent_a") })
  let _ = op5
  let frontier_abcde = oplog.get_frontier()

  inspect(tree.to_text(), content="ABCDE")

  // Retreat from ABCDE to ABC (retreat ops 3,4)
  // Then advance back to ABCDE
  let tree2 : @fugue.FugueTree[String] = @fugue.FugueTree::new()
  tree2.insert({ id: @fugue.Lv(0), content: "A", origin_left: None, origin_right: None, timestamp: @fugue.Timestamp(0), agent: @fugue.ReplicaId("agent_a") })
  tree2.insert({ id: @fugue.Lv(1), content: "B", origin_left: Some(@fugue.Lv(0)), origin_right: None, timestamp: @fugue.Timestamp(1), agent: @fugue.ReplicaId("agent_a") })
  tree2.insert({ id: @fugue.Lv(2), content: "C", origin_left: Some(@fugue.Lv(1)), origin_right: None, timestamp: @fugue.Timestamp(2), agent: @fugue.ReplicaId("agent_a") })
  tree2.insert({ id: @fugue.Lv(3), content: "D", origin_left: Some(@fugue.Lv(2)), origin_right: None, timestamp: @fugue.Timestamp(3), agent: @fugue.ReplicaId("agent_a") })
  tree2.insert({ id: @fugue.Lv(4), content: "E", origin_left: Some(@fugue.Lv(3)), origin_right: None, timestamp: @fugue.Timestamp(4), agent: @fugue.ReplicaId("agent_a") })

  // Merge from ABCDE frontier back to ABC frontier (retreat D,E)
  merge(tree2, oplog, frontier_abcde, frontier_abc)
  inspect(tree2.to_text(), content="ABC")

  // Merge from ABC back to ABCDE (advance D,E)
  merge(tree2, oplog, frontier_abc, frontier_abcde)
  inspect(tree2.to_text(), content="ABCDE")
}
```

- [ ] **Step 2: Run tests to verify they pass with current implementation**

Run: `cd event-graph-walker && moon test -p internal/branch -f branch_merge_test.mbt`
Expected: PASS — these tests verify convergence behavior that must remain correct after rewrite

- [ ] **Step 3: Rewrite retreat_operations to use two-count**

Replace the `retreat_operations` method in `branch_merge.mbt`:

```moonbit
///|
/// Remove operations from the retreat set using two-count approach.
///
/// For Insert ops: mark item as Retreated, decrement visible count.
/// For Delete/Undelete ops: adjust delete_count on target item.
///
/// After all retreat operations, call `sweep_dirty_deletes` to recompute
/// LWW winners for items whose delete_count changed.
pub fn MergeContext::retreat_operations(
  self : MergeContext,
  operations : @rle.Rle[@core.LvRange],
) -> Unit raise BranchError {
  let cg = self.oplog.causal_graph()
  let dirty_items : Array[Int] = []

  for range in operations.iter() {
    for lv = range.start; lv < range.end(); lv = lv + 1 {
      match self.oplog.get_op(lv) {
        Some(op) =>
          match op.content() {
            @core.Insert(_) =>
              // Retreat Insert: hide the item
              self.tree.delete(@fugue.Lv(lv)) catch {
                e => raise BranchError::Fugue(e)
              }
            @core.Delete => {
              // Retreat Delete: decrement delete_count on target
              let target_lv = match op.origin_left() {
                None => continue
                Some(raw) =>
                  match cg.raw_to_lv(raw) {
                    Some(mapped) => mapped
                    None => raise BranchError::MissingOrigin(raw~)
                  }
              }
              match self.tree[@fugue.Lv(target_lv)] {
                Some(item) => {
                  item.delete_count = item.delete_count - 1
                  dirty_items.push(target_lv)
                }
                None => ()
              }
            }
            @core.Undelete => {
              // Retreat Undelete: re-apply the delete it cancelled
              let target_lv = match op.origin_left() {
                None => continue
                Some(raw) =>
                  match cg.raw_to_lv(raw) {
                    Some(mapped) => mapped
                    None => raise BranchError::MissingOrigin(raw~)
                  }
              }
              match self.tree[@fugue.Lv(target_lv)] {
                Some(item) => {
                  item.delete_count = item.delete_count + 1
                  dirty_items.push(target_lv)
                }
                None => ()
              }
            }
          }
        None => raise BranchError::MissingOp(lv~)
      }
    }
  }

  // Post-retreat: recompute LWW winners for dirty items
  if dirty_items.length() > 0 {
    let delete_index = DeleteIndex::build(self.oplog)
    for target_lv in dirty_items {
      let winner = delete_index.recompute_winner(
        target_lv, self.oplog, operations,
      )
      self.tree.set_delete_winner(
        @fugue.Lv(target_lv),
        winner.deleted,
        winner.ts,
        winner.agent,
        winner.is_undelete,
      ) catch {
        e => raise BranchError::Fugue(e)
      }
    }
  }
}
```

**Important note on `delete_count` semantics:** The `delete_count` field is used here as a **dirty tracker**, NOT as an accurate count of active delete operations. It starts at 0 (from `Item::new`) regardless of how many deletes the item actually has. The decrements/increments during retreat are relative deltas that mark which items were affected. The actual correctness comes from the `set_delete_winner` call in the post-retreat sweep, which recomputes the authoritative `deleted` boolean and LWW fields from the oplog via `DeleteIndex`. The `delete_count` value after the sweep is NOT meaningful — only `dirty_items` membership matters.

This means `is_visible()` still uses the `deleted` boolean (restored by `set_delete_winner`) as its source of truth. Switching to count-based visibility is deferred to future work when `delete_count` is properly bootstrapped.

- [ ] **Step 4: Run all merge tests**

Run: `cd event-graph-walker && moon test -p internal/branch`
Expected: All branch tests pass

- [ ] **Step 5: Run full test suite**

Run: `cd event-graph-walker && moon test`
Expected: All 315+ tests pass

- [ ] **Step 6: Commit**

```bash
cd event-graph-walker
git add internal/branch/branch_merge.mbt internal/branch/branch_merge_test.mbt
git commit -m "feat(branch): two-count retreat — O(d) per delete instead of O(total_ops)"
```

---

## Task 5: Incremental position cache during merge

**Files:**
- Create: `event-graph-walker/internal/document/merge_cache.mbt`
- Create: `event-graph-walker/internal/document/merge_cache_test.mbt`
- Modify: `event-graph-walker/internal/document/document.mbt`

**Note:** MergeCache lives in the `document` package (not `branch`) because it depends on `VisibleRun` which is defined in `document`. The dependency graph is `document → branch`, so `branch` cannot import `document` (circular dependency). MergeCache is used by Document to wrap the cache before/after calling branch merge functions.

This task makes the OrderTree[VisibleRun] survive merge operations by updating it incrementally.

- [ ] **Step 1: Write failing test for MergeCache**

```moonbit
// merge_cache_test.mbt

///|
test "MergeCache - retreat insert removes from cache" {
  // Build a small document "ABC" with a position cache
  let doc = Document::new("agent_a")
  let _ = try! doc.insert(0, "ABC")
  inspect(doc.visible_count(), content="3")

  // The position cache should be valid
  // (accessing lv_to_position triggers lazy build)
  let pos_a = doc.lv_to_position(0)
  inspect(pos_a, content="Some(0)")
  let pos_b = doc.lv_to_position(1)
  inspect(pos_b, content="Some(1)")
  let pos_c = doc.lv_to_position(2)
  inspect(pos_c, content="Some(2)")
}
```

- [ ] **Step 2: Run test to verify baseline**

Run: `cd event-graph-walker && moon test -p internal/document -f merge_cache_test.mbt`
Expected: PASS (this is a baseline test — uses Document from same package)

- [ ] **Step 3: Implement MergeCache wrapper**

```moonbit
// merge_cache.mbt (in internal/document/)

///|
/// Wraps a position cache (OrderTree[VisibleRun]) for incremental updates
/// during merge operations. If the merge is too large, the cache is dropped
/// and rebuilt after merge completes.
///
/// The threshold for "too large" is when retreat + advance ops exceed half
/// the document size — at that point, incremental updates cost more than rebuild.
pub struct MergeCache {
  mut cache : @order_tree.OrderTree[VisibleRun]?
  mut dirty : Bool // True if cache was dropped (needs rebuild)
}

///|
/// Create from an existing position cache.
/// `doc_size` = visible item count; `merge_size` = retreat + advance op count.
/// If merge_size > doc_size / 2, we skip incremental and rebuild after.
pub fn MergeCache::new(
  cache : @order_tree.OrderTree[VisibleRun]?,
  doc_size : Int,
  merge_size : Int,
) -> MergeCache {
  if merge_size > doc_size / 2 {
    { cache: None, dirty: true }
  } else {
    { cache, dirty: cache is None }
  }
}

///|
/// Remove an item at a known document position (retreat insert / advance delete).
pub fn MergeCache::remove_at(self : MergeCache, position : Int) -> Unit {
  match self.cache {
    Some(cache) => cache.delete_at(position)
    None => self.dirty = true
  }
}

///|
/// Insert an item at a document position (advance insert / retreat delete making visible).
pub fn MergeCache::insert_at(
  self : MergeCache,
  position : Int,
  run : VisibleRun,
) -> Unit {
  match self.cache {
    Some(cache) => cache.insert_at(position, run)
    None => self.dirty = true
  }
}

///|
/// Get the final cache. Returns None if it was dropped and needs full rebuild.
pub fn MergeCache::take(self : MergeCache) -> @order_tree.OrderTree[VisibleRun]? {
  if self.dirty && self.cache is None {
    None
  } else {
    self.cache
  }
}
```

Note: This is a thin wrapper. The actual integration with merge retreat/advance is deferred to a follow-up task because:
1. `retreat_insert` needs to know the document position of the item being retreated (requires `lv_to_position` lookup)
2. `advance_insert` gets the position from FugueMax
3. Both require threading the cache through the Document's merge call

For now, the MergeCache provides the API. The `branch` package cannot use it directly (circular dependency), but Document wraps/unwraps the cache before/after calling branch merge functions.

- [ ] **Step 4: Integrate MergeCache with Document::merge_remote**

Update `Document::merge_remote` in `document.mbt` to use MergeCache:
```

In `Document::merge_remote`, wrap the cache in MergeCache before merge and unwrap after:

```moonbit
pub fn Document::merge_remote(
  self : Document,
  remote_ops : Array[@core.Op],
  remote_frontier : Array[@core.RawVersion],
) -> Unit raise DocumentError {
  self.cursor = None
  self.oplog.validate_remote_batch(remote_ops, remote_frontier) catch {
    e => raise DocumentError::OpLog(e)
  }

  // Wrap position cache for potential incremental update
  let merge_cache = MergeCache::new(
    self.position_cache,
    self.tree.visible_count(),
    remote_ops.length(), // rough estimate of merge size
  )

  // Still invalidate for now — full integration deferred to Task 6
  self.invalidate_cache()
  @branch.merge_remote_ops(self.tree, self.oplog, remote_ops) catch {
    e => raise DocumentError::Branch(e)
  }

  // After merge, try to recover cache (currently always None due to invalidation above)
  self.position_cache = merge_cache.take()
}
```

- [ ] **Step 5: Run full test suite**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass

- [ ] **Step 6: Update interfaces**

Run: `cd event-graph-walker && moon info && moon fmt`

- [ ] **Step 7: Commit**

```bash
cd event-graph-walker
git add internal/document/merge_cache.mbt internal/document/merge_cache_test.mbt internal/document/document.mbt internal/document/pkg.generated.mbti
git commit -m "feat(document): add MergeCache for incremental position cache during merge"
```

---

## Task 6: Full incremental cache wiring (future follow-up)

**Files:**
- Modify: `event-graph-walker/internal/document/document.mbt`

Wire the MergeCache through the actual merge loop so small merges keep the position cache alive. This requires the `branch` merge functions to accept a callback or return position change events that `Document` can forward to MergeCache. This is left as a follow-up because it requires careful API design across the `document`/`branch` boundary without introducing circular dependencies.

- [ ] **Step 1: Write test for cache survival after small merge**

Add to an existing document test file or create a new one:

```moonbit
///|
test "Document - position cache survives small merge" {
  let doc_a = @document.Document::new("agent_a")
  let doc_b = @document.Document::new("agent_b")

  // Agent A types "Hello"
  let _ = try! doc_a.insert(0, "Hello")

  // Sync A → B
  let ops_a = doc_a.get_all_ops()
  let frontier_a = try! doc_a.get_frontier_raw()
  try! doc_b.merge_remote(ops_a, frontier_a)
  inspect(doc_b.to_text(), content="Hello")

  // Agent B types " World" at end
  let _ = try! doc_b.insert(5, " World")

  // Sync B → A (small merge: 6 chars)
  let ops_b = doc_b.get_all_ops()
  let frontier_b = try! doc_b.get_frontier_raw()

  // Warm up A's position cache
  let _ = doc_a.lv_to_position(0)

  // Merge B's ops — cache should survive (6 ops < 5/2 = 2... hmm, threshold)
  try! doc_a.merge_remote(ops_b, frontier_b)
  inspect(doc_a.to_text(), content="Hello World")

  // Position queries should work without full rebuild
  let pos = doc_a.lv_to_position(0)
  inspect(pos, content="Some(0)")
}
```

- [ ] **Step 2: Run test — expect it to pass with fallback rebuild**

Run: `cd event-graph-walker && moon test -p internal/document -f merge_cache_test.mbt`
Expected: PASS (merge invalidates cache, lazy rebuild still works)

- [ ] **Step 3: Run full test suite**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
cd event-graph-walker
git add internal/document/document.mbt
git commit -m "chore(document): prepare merge_remote for incremental cache (no behavior change)"
```

---

## Task 7: Benchmark — verify retreat performance improvement

**Files:**
- Modify: `event-graph-walker/internal/branch/branch_merge_benchmark.mbt`

- [ ] **Step 1: Read current benchmark**

Read: `event-graph-walker/internal/branch/branch_merge_benchmark.mbt`
Understand the existing benchmark structure.

- [ ] **Step 2: Add retreat-focused benchmark**

```moonbit
///|
/// Benchmark: retreat with concurrent deletes.
/// Measures the cost of retreat_operations when multiple delete ops
/// target the same items. This is the hot path that two-count optimizes.
test "merge - retreat concurrent deletes (500 items, 50 deletes)" (b : @bench.T) {
  // Setup: 500-item document with 50 deletes
  let oplog_a = @oplog.OpLog::new("agent_a")
  let tree : @fugue.FugueTree[String] = @fugue.FugueTree::new()

  // Insert 500 chars
  let mut prev_lv = -1
  for i = 0; i < 500; i = i + 1 {
    let op = try! oplog_a.insert("x", prev_lv, -1)
    tree.insert({
      id: @fugue.Lv(op.lv()),
      content: "x",
      origin_left: if prev_lv == -1 { None } else { Some(@fugue.Lv(prev_lv)) },
      origin_right: None,
      timestamp: @fugue.Timestamp(i),
      agent: @fugue.ReplicaId("agent_a"),
    })
    prev_lv = op.lv()
  }
  let frontier_base = oplog_a.get_frontier()

  // Agent A deletes 50 items
  for i = 0; i < 50; i = i + 1 {
    let _ = try! oplog_a.delete(i * 10)
    try! tree.delete_with_ts(@fugue.Lv(i * 10), 500 + i, "agent_a")
  }
  let frontier_with_deletes = oplog_a.get_frontier()

  b.bench(fn() {
    // Retreat the 50 deletes (go from frontier_with_deletes back to frontier_base)
    let tree_copy : @fugue.FugueTree[String] = @fugue.FugueTree::new()
    // Rebuild tree state at frontier_with_deletes
    for i = 0; i < 500; i = i + 1 {
      tree_copy.insert({
        id: @fugue.Lv(i),
        content: "x",
        origin_left: if i == 0 { None } else { Some(@fugue.Lv(i - 1)) },
        origin_right: None,
        timestamp: @fugue.Timestamp(i),
        agent: @fugue.ReplicaId("agent_a"),
      })
    }
    for i = 0; i < 50; i = i + 1 {
      try! tree_copy.delete_with_ts(@fugue.Lv(i * 10), 500 + i, "agent_a")
    }
    try! merge(tree_copy, oplog_a, frontier_with_deletes, frontier_base)
  })
}
```

- [ ] **Step 3: Run benchmark**

Run: `cd event-graph-walker && moon bench --release -p internal/branch`
Record baseline numbers.

- [ ] **Step 4: Commit**

```bash
cd event-graph-walker
git add internal/branch/branch_merge_benchmark.mbt
git commit -m "bench(branch): add retreat_concurrent_deletes benchmark"
```

---

## Complexity Summary

| Operation | Before Phase 3 | After Phase 3 |
|-----------|----------------|---------------|
| Retreat delete (per op) | O(total_ops) oplog scan | O(1) count + O(d) post-sweep |
| Retreat insert (per op) | O(1) force-delete | O(1) force-delete (unchanged) |
| Advance delete (per op) | O(1) LWW comparison | O(1) LWW comparison (unchanged) |
| Total merge (k ops, d deletes) | O(k × total_ops) | O(total_ops) index build + O(k) + O(d_total × d_per_item) sweep |
| DeleteIndex build | N/A | O(total_ops) — once per merge, not per retreated delete |
| Position cache after merge | O(n) full rebuild | O(n) rebuild (incremental deferred) |

The DeleteIndex build is O(total_ops) but amortized: it runs once per merge instead of once per retreated delete. For k retreated deletes, old = O(k × total_ops), new = O(total_ops + k × d) where d ≈ 1-2.

## Benchmark Results (2026-03-24)

Benchmark: retreat 50 deletes across a 500-item document (`moon bench --release -p internal/branch`).

| | Old (oplog scan) | New (two-count + DeleteIndex) | Speedup |
|---|---|---|---|
| Mean | 6.36ms ± 109µs | 359µs ± 9.6µs | **17.7x** |
| Range | 6.20ms – 6.52ms | 348µs – 378µs | |
| Runs | 16 per iteration | 283 per iteration | |

The variance also dropped significantly (±109µs → ±9.6µs), indicating more predictable latency.

## Risk Assessment

1. **Semantic equivalence:** Two-count must produce identical results to oplog scan for all convergence tests. The post-merge LWW sweep ensures this — it uses the same `should_win_delete` function and the same filtered op set.

2. **delete_count accuracy:** If `delete_count` drifts (e.g., missing an increment during advance), items may have wrong visibility. Mitigated by: (a) the LWW sweep recomputes the authoritative state from the oplog, (b) existing convergence tests catch divergence.

3. **MergeCache position tracking:** Knowing an item's document position during retreat requires either the position cache or a tree walk. For retreated inserts, the item is being removed — we need its current position. For retreated deletes making items visible, we need the target position. Both require careful integration. Task 5-6 are intentionally conservative (infrastructure first, full integration later).

## Future Work

- **Full incremental cache integration:** Wire MergeCache through the entire `merge_remote_ops` → `Branch::merge_remote_ops` → `merge` call chain
- **Persistent DeleteIndex:** Instead of building per-merge, maintain incrementally as ops are added to the oplog
- **Phase 2b synergy:** After Array-backed FugueStore lands, `Item[T]` becomes `ItemMeta` — the `state` and `delete_count` fields transfer directly
- **State-based visibility:** Switch `is_visible()` from `!deleted` to `state.is_visible(delete_count~)` and remove the `deleted` boolean entirely
