# Wire MovableTree into Block Editor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MovableTree the single source of truth for block ordering by adding `create_node_after` to TreeDoc and removing the redundant `order` array from `BlockDoc`.

**Architecture:** The block editor's `BlockDoc` currently maintains a parallel `order: Array[TreeNodeId]` for root children ordering because `TreeDoc` lacked positional insertion. MovableTree already has fractional indexing internally — we expose it via `create_node_after`, then delete all order-tracking code from `BlockDoc`.

**Tech Stack:** MoonBit, event-graph-walker submodule (TreeDoc/FractionalIndex)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `event-graph-walker/tree/tree_doc.mbt` | Modify | Add `create_node_after` + `position_after_sibling` |
| `event-graph-walker/tree/tree_doc_test.mbt` | Modify | Add tests for `create_node_after` |
| `examples/block-editor/main/block_doc.mbt` | Modify | Remove `order` field + simplify all methods |
| `examples/block-editor/main/block_init.mbt` | Modify | Fix `parse_block_id` struct construction |
| `examples/block-editor/main/block_init_wbtest.mbt` | Modify | Fix field access in test |

---

### Task 1: Add `create_node_after` to TreeDoc

**Files:**
- Modify: `event-graph-walker/tree/tree_doc.mbt:289-328` (after `position_after_last_child`, before `create_node`)

- [ ] **Step 1: Write the failing test**

Append to `event-graph-walker/tree/tree_doc_test.mbt`:

```moonbit
///|
/// Test 21: create_node_after inserts between siblings
test "TreeDoc: create_node_after inserts between siblings" {
  let doc = @tree.TreeDoc::new("alice")
  let a = doc.create_node(parent=@tree.root_id)
  let b = doc.create_node(parent=@tree.root_id)
  let c = doc.create_node_after(parent=@tree.root_id, after=a)
  let children = doc.children(@tree.root_id)
  inspect(children.length(), content="3")
  inspect(children[0] == a, content="true")
  inspect(children[1] == c, content="true")
  inspect(children[2] == b, content="true")
}

///|
/// Test 22: create_node_after appends when after_id is last child
test "TreeDoc: create_node_after appends after last" {
  let doc = @tree.TreeDoc::new("alice")
  let a = doc.create_node(parent=@tree.root_id)
  let b = doc.create_node(parent=@tree.root_id)
  let c = doc.create_node_after(parent=@tree.root_id, after=b)
  let children = doc.children(@tree.root_id)
  inspect(children.length(), content="3")
  inspect(children[0] == a, content="true")
  inspect(children[1] == b, content="true")
  inspect(children[2] == c, content="true")
}

///|
/// Test 23: create_node_after with nested parent
test "TreeDoc: create_node_after nested" {
  let doc = @tree.TreeDoc::new("alice")
  let parent = doc.create_node(parent=@tree.root_id)
  let x = doc.create_node(parent~)
  let y = doc.create_node(parent~)
  let z = doc.create_node_after(parent~, after=x)
  let children = doc.children(parent)
  inspect(children.length(), content="3")
  inspect(children[0] == x, content="true")
  inspect(children[1] == z, content="true")
  inspect(children[2] == y, content="true")
}

///|
/// Test 24: create_node_after falls back to append when after_id is not a child
test "TreeDoc: create_node_after fallback on missing after" {
  let doc = @tree.TreeDoc::new("alice")
  let a = doc.create_node(parent=@tree.root_id)
  let orphan : @mt.TreeNodeId = { agent: "ghost", counter: 99 }
  let b = doc.create_node_after(parent=@tree.root_id, after=orphan)
  let children = doc.children(@tree.root_id)
  inspect(children.length(), content="2")
  inspect(children[0] == a, content="true")
  inspect(children[1] == b, content="true")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd event-graph-walker && moon test -p tree`
Expected: FAIL — `create_node_after` not found

- [ ] **Step 3: Add `position_after_sibling` helper**

Add after `position_after_last_child` in `event-graph-walker/tree/tree_doc.mbt`:

```moonbit
///|
/// Compute a fractional index that sorts immediately after a given sibling.
/// Falls back to appending after the last child if `after` is not found.
fn TreeDoc::position_after_sibling(
  self : TreeDoc,
  parent : @mt.TreeNodeId,
  after : @mt.TreeNodeId,
) -> @fi.FractionalIndex {
  let children = self.tree.children(parent)
  let after_pos = self.tree.get_position(after)
  let mut next_pos : @fi.FractionalIndex? = None
  let mut found = false
  for child in children {
    if found {
      next_pos = self.tree.get_position(child)
      break
    }
    if child == after {
      found = true
    }
  }
  if not(found) {
    return self.position_after_last_child(parent)
  }
  @fi.FractionalIndex::between(left=after_pos, right=next_pos)
}
```

- [ ] **Step 4: Add `create_node_after` public method**

Add after `create_node` in `event-graph-walker/tree/tree_doc.mbt`:

```moonbit
///|
/// Create a new node as a child of `parent`, positioned immediately after `after`.
/// Falls back to appending at the end if `after` is not a child of `parent`.
pub fn TreeDoc::create_node_after(
  self : TreeDoc,
  parent~ : @mt.TreeNodeId,
  after~ : @mt.TreeNodeId,
) -> @mt.TreeNodeId {
  if not(self.is_local_parent_valid(parent)) {
    abort("TreeDoc::create_node_after: parent does not exist locally")
  }
  let id = self.alloc_id()
  let timestamp = self.next_timestamp()
  let position = self.position_after_sibling(parent, after)
  let move_op : @mt.TreeMoveOp = {
    timestamp,
    target: id,
    new_parent: parent,
    position,
    agent: self.agent_id,
  }
  self.apply_move_op(move_op)
  let _ = self.record_op(@mt.Move(move_op))
  id
}
```

- [ ] **Step 5: Run tests**

Run: `cd event-graph-walker && moon test -p tree`
Expected: All 24 tests pass

- [ ] **Step 6: Update interface and format**

Run: `cd event-graph-walker && moon info && moon fmt`

- [ ] **Step 7: Commit in submodule**

```bash
cd event-graph-walker
git add tree/tree_doc.mbt tree/tree_doc_test.mbt tree/pkg.generated.mbti
git commit -m "feat(tree): add create_node_after for positional insertion"
```

---

### Task 2: Fix block-editor build errors

**Files:**
- Modify: `examples/block-editor/main/block_init.mbt:62`
- Modify: `examples/block-editor/main/block_init_wbtest.mbt:34-37`

- [ ] **Step 1: Fix `parse_block_id` — replace missing `tree_node_id_new` with struct literal**

In `examples/block-editor/main/block_init.mbt`, replace line 62:

```moonbit
// Old:
  @tree.tree_node_id_new(agent, counter)
// New:
  let id : @tree.TreeNodeId = { agent, counter }
  id
```

- [ ] **Step 2: Fix test — replace missing accessors with field access**

In `examples/block-editor/main/block_init_wbtest.mbt`, replace lines 34-38:

```moonbit
// Old:
  inspect(@tree.tree_node_id_agent(parsed), content="alice")
  inspect(
    @tree.tree_node_id_counter(parsed) == @tree.tree_node_id_counter(id),
    content="true",
  )
// New:
  inspect(parsed.agent, content="alice")
  inspect(parsed.counter == id.counter, content="true")
```

- [ ] **Step 3: Run moon check**

Run: `cd examples/block-editor && moon check`
Expected: No errors

- [ ] **Step 4: Run tests**

Run: `cd examples/block-editor && moon test`
Expected: All 30 tests pass

---

### Task 3: Remove `order` array from BlockDoc

**Files:**
- Modify: `examples/block-editor/main/block_doc.mbt` (full rewrite of the struct and methods)

- [ ] **Step 1: Remove `order` field from struct and constructor**

Replace the struct and `new`:

```moonbit
pub struct BlockDoc {
  priv tree : @tree.TreeDoc
  priv texts : Map[String, @text.TextDoc]
  priv replica_id : String
}

///|
pub fn BlockDoc::new(replica_id : String) -> BlockDoc {
  { tree: @tree.TreeDoc::new(replica_id), texts: {}, replica_id }
}
```

- [ ] **Step 2: Simplify `create_block` — remove order.push**

```moonbit
///|
/// Create a block as the last child of `parent` (default: root).
pub fn BlockDoc::create_block(
  self : BlockDoc,
  block_type : BlockType,
  parent? : @tree.TreeNodeId = root_block_id,
) -> @tree.TreeNodeId {
  let id = self.tree.create_node(parent~)
  self.texts[id_key(id)] = @text.TextDoc::new(self.replica_id)
  self.apply_block_type(id, block_type)
  id
}
```

- [ ] **Step 3: Rewrite `create_block_after` to use tree's fractional indexing**

```moonbit
///|
/// Create a block immediately after `after_id` in document order.
pub fn BlockDoc::create_block_after(
  self : BlockDoc,
  after_id : @tree.TreeNodeId,
  block_type : BlockType,
) -> @tree.TreeNodeId {
  let id = self.tree.create_node_after(parent=root_block_id, after=after_id)
  self.texts[id_key(id)] = @text.TextDoc::new(self.replica_id)
  self.apply_block_type(id, block_type)
  id
}
```

- [ ] **Step 4: Simplify `delete_block` — remove order filter**

```moonbit
///|
/// Delete a block: move it to the tree trash.
pub fn BlockDoc::delete_block(self : BlockDoc, id : @tree.TreeNodeId) -> Unit {
  self.tree.delete_node(id)
}
```

- [ ] **Step 5: Simplify `move_block` — remove order guard**

```moonbit
///|
/// Move a block to a new parent.
pub fn BlockDoc::move_block(
  self : BlockDoc,
  id : @tree.TreeNodeId,
  new_parent~ : @tree.TreeNodeId,
) -> Unit {
  self.tree.move_node(target=id, new_parent~)
}
```

- [ ] **Step 6: Simplify `children` — always delegate to tree**

```moonbit
///|
/// Return children of `parent` in display order (sorted by fractional index).
pub fn BlockDoc::children(
  self : BlockDoc,
  parent : @tree.TreeNodeId,
) -> Array[@tree.TreeNodeId] {
  self.tree.children(parent)
}
```

- [ ] **Step 7: Remove `order_index` helper**

Delete lines 220-229 (`fn BlockDoc::order_index`).

- [ ] **Step 8: Remove stale V1 workaround comment**

Delete the comment block at lines 1-8 (the workaround comment about `order`).

- [ ] **Step 9: Run moon check**

Run: `cd examples/block-editor && moon check`
Expected: No errors

- [ ] **Step 10: Run tests**

Run: `cd examples/block-editor && moon test`
Expected: All 30 tests pass (ordering tests use tree's fractional indexing now)

- [ ] **Step 11: Format**

Run: `cd examples/block-editor && moon info && moon fmt`

---

### Task 4: Commit and verify

- [ ] **Step 1: Run full test suite**

```bash
cd event-graph-walker && moon test
cd ../examples/block-editor && moon test
```

- [ ] **Step 2: Update submodule pointer**

```bash
cd /path/to/canopy
git add event-graph-walker
```

- [ ] **Step 3: Commit**

```bash
git add examples/block-editor/main/block_doc.mbt \
        examples/block-editor/main/block_init.mbt \
        examples/block-editor/main/block_init_wbtest.mbt \
        event-graph-walker
git commit -m "feat(block-editor): wire MovableTree fractional indexing, remove order array

TreeDoc::create_node_after enables positional insertion via fractional
indexing. BlockDoc no longer maintains a parallel order array — the
tree CRDT is now the single source of truth for block ordering."
```
