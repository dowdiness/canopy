# LWW Delete/Undelete Conflict Resolution Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make concurrent Delete/Undelete operations convergent using Last-Writer-Wins with Lamport timestamps, fixing the divergence bug found by fuzz testing.

**Architecture:** Add an explicit winner record (`deleted_ts`, `deleted_agent`, `deleted_is_undelete`) to the FugueTree Item. New convergent `delete_with_ts`/`undelete_with_ts` methods compare Lamport timestamps and only apply if the new op "wins". ALL mutation paths (local, remote, advance, retreat) maintain this record. The winning rule: higher timestamp wins; for ties, Undelete wins (add-wins); for same type ties, higher agent ID wins. For retreat, the winner is recomputed from the oplog by scanning for all Delete/Undelete ops on the target item that remain in the common ancestor.

**Tech Stack:** MoonBit, event-graph-walker submodule

**Spec:** Root cause: `FugueTree::delete`/`undelete` are non-commutative boolean setters. Concurrent Delete+Undelete diverge because last-applied wins and replicas apply in different orders.

**Key code path insight:** `Branch::advance` (branch.mbt:93) already falls back to full checkout when retreat is needed. The incremental retreat in `branch_merge.mbt::merge()` is a separate, less-used path. The primary bug manifests in `Document::apply_remote` (the common sync path).

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `internal/fugue/item.mbt` | Add `deleted_ts`, `deleted_agent`, `deleted_is_undelete` fields |
| Modify | `internal/fugue/tree.mbt` | Add `delete_with_ts`, `undelete_with_ts`, `set_delete_winner`; update existing `delete`/`undelete` to maintain winner |
| Modify | `internal/document/document.mbt` | Use convergent methods in `apply_remote`, `delete`, `delete_range`, `undelete`, `delete_by_lv` |
| Modify | `internal/branch/branch.mbt` | Use convergent methods in `apply_operation_to_tree` |
| Modify | `internal/branch/branch_merge.mbt` | Fix `retreat_operations` (recompute winner from oplog); use convergent methods in `apply_operations` |
| Modify | `text/debug_convergence_test.mbt` | Add proper convergence assertions |
| Modify | `text/text_convergence_fuzz_test.mbt` | Re-enable full multi-agent convergence property with undo |
| Update | `internal/fugue/pkg.generated.mbti` | `moon info` regeneration |

---

### Task 1: Add explicit winner record to Item

**Files:**
- Modify: `internal/fugue/item.mbt`

- [ ] **Step 1: Add winner fields to Item struct**

In `internal/fugue/item.mbt` (around line 31), add three fields after `deleted`:

```moonbit
pub(all) struct Item[T] {
  id : Lv
  content : T
  parent : Lv?
  side : Side
  deleted : Bool
  deleted_ts : Int             // Lamport timestamp of winning Delete/Undelete op (0 = initial)
  deleted_agent : String       // Agent ID of winning op ("" = initial)
  deleted_is_undelete : Bool   // true if winner was Undelete, false if Delete or initial
  timestamp : Timestamp
  agent : ReplicaId
}
```

- [ ] **Step 2: Update `Item::new` to initialize winner fields**

```moonbit
pub fn Item::new[T](
  id : Lv,
  content : T,
  parent : Lv?,
  side : Side,
  timestamp : Timestamp,
  agent : ReplicaId,
) -> Item[T] {
  {
    id,
    content,
    parent,
    side,
    deleted: false,
    deleted_ts: 0,
    deleted_agent: "",
    deleted_is_undelete: false,
    timestamp,
    agent,
  }
}
```

- [ ] **Step 3: Verify `mark_deleted`/`mark_visible` preserve winner fields**

Both use `{ ..self, deleted: ... }` struct spread, which preserves new fields. Read and confirm.

- [ ] **Step 4: Run `moon check`, fix any compile errors**

Run: `cd event-graph-walker && moon check`

If any code constructs Item literals directly (unlikely outside item.mbt), add the new fields with defaults.

- [ ] **Step 5: Run tests**

Run: `cd event-graph-walker && moon test`
Expected: All pass (fields added but not yet used for decisions).

- [ ] **Step 6: Commit**

```bash
cd event-graph-walker
git add internal/fugue/item.mbt
git commit -m "feat(fugue): add explicit LWW winner record to Item

Add deleted_ts, deleted_agent, deleted_is_undelete to track which
operation determined the current deleted state. Enables deterministic
conflict resolution for concurrent Delete/Undelete operations."
```

---

### Task 2: Add convergent methods + update force methods on FugueTree

**Files:**
- Modify: `internal/fugue/tree.mbt`
- Modify: `internal/fugue/tree_test.mbt`

- [ ] **Step 1: Write failing tests**

In `internal/fugue/tree_test.mbt`:

```moonbit
///|
test "delete_with_ts: higher timestamp wins" {
  let tree = @fugue.FugueTree::new()
  let lv = @fugue.Lv(0)
  tree.insert({
    id: lv, content: "x", origin_left: None, origin_right: None,
    timestamp: @fugue.Timestamp(1), agent: @fugue.ReplicaId("alice"),
  })
  try! tree.delete_with_ts(lv, 2, "alice")
  inspect(tree.visible_count(), content="0")
  // Undelete with ts=3 wins
  try! tree.undelete_with_ts(lv, 3, "bob")
  inspect(tree.visible_count(), content="1")
  // Delete with ts=1 loses
  try! tree.delete_with_ts(lv, 1, "charlie")
  inspect(tree.visible_count(), content="1")
}

///|
test "delete_with_ts: add-wins at same timestamp" {
  let tree = @fugue.FugueTree::new()
  let lv = @fugue.Lv(0)
  tree.insert({
    id: lv, content: "x", origin_left: None, origin_right: None,
    timestamp: @fugue.Timestamp(1), agent: @fugue.ReplicaId("alice"),
  })
  try! tree.delete_with_ts(lv, 5, "alice")
  inspect(tree.visible_count(), content="0")
  // Undelete at same ts=5 wins (add-wins)
  try! tree.undelete_with_ts(lv, 5, "bob")
  inspect(tree.visible_count(), content="1")
  // Delete at same ts=5 cannot override undelete (add-wins)
  try! tree.delete_with_ts(lv, 5, "zack")
  inspect(tree.visible_count(), content="1")
}

///|
test "delete_with_ts: commutativity" {
  let make_tree = fn() {
    let tree = @fugue.FugueTree::new()
    tree.insert({
      id: @fugue.Lv(0), content: "x", origin_left: None, origin_right: None,
      timestamp: @fugue.Timestamp(1), agent: @fugue.ReplicaId("alice"),
    })
    tree
  }
  let lv = @fugue.Lv(0)
  // Order 1: delete(ts=3) then undelete(ts=2)
  let t1 = make_tree()
  try! t1.delete_with_ts(lv, 3, "alice")
  try! t1.undelete_with_ts(lv, 2, "bob")
  // Order 2: undelete(ts=2) then delete(ts=3)
  let t2 = make_tree()
  try! t2.undelete_with_ts(lv, 2, "bob")
  try! t2.delete_with_ts(lv, 3, "alice")
  // Both agree: delete at ts=3 wins
  inspect(t1.visible_count(), content="0")
  inspect(t2.visible_count(), content="0")
}

///|
test "set_delete_winner: restores winner state" {
  let tree = @fugue.FugueTree::new()
  let lv = @fugue.Lv(0)
  tree.insert({
    id: lv, content: "x", origin_left: None, origin_right: None,
    timestamp: @fugue.Timestamp(1), agent: @fugue.ReplicaId("alice"),
  })
  // Set winner to Delete(ts=5, alice)
  try! tree.set_delete_winner(lv, true, 5, "alice", false)
  inspect(tree.visible_count(), content="0")
  // Set winner to Undelete(ts=3, bob)
  try! tree.set_delete_winner(lv, false, 3, "bob", true)
  inspect(tree.visible_count(), content="1")
  // Set winner to initial (no op)
  try! tree.set_delete_winner(lv, false, 0, "", false)
  inspect(tree.visible_count(), content="1") // item starts visible
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/fugue`
Expected: FAIL — methods not defined.

- [ ] **Step 3: Implement `should_win_delete`**

```moonbit
///|
/// LWW comparison for Delete/Undelete conflict resolution.
/// Returns true if the new op wins over the current winner.
///
/// Rule: higher timestamp wins. Same timestamp: Undelete beats Delete (add-wins).
/// Same timestamp and type: higher agent ID wins.
fn should_win_delete(
  new_ts : Int,
  new_agent : String,
  new_is_undelete : Bool,
  cur_ts : Int,
  cur_agent : String,
  cur_is_undelete : Bool,
) -> Bool {
  if cur_ts == 0 && cur_agent == "" {
    return true // No previous winner, always apply
  }
  if new_ts != cur_ts {
    return new_ts > cur_ts
  }
  // Same timestamp: Undelete beats Delete (add-wins)
  if new_is_undelete != cur_is_undelete {
    return new_is_undelete
  }
  // Same timestamp, same type: agent tiebreaker
  new_agent > cur_agent
}
```

- [ ] **Step 4: Implement convergent `delete_with_ts` and `undelete_with_ts`**

```moonbit
///|
/// Convergent delete: only applies if this op wins the LWW comparison.
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
      if should_win_delete(ts, agent, false, item.deleted_ts, item.deleted_agent, item.deleted_is_undelete) {
        if not(item.deleted) {
          self.visible = self.visible - 1
        }
        self.items = self.items.add(
          id,
          { ..item, deleted: true, deleted_ts: ts, deleted_agent: agent, deleted_is_undelete: false },
        )
      }
    None => raise FugueError::MissingItem(id~)
  }
}

///|
/// Convergent undelete: only applies if this op wins the LWW comparison.
pub fn[T] FugueTree::undelete_with_ts(
  self : FugueTree[T],
  id : Lv,
  ts : Int,
  agent : String,
) -> Unit raise FugueError {
  match self[id] {
    Some(item) =>
      if should_win_delete(ts, agent, true, item.deleted_ts, item.deleted_agent, item.deleted_is_undelete) {
        if item.deleted {
          self.visible = self.visible + 1
        }
        self.items = self.items.add(
          id,
          { ..item, deleted: false, deleted_ts: ts, deleted_agent: agent, deleted_is_undelete: true },
        )
      }
    None => raise FugueError::MissingItem(id~)
  }
}
```

- [ ] **Step 5: Implement `set_delete_winner` (force-set winner state)**

Used by retreat to restore a computed winner without LWW comparison:

```moonbit
///|
/// Force-set the delete winner state. Used by retreat to restore a recomputed winner.
/// No LWW comparison — directly sets the state.
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
      self.items = self.items.add(
        id,
        { ..item, deleted, deleted_ts: ts, deleted_agent: agent, deleted_is_undelete: is_undelete },
      )
    }
    None => raise FugueError::MissingItem(id~)
  }
}
```

- [ ] **Step 6: Update existing `delete` and `undelete` to maintain winner record**

The existing force methods must also update the winner record to keep the invariant. They are used by local edits (via Document) and retreat of Insert ops. Update them to accept ts/agent:

**If MoonBit supports labelled optional params** (it does — see `UndoManager::new` with `capture_timeout_ms?`):

```moonbit
///|
pub fn[T] FugueTree::delete(
  self : FugueTree[T],
  id : Lv,
  ts~ : Int = 0,
  agent~ : String = "",
) -> Unit raise FugueError {
  if id == root_lv {
    return
  }
  match self[id] {
    Some(item) => {
      if not(item.deleted) {
        self.visible = self.visible - 1
      }
      self.items = self.items.add(
        id,
        { ..item, deleted: true, deleted_ts: ts, deleted_agent: agent, deleted_is_undelete: false },
      )
    }
    None => raise FugueError::MissingItem(id~)
  }
}

///|
pub fn[T] FugueTree::undelete(
  self : FugueTree[T],
  id : Lv,
  ts~ : Int = 0,
  agent~ : String = "",
) -> Unit raise FugueError {
  match self[id] {
    Some(item) =>
      if item.deleted {
        self.visible = self.visible + 1
        self.items = self.items.add(
          id,
          { ..item, deleted: false, deleted_ts: ts, deleted_agent: agent, deleted_is_undelete: true },
        )
      }
    None => raise FugueError::MissingItem(id~)
  }
}
```

**If optional params don't work** on generic methods, keep existing signatures unchanged but update the method body to set `deleted_ts: 0, deleted_agent: "", deleted_is_undelete: false/true`. Callers that need to pass ts/agent use the convergent or `set_delete_winner` methods instead.

- [ ] **Step 7: Run tests**

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/fugue`
Expected: All pass.

- [ ] **Step 8: Commit**

```bash
cd event-graph-walker
git add internal/fugue/tree.mbt internal/fugue/tree_test.mbt
git commit -m "feat(fugue): add convergent delete_with_ts/undelete_with_ts + set_delete_winner

LWW comparison: higher Lamport timestamp wins. Same timestamp: Undelete
wins (add-wins). Same type+timestamp: higher agent wins.
set_delete_winner force-sets state for retreat recomputation.
Existing delete/undelete updated to maintain winner record."
```

---

### Task 3: Wire convergent methods into Document

**Files:**
- Modify: `internal/document/document.mbt`

All callers of `tree.delete`/`tree.undelete` in Document must use convergent methods. The Lamport timestamp for each op is obtained from `cg[op.lv()]` where `cg = self.oplog.causal_graph()`.

- [ ] **Step 1: Update `apply_remote` (around line 322)**

Change Delete/Undelete cases from `self.tree.delete(lv)` to `self.tree.delete_with_ts(lv, ts, agent)`:

```moonbit
@core.Delete =>
  match origin_left {
    Some(lv) => {
      let (del_ts, del_agent) = match cg[applied.lv()] {
        Some(entry) => (entry.timestamp, entry.agent)
        None =>
          raise DocumentError::OpLog(
            @oplog.OpLogError::MissingLocalVersion(lv=applied.lv()),
          )
      }
      self.tree.delete_with_ts(lv, del_ts, del_agent) catch {
        e => raise DocumentError::Fugue(e)
      }
    }
    None => ()
  }
@core.Undelete =>
  match origin_left {
    Some(lv) => {
      let (undel_ts, undel_agent) = match cg[applied.lv()] {
        Some(entry) => (entry.timestamp, entry.agent)
        None =>
          raise DocumentError::OpLog(
            @oplog.OpLogError::MissingLocalVersion(lv=applied.lv()),
          )
      }
      self.tree.undelete_with_ts(lv, undel_ts, undel_agent) catch {
        e => raise DocumentError::Fugue(e)
      }
    }
    None => ()
  }
```

- [ ] **Step 2: Update `Document::delete` (around line 225)**

After creating the op via `self.oplog.delete(...)`, look up its Lamport timestamp and use the convergent method. Local ops always have the highest clock and will always win:

```moonbit
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
```

- [ ] **Step 3: Update `Document::delete_range` (around line 265)**

Same pattern — each delete op in the range needs its own timestamp lookup and convergent call.

- [ ] **Step 4: Update `Document::undelete` (around line 289)**

Same pattern with `undelete_with_ts`.

- [ ] **Step 5: Update `Document::delete_by_lv` (around line 313)**

Called by the undo system. Same pattern with `delete_with_ts`.

- [ ] **Step 6: Run convergence debug test**

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/text -f debug_convergence_test.mbt`
Expected: Both tests show convergence.

- [ ] **Step 7: Run full test suite**

Run: `cd event-graph-walker && moon test`
Expected: All pass.

- [ ] **Step 8: Commit**

```bash
cd event-graph-walker
git add internal/document/document.mbt
git commit -m "fix(document): use convergent delete/undelete with Lamport timestamps

All delete/undelete paths in Document now use delete_with_ts/
undelete_with_ts. Covers: apply_remote, delete, delete_range,
undelete, delete_by_lv. Concurrent Delete/Undelete now converge."
```

---

### Task 4: Fix branch.mbt and branch_merge.mbt

**Files:**
- Modify: `internal/branch/branch.mbt`
- Modify: `internal/branch/branch_merge.mbt`

**Context:** `Branch::advance` (branch.mbt:93) already falls back to full `checkout` when retreat is needed. So `apply_operation_to_tree` is only used for forward-only advance. The incremental retreat in `branch_merge.mbt::merge()` is a separate path.

- [ ] **Step 1: Update `apply_operation_to_tree` in `branch.mbt` (around line 249)**

This function takes `(tree, op, cg)` as params (not `self`). Update Delete/Undelete cases:

```moonbit
@core.Delete =>
  match origin_left {
    Some(lv) => {
      let (del_ts, del_agent) = match cg[op.lv()] {
        Some(entry) => (entry.timestamp, entry.agent)
        None => raise BranchError::MissingOp(lv=op.lv())
      }
      tree.delete_with_ts(lv, del_ts, del_agent) catch {
        e => raise BranchError::Fugue(e)
      }
    }
    None => ()
  }
@core.Undelete =>
  match origin_left {
    Some(lv) => {
      let (undel_ts, undel_agent) = match cg[op.lv()] {
        Some(entry) => (entry.timestamp, entry.agent)
        None => raise BranchError::MissingOp(lv=op.lv())
      }
      tree.undelete_with_ts(lv, undel_ts, undel_agent) catch {
        e => raise BranchError::Fugue(e)
      }
    }
    None => ()
  }
```

- [ ] **Step 2: Update `apply_operations` in `branch_merge.mbt` (around line 27)**

Same pattern — use convergent methods with Lamport timestamps. The `cg` variable is already defined at line 35:

```moonbit
@core.Delete =>
  match op.origin_left() {
    None => ()
    Some(raw) =>
      match cg.raw_to_lv(raw) {
        Some(mapped) => {
          let (del_ts, del_agent) = match cg[lv] {
            Some(entry) => (entry.timestamp, entry.agent)
            None => raise BranchError::MissingOp(lv~)
          }
          self.tree.delete_with_ts(@fugue.Lv(mapped), del_ts, del_agent) catch {
            e => raise BranchError::Fugue(e)
          }
        }
        None => raise BranchError::MissingOrigin(raw~)
      }
  }
@core.Undelete =>
  match op.origin_left() {
    None => ()
    Some(raw) =>
      match cg.raw_to_lv(raw) {
        Some(mapped) => {
          let (undel_ts, undel_agent) = match cg[lv] {
            Some(entry) => (entry.timestamp, entry.agent)
            None => raise BranchError::MissingOp(lv~)
          }
          self.tree.undelete_with_ts(@fugue.Lv(mapped), undel_ts, undel_agent) catch {
            e => raise BranchError::Fugue(e)
          }
        }
        None => raise BranchError::MissingOrigin(raw~)
      }
  }
```

- [ ] **Step 3: Fix `retreat_operations` — recompute winner from oplog**

Replace the current blind `tree.delete(Lv(lv))` with correct retreat logic. For Delete/Undelete ops, recompute the winner among all ops targeting the same item that remain in the common ancestor (i.e., NOT in the retreat set):

```moonbit
pub fn MergeContext::retreat_operations(
  self : MergeContext,
  operations : Array[Int],
) -> Unit raise BranchError {
  let cg = self.oplog.causal_graph()
  // Build a set of retreated LVs for fast lookup
  let retreat_set : @hashset.HashSet[Int] = @hashset.HashSet::new()
  for lv in operations {
    retreat_set.insert(lv)
  }

  for lv in operations {
    match self.oplog.get_op(lv) {
      Some(op) =>
        match op.content() {
          @core.Insert(_) =>
            // Retreat Insert: hide the item
            self.tree.delete(@fugue.Lv(lv)) catch {
              e => raise BranchError::Fugue(e)
            }
          @core.Delete | @core.Undelete => {
            // Retreat Delete/Undelete: recompute winner from remaining ops
            let target_lv = match op.origin_left() {
              None => continue
              Some(raw) =>
                match cg.raw_to_lv(raw) {
                  Some(mapped) => mapped
                  None => raise BranchError::MissingOrigin(raw~)
                }
            }
            // Scan oplog for all Delete/Undelete ops targeting this item
            // that are NOT in the retreat set (i.e., remain in common ancestor)
            let mut best_ts = 0
            let mut best_agent = ""
            let mut best_is_undelete = false
            let mut best_deleted = false
            let op_count = self.oplog.op_count()
            for i = 0; i < op_count; i = i + 1 {
              if retreat_set.contains(i) {
                continue // Skip retreated ops
              }
              match self.oplog.get_op(i) {
                Some(other_op) => {
                  let dominated = match other_op.content() {
                    @core.Delete | @core.Undelete => true
                    _ => false
                  }
                  if not(dominated) {
                    continue
                  }
                  // Check if this op targets the same item
                  let other_target = match other_op.origin_left() {
                    None => continue
                    Some(raw) =>
                      match cg.raw_to_lv(raw) {
                        Some(t) => t
                        None => continue
                      }
                  }
                  if other_target != target_lv {
                    continue
                  }
                  // This op targets the same item and is in the common ancestor
                  let (other_ts, other_agent) = match cg[i] {
                    Some(entry) => (entry.timestamp, entry.agent)
                    None => continue
                  }
                  let other_is_undelete = match other_op.content() {
                    @core.Undelete => true
                    _ => false
                  }
                  if should_win_delete(
                    other_ts, other_agent, other_is_undelete,
                    best_ts, best_agent, best_is_undelete,
                  ) {
                    best_ts = other_ts
                    best_agent = other_agent
                    best_is_undelete = other_is_undelete
                    best_deleted = not(other_is_undelete)
                  }
                }
                None => continue
              }
            }
            // Set the item to the recomputed winner state
            self.tree.set_delete_winner(
              @fugue.Lv(target_lv), best_deleted, best_ts, best_agent, best_is_undelete,
            ) catch {
              e => raise BranchError::Fugue(e)
            }
          }
        }
      None => raise BranchError::MissingOp(lv~)
    }
  }
}
```

**Note:** `should_win_delete` is defined in `fugue/tree.mbt` (private to fugue package). Since `branch_merge.mbt` is in a different package (`branch`), it cannot call `should_win_delete` directly. Options:
1. Make `should_win_delete` public (`pub fn`) and import it
2. Duplicate the comparison logic inline in `branch_merge.mbt`
3. Move the comparison to a shared utility

**Recommendation:** Make it `pub fn` in `fugue/tree.mbt` — it's a pure function with no side effects, safe to expose. Or define a standalone `pub fn fugue_delete_wins(...)` in the fugue package.

**Performance note:** The oplog scan is O(n) where n is total ops. Since retreat is rare AND multiple Delete/Undelete on the same item is rare, this is acceptable. Can be optimized later with a per-item index if needed.

- [ ] **Step 4: Run tests**

Run: `cd event-graph-walker && moon test`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
cd event-graph-walker
git add internal/branch/branch.mbt internal/branch/branch_merge.mbt
git commit -m "fix(branch): correct retreat with oplog recomputation, convergent advance

retreat_operations now recomputes the LWW winner from the oplog for
Delete/Undelete ops, scanning for all ops targeting the same item
that remain in the common ancestor. apply_operations and
apply_operation_to_tree use delete_with_ts/undelete_with_ts."
```

---

### Task 5: Update fuzz tests — verify fix and re-enable full property

**Files:**
- Modify: `text/debug_convergence_test.mbt`
- Modify: `text/text_convergence_fuzz_test.mbt`

- [ ] **Step 1: Update debug test with convergence assertions**

Add `assert_true!` at the end of each debug test to assert convergence.

- [ ] **Step 2: Update the known-bug regression test**

In `text/text_convergence_fuzz_test.mbt`, change:

```moonbit
///|
/// FIXED: LWW conflict resolution on Delete/Undelete ops.
test "regression: undo+sync multi-agent convergence (was known-bug)" {
  // ... same trace ...
  let result = run_trace_and_check_convergence(trace)
  assert_true!(result)
}
```

- [ ] **Step 3: Re-enable full property test with undo**

```moonbit
///|
test "property: multi-agent convergence with undo/redo" {
  @qc.quick_check_fn(fn(trace : MultiAgentTrace) -> Bool {
    run_trace_and_check_convergence(trace)
  })
}
```

- [ ] **Step 4: Run fuzz tests**

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/text -f text_convergence_fuzz_test.mbt`
Expected: All property tests PASS.

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/text -f debug_convergence_test.mbt`
Expected: Both pass.

- [ ] **Step 5: Run full test suite**

Run: `cd event-graph-walker && moon test`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
cd event-graph-walker
git add text/debug_convergence_test.mbt text/text_convergence_fuzz_test.mbt
git commit -m "test(text): verify convergence fix, re-enable full fuzz test with undo

Known-bug regression now asserts convergence. Full multi-agent
convergence property test with undo/redo re-enabled."
```

---

### Task 6: moon info + moon fmt + final verification

- [ ] **Step 1:** Run: `cd event-graph-walker && moon info && moon fmt`

- [ ] **Step 2:** Run: `cd event-graph-walker && git diff *.mbti`

Expected new entries:
- `FugueTree::delete_with_ts`, `FugueTree::undelete_with_ts`, `FugueTree::set_delete_winner`
- Item struct with `deleted_ts`, `deleted_agent`, `deleted_is_undelete`

- [ ] **Step 3:** Run: `cd event-graph-walker && moon test` — all pass

- [ ] **Step 4:** Commit:

```bash
cd event-graph-walker
git add -A '*.mbti' '*.mbt'
git commit -m "chore: moon info + moon fmt after LWW Delete/Undelete fix"
```

---

## Post-implementation notes

**What this fixes:**
- Concurrent Delete + Undelete on the same item now converge deterministically
- Fuzz test regression (undo+sync divergence) resolved
- Add-wins: user's undo intent preserved over concurrent deletes
- Retreat correctly restores common-ancestor state via oplog recomputation

**What this doesn't change:**
- Local edit behavior (local ops have highest timestamp, always win)
- Undo/redo semantics (undo ops are local, always win)
- FugueMax insertion algorithm (unchanged)
- Sync protocol (unchanged)

**Follow-up:**
1. Remove `text/debug_convergence_test.mbt` or keep as integration tests
2. Run benchmarks: `cd event-graph-walker && moon bench --release`
3. Consider adding a per-item Delete/Undelete index on OpLog if retreat recomputation becomes a bottleneck (unlikely — retreat is rare and items rarely have multiple Delete/Undelete ops)
