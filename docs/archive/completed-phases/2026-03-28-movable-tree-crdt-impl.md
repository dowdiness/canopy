# MovableTree CRDT Implementation Plan

**Status:** Complete

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a movable tree CRDT to event-graph-walker, implementing Kleppmann's algorithm with fractional indexing for sibling ordering.

**Architecture:** New packages inside event-graph-walker: `internal/fractional_index/` for sibling ordering, `internal/movable_tree/` for the tree CRDT core, and `tree/` for the public API. Shares `CausalGraph` for Lamport timestamps and causal ordering. Does NOT modify existing sequence CRDT code — tree operations have their own types parallel to the existing `Op`/`OpContent`.

**Tech Stack:** MoonBit, moonbitlang/quickcheck for property-based tests

---

## File Structure

```
event-graph-walker/
  internal/
    fractional_index/
      fractional_index.mbt           -- FractionalIndex type + between() algorithm
      fractional_index_test.mbt      -- Unit tests
      fractional_index_properties_test.mbt -- Quickcheck ordering properties
      moon.pkg.json
    movable_tree/
      types.mbt                      -- TreeNodeId, TreeOp, TreeOpContent, TRASH sentinel
      tree.mbt                       -- MovableTree structure + apply operations
      ancestor.mbt                   -- is_ancestor_of() with iterative parent walk
      conflict.mbt                   -- Kleppmann's undo-do-redo for concurrent moves
      tree_test.mbt                  -- Unit tests (single peer)
      convergence_test.mbt           -- Multi-peer convergence tests
      convergence_properties_test.mbt -- Quickcheck convergence properties
      moon.pkg.json
  tree/
    tree_doc.mbt                     -- Public TreeDoc API (mirrors TextDoc pattern)
    tree_doc_test.mbt                -- Integration tests
    moon.pkg.json
```

**Unchanged files:** All existing code in `internal/core/`, `internal/fugue/`, `internal/oplog/`, `internal/branch/`, `internal/document/`, `text/`, `undo/` remains untouched. The tree CRDT is additive.

---

### Task 1: FractionalIndex

Standalone sibling ordering. No CRDT dependency. A `FractionalIndex` is a byte array that supports generating a key between any two existing keys, with deterministic tie-breaking.

**Files:**
- Create: `event-graph-walker/internal/fractional_index/fractional_index.mbt`
- Create: `event-graph-walker/internal/fractional_index/fractional_index_test.mbt`
- Create: `event-graph-walker/internal/fractional_index/fractional_index_properties_test.mbt`
- Create: `event-graph-walker/internal/fractional_index/moon.pkg.json`

- [ ] **Step 1: Create moon.pkg.json**

```json
{
  "import": [
    "moonbitlang/quickcheck" "@qc"
  ]
}
```

Run: `cd event-graph-walker && moon check`
Expected: PASS (empty package)

- [ ] **Step 2: Write failing test for FractionalIndex ordering**

In `fractional_index_test.mbt`:

```moonbit
///|
test "between: generates key between two keys" {
  let a = @fractional_index.FractionalIndex::new(b"\x01")
  let b = @fractional_index.FractionalIndex::new(b"\x03")
  let mid = @fractional_index.FractionalIndex::between(Some(a), Some(b))
  inspect(mid > a, content="true")
  inspect(mid < b, content="true")
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/fractional_index`
Expected: FAIL — `FractionalIndex` not defined

- [ ] **Step 3: Implement FractionalIndex type and between()**

In `fractional_index.mbt`:

```moonbit
///|
pub(all) struct FractionalIndex {
  bytes : Bytes
} derive(Eq, Show, Debug)

///|
pub fn FractionalIndex::new(bytes : Bytes) -> FractionalIndex {
  FractionalIndex::{ bytes }
}

///|
pub impl Compare for FractionalIndex with compare(self, other) {
  let len = if self.bytes.length() < other.bytes.length() {
    self.bytes.length()
  } else {
    other.bytes.length()
  }
  for i = 0; i < len; i = i + 1 {
    let a = self.bytes[i]
    let b = other.bytes[i]
    if a < b {
      return -1
    }
    if a > b {
      return 1
    }
  }
  self.bytes.length().compare(other.bytes.length())
}

///|
/// Generate a FractionalIndex between `left` and `right`.
/// - `between(None, None)` → midpoint of the key space
/// - `between(None, Some(r))` → before r
/// - `between(Some(l), None)` → after l
/// - `between(Some(l), Some(r))` → between l and r (l < r required)
pub fn FractionalIndex::between(
  left : FractionalIndex?,
  right : FractionalIndex?,
) -> FractionalIndex {
  match (left, right) {
    (None, None) => FractionalIndex::new(b"\x80")
    (None, Some(r)) => {
      // Generate a key before r: find first non-zero byte, halve it
      let buf = Bytes::make(r.bytes.length() + 1, 0)
      for i = 0; i < r.bytes.length(); i = i + 1 {
        buf[i] = r.bytes[i]
      }
      // Find position to split
      let mut i = 0
      while i < r.bytes.length() && r.bytes[i] == 0 {
        buf[i] = 0
        i = i + 1
      }
      if i < r.bytes.length() {
        let v = r.bytes[i].to_int()
        if v > 1 {
          buf[i] = (v / 2).to_byte()
          FractionalIndex::new(Bytes::sub(buf, 0, i + 1))
        } else {
          // byte is 1 or 0, need to go deeper
          buf[i] = 0
          buf[i + 1] = 128
          FractionalIndex::new(Bytes::sub(buf, 0, i + 2))
        }
      } else {
        // All zeros — prepend with 0x00 0x80
        buf[r.bytes.length()] = 128
        FractionalIndex::new(buf)
      }
    }
    (Some(l), None) => {
      // Generate a key after l: increment last byte, or append 0x80
      let buf = Bytes::make(l.bytes.length() + 1, 0)
      for i = 0; i < l.bytes.length(); i = i + 1 {
        buf[i] = l.bytes[i]
      }
      let last = l.bytes.length() - 1
      let v = l.bytes[last].to_int()
      if v < 255 {
        buf[last] = (v + 1 + (255 - v) / 2).to_byte()
        FractionalIndex::new(Bytes::sub(buf, 0, l.bytes.length()))
      } else {
        // Last byte is 0xFF, append 0x80
        buf[l.bytes.length()] = 128
        FractionalIndex::new(buf)
      }
    }
    (Some(l), Some(r)) => {
      // Generate a key between l and r
      let max_len = if l.bytes.length() > r.bytes.length() {
        l.bytes.length()
      } else {
        r.bytes.length()
      }
      let buf = Bytes::make(max_len + 1, 0)
      for i = 0; i < max_len + 1; i = i + 1 {
        let a = if i < l.bytes.length() { l.bytes[i].to_int() } else { 0 }
        let b = if i < r.bytes.length() { r.bytes[i].to_int() } else { 256 }
        if a == b {
          buf[i] = a.to_byte()
          continue i + 1
        }
        // a < b at this position
        if b - a > 1 {
          buf[i] = (a + (b - a) / 2).to_byte()
          return FractionalIndex::new(Bytes::sub(buf, 0, i + 1))
        }
        // b - a == 1, need to go deeper: keep a, recurse on next byte
        buf[i] = a.to_byte()
        // Next byte: between 0 and (right's next byte or 256)
        let next_r = if i + 1 < r.bytes.length() {
          r.bytes[i + 1].to_int()
        } else {
          256
        }
        let next_l = if i + 1 < l.bytes.length() {
          l.bytes[i + 1].to_int()
        } else {
          0
        }
        if next_r - next_l > 1 {
          buf[i + 1] = (next_l + (next_r - next_l) / 2).to_byte()
          return FractionalIndex::new(Bytes::sub(buf, 0, i + 2))
        }
        buf[i + 1] = next_l.to_byte()
        buf[i + 2] = 128
        return FractionalIndex::new(Bytes::sub(buf, 0, i + 3))
      }
      // Shouldn't reach here if l < r
      abort("FractionalIndex::between: left must be less than right")
    }
  }
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/fractional_index`
Expected: PASS

- [ ] **Step 4: Write more ordering tests**

Add to `fractional_index_test.mbt`:

```moonbit
///|
test "between: None None gives midpoint" {
  let mid = @fractional_index.FractionalIndex::between(None, None)
  inspect(mid.bytes()[0], content="128")
}

///|
test "between: None right gives key before right" {
  let r = @fractional_index.FractionalIndex::new(b"\x80")
  let mid = @fractional_index.FractionalIndex::between(None, Some(r))
  inspect(mid < r, content="true")
}

///|
test "between: left None gives key after left" {
  let l = @fractional_index.FractionalIndex::new(b"\x80")
  let mid = @fractional_index.FractionalIndex::between(Some(l), None)
  inspect(mid > l, content="true")
}

///|
test "between: many insertions at same position stay ordered" {
  let mut prev : @fractional_index.FractionalIndex? = None
  let mut next = @fractional_index.FractionalIndex::new(b"\x80")
  // Insert 20 items all before next — simulates typing at the start
  let items : Array[@fractional_index.FractionalIndex] = []
  for i = 0; i < 20; i = i + 1 {
    let mid = @fractional_index.FractionalIndex::between(prev, Some(next))
    items.push(mid)
    prev = Some(mid)
  }
  // All items should be strictly ordered
  for i = 1; i < items.length(); i = i + 1 {
    inspect(items[i] > items[i - 1], content="true")
  }
}

///|
test "between: interleaving stays ordered" {
  let a = @fractional_index.FractionalIndex::new(b"\x40")
  let b = @fractional_index.FractionalIndex::new(b"\xC0")
  let mid1 = @fractional_index.FractionalIndex::between(Some(a), Some(b))
  let mid2 = @fractional_index.FractionalIndex::between(Some(a), Some(mid1))
  let mid3 = @fractional_index.FractionalIndex::between(Some(mid2), Some(mid1))
  inspect(a < mid2, content="true")
  inspect(mid2 < mid3, content="true")
  inspect(mid3 < mid1, content="true")
  inspect(mid1 < b, content="true")
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/fractional_index`
Expected: PASS

- [ ] **Step 5: Write quickcheck property tests**

In `fractional_index_properties_test.mbt`:

```moonbit
///|
test "property: between(l, r) is always strictly between l and r" {
  // Generate random byte arrays, sort them, verify between works
  let pairs : Array[(Bytes, Bytes)] = [
    (b"\x10", b"\x20"),
    (b"\x01", b"\xFF"),
    (b"\x80", b"\x81"),
    (b"\x80\x00", b"\x80\x01"),
    (b"\x01\x01", b"\x01\x03"),
    (b"\xFE", b"\xFF"),
  ]
  for pair in pairs {
    let l = @fractional_index.FractionalIndex::new(pair.0)
    let r = @fractional_index.FractionalIndex::new(pair.1)
    let mid = @fractional_index.FractionalIndex::between(Some(l), Some(r))
    inspect(mid > l, content="true")
    inspect(mid < r, content="true")
  }
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/fractional_index`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
cd event-graph-walker
git add internal/fractional_index/
git commit -m "feat: add FractionalIndex for CRDT sibling ordering"
```

---

### Task 2: Tree Types and MovableTree Structure

Core types for the movable tree CRDT. A tree of nodes where each node has a parent, fractional index for sibling ordering, and a property map.

**Files:**
- Create: `event-graph-walker/internal/movable_tree/types.mbt`
- Create: `event-graph-walker/internal/movable_tree/tree.mbt`
- Create: `event-graph-walker/internal/movable_tree/tree_test.mbt`
- Create: `event-graph-walker/internal/movable_tree/moon.pkg.json`

- [ ] **Step 1: Create moon.pkg.json**

```json
{
  "import": [
    "dowdiness/event-graph-walker/internal/fractional_index" "@fi"
  ]
}
```

Run: `cd event-graph-walker && moon check`
Expected: PASS

- [ ] **Step 2: Write failing test for tree creation and node insertion**

In `tree_test.mbt`:

```moonbit
///|
test "create: single node under root" {
  let tree = @movable_tree.MovableTree::new()
  let id = tree.create_node(
    parent=@movable_tree.root_id,
    position=@fi.FractionalIndex::between(None, None),
  )
  inspect(tree.parent(id), content="Some(ROOT)")
  inspect(tree.children(@movable_tree.root_id).length(), content="1")
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/movable_tree`
Expected: FAIL — types not defined

- [ ] **Step 3: Implement core types**

In `types.mbt`:

```moonbit
///|
/// Unique identifier for a tree node.
/// Uses (agent_id, lamport_timestamp) for global uniqueness across peers.
pub(all) struct TreeNodeId {
  agent : String
  counter : Int
} derive(Eq, Hash, Show, Debug, Compare)

///|
/// Sentinel ID for the virtual root node.
pub let root_id : TreeNodeId = TreeNodeId::{ agent: "", counter: -1 }

///|
/// Sentinel ID for the TRASH node (deleted nodes are moved here).
pub let trash_id : TreeNodeId = TreeNodeId::{ agent: "", counter: -2 }

///|
/// A move operation in the tree CRDT.
/// All tree mutations (create, move, delete) are represented as moves.
/// - Create: move from NOWHERE to a parent
/// - Delete: move to TRASH
/// - Move: move to a new parent with new position
pub(all) struct TreeMoveOp {
  timestamp : Int                           // Lamport timestamp (sort key)
  target : TreeNodeId                       // Node being moved
  new_parent : TreeNodeId                   // Destination parent (TRASH = delete)
  position : @fi.FractionalIndex            // Position among siblings
  agent : String                            // Who created this op
} derive(Show, Debug)

///|
/// Internal representation of a node in the tree.
pub(all) struct TreeNode {
  id : TreeNodeId
  mut parent : TreeNodeId
  mut position : @fi.FractionalIndex
  properties : Map[String, String]          // Block metadata (type, level, etc.)
} derive(Show, Debug)
```

- [ ] **Step 4: Implement MovableTree structure**

In `tree.mbt`:

```moonbit
///|
pub struct MovableTree {
  priv nodes : Map[TreeNodeId, TreeNode]
  priv children_cache : Map[TreeNodeId, Array[TreeNodeId]]
  priv mut next_counter : Int
  priv agent_id : String
}

///|
pub fn MovableTree::new(agent_id~ : String = "local") -> MovableTree {
  let children_cache : Map[TreeNodeId, Array[TreeNodeId]] = Map::new()
  children_cache[root_id] = []
  children_cache[trash_id] = []
  MovableTree::{
    nodes: Map::new(),
    children_cache,
    next_counter: 0,
    agent_id,
  }
}

///|
pub fn MovableTree::create_node(
  self : MovableTree,
  parent~ : TreeNodeId,
  position~ : @fi.FractionalIndex,
) -> TreeNodeId {
  let id = TreeNodeId::{ agent: self.agent_id, counter: self.next_counter }
  self.next_counter = self.next_counter + 1
  let node = TreeNode::{
    id,
    parent,
    position,
    properties: Map::new(),
  }
  self.nodes[id] = node
  // Add to parent's children
  match self.children_cache[parent] {
    Some(children) => children.push(id)
    None => self.children_cache[parent] = [id]
  }
  id
}

///|
pub fn MovableTree::parent(self : MovableTree, id : TreeNodeId) -> TreeNodeId? {
  match self.nodes[id] {
    Some(node) => Some(node.parent)
    None => None
  }
}

///|
/// Returns children of a node, sorted by fractional index.
pub fn MovableTree::children(
  self : MovableTree,
  parent : TreeNodeId,
) -> Array[TreeNodeId] {
  match self.children_cache[parent] {
    Some(children) => {
      let sorted = children.copy()
      sorted.sort_by(fn(a, b) {
        let node_a = self.nodes[a].unwrap()
        let node_b = self.nodes[b].unwrap()
        node_a.position.compare(node_b.position)
      })
      sorted
    }
    None => []
  }
}

///|
pub fn MovableTree::is_alive(self : MovableTree, id : TreeNodeId) -> Bool {
  match self.nodes[id] {
    Some(node) => node.parent != trash_id
    None => false
  }
}

///|
pub fn MovableTree::node_count(self : MovableTree) -> Int {
  self.nodes.size()
}

///|
pub fn MovableTree::set_property(
  self : MovableTree,
  id : TreeNodeId,
  key : String,
  value : String,
) -> Unit {
  match self.nodes[id] {
    Some(node) => node.properties[key] = value
    None => ()
  }
}

///|
pub fn MovableTree::get_property(
  self : MovableTree,
  id : TreeNodeId,
  key : String,
) -> String? {
  match self.nodes[id] {
    Some(node) => node.properties[key]
    None => None
  }
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/movable_tree`
Expected: PASS

- [ ] **Step 5: Write tests for move and delete**

Add to `tree_test.mbt`:

```moonbit
///|
test "move: reparent a node" {
  let tree = @movable_tree.MovableTree::new()
  let a = tree.create_node(
    parent=@movable_tree.root_id,
    position=@fi.FractionalIndex::new(b"\x40"),
  )
  let b = tree.create_node(
    parent=@movable_tree.root_id,
    position=@fi.FractionalIndex::new(b"\x80"),
  )
  // Move a under b
  tree.move_node(
    target=a,
    new_parent=b,
    position=@fi.FractionalIndex::between(None, None),
  )
  inspect(tree.parent(a), content="Some({agent: \"local\", counter: 1})")
  inspect(tree.children(@movable_tree.root_id).length(), content="1")
  inspect(tree.children(b).length(), content="1")
}

///|
test "delete: move to trash" {
  let tree = @movable_tree.MovableTree::new()
  let a = tree.create_node(
    parent=@movable_tree.root_id,
    position=@fi.FractionalIndex::between(None, None),
  )
  tree.delete_node(a)
  inspect(tree.is_alive(a), content="false")
  inspect(tree.children(@movable_tree.root_id).length(), content="0")
}

///|
test "children: sorted by fractional index" {
  let tree = @movable_tree.MovableTree::new()
  let c = tree.create_node(
    parent=@movable_tree.root_id,
    position=@fi.FractionalIndex::new(b"\xC0"),
  )
  let a = tree.create_node(
    parent=@movable_tree.root_id,
    position=@fi.FractionalIndex::new(b"\x40"),
  )
  let b = tree.create_node(
    parent=@movable_tree.root_id,
    position=@fi.FractionalIndex::new(b"\x80"),
  )
  let children = tree.children(@movable_tree.root_id)
  inspect(children[0] == a, content="true")
  inspect(children[1] == b, content="true")
  inspect(children[2] == c, content="true")
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/movable_tree`
Expected: FAIL — `move_node` and `delete_node` not defined

- [ ] **Step 6: Implement move_node and delete_node**

Add to `tree.mbt`:

```moonbit
///|
pub fn MovableTree::move_node(
  self : MovableTree,
  target~ : TreeNodeId,
  new_parent~ : TreeNodeId,
  position~ : @fi.FractionalIndex,
) -> Unit {
  match self.nodes[target] {
    None => () // Node doesn't exist, no-op
    Some(node) => {
      let old_parent = node.parent
      // Remove from old parent's children
      match self.children_cache[old_parent] {
        Some(children) => {
          let idx = children.search(target)
          match idx {
            Some(i) => { let _ = children.remove(i) }
            None => ()
          }
        }
        None => ()
      }
      // Update node
      node.parent = new_parent
      node.position = position
      // Add to new parent's children
      match self.children_cache[new_parent] {
        Some(children) => children.push(target)
        None => self.children_cache[new_parent] = [target]
      }
    }
  }
}

///|
pub fn MovableTree::delete_node(self : MovableTree, target : TreeNodeId) -> Unit {
  self.move_node(
    target~,
    new_parent=trash_id,
    position=@fi.FractionalIndex::new(b"\x00"),
  )
}

///|
pub fn MovableTree::restore_node(
  self : MovableTree,
  target~ : TreeNodeId,
  parent~ : TreeNodeId,
  position~ : @fi.FractionalIndex,
) -> Unit {
  self.move_node(target~, new_parent=parent, position~)
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/movable_tree`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
cd event-graph-walker
git add internal/movable_tree/
git commit -m "feat: add MovableTree structure with create/move/delete"
```

---

### Task 3: Ancestor Detection (Cycle Prevention)

Cycle detection is the core safety invariant. Before applying a move, check that `new_parent` is not a descendant of `target` — otherwise the move would create a cycle.

**Files:**
- Create: `event-graph-walker/internal/movable_tree/ancestor.mbt`
- Modify: `event-graph-walker/internal/movable_tree/tree_test.mbt`

- [ ] **Step 1: Write failing test for is_ancestor_of**

Add to `tree_test.mbt`:

```moonbit
///|
test "is_ancestor_of: parent is ancestor of child" {
  let tree = @movable_tree.MovableTree::new()
  let a = tree.create_node(
    parent=@movable_tree.root_id,
    position=@fi.FractionalIndex::between(None, None),
  )
  let b = tree.create_node(
    parent=a,
    position=@fi.FractionalIndex::between(None, None),
  )
  inspect(tree.is_ancestor_of(a, b), content="true")
  inspect(tree.is_ancestor_of(b, a), content="false")
  inspect(tree.is_ancestor_of(@movable_tree.root_id, b), content="true")
}

///|
test "is_ancestor_of: node is not its own ancestor" {
  let tree = @movable_tree.MovableTree::new()
  let a = tree.create_node(
    parent=@movable_tree.root_id,
    position=@fi.FractionalIndex::between(None, None),
  )
  inspect(tree.is_ancestor_of(a, a), content="false")
}

///|
test "is_ancestor_of: deep chain" {
  let tree = @movable_tree.MovableTree::new()
  let mut parent = @movable_tree.root_id
  let nodes : Array[@movable_tree.TreeNodeId] = []
  for i = 0; i < 10; i = i + 1 {
    let n = tree.create_node(
      parent~,
      position=@fi.FractionalIndex::between(None, None),
    )
    nodes.push(n)
    parent = n
  }
  // First node is ancestor of last
  inspect(tree.is_ancestor_of(nodes[0], nodes[9]), content="true")
  // Last is not ancestor of first
  inspect(tree.is_ancestor_of(nodes[9], nodes[0]), content="false")
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/movable_tree`
Expected: FAIL — `is_ancestor_of` not defined

- [ ] **Step 2: Implement is_ancestor_of**

In `ancestor.mbt`:

```moonbit
///|
/// Returns true if `ancestor` is a proper ancestor of `descendant`.
/// Walks up from descendant following parent pointers until it finds
/// ancestor or reaches root/trash.
pub fn MovableTree::is_ancestor_of(
  self : MovableTree,
  ancestor : TreeNodeId,
  descendant : TreeNodeId,
) -> Bool {
  if ancestor == descendant {
    return false
  }
  let mut current = descendant
  while true {
    match self.nodes[current] {
      None => return false
      Some(node) => {
        if node.parent == ancestor {
          return true
        }
        if node.parent == root_id || node.parent == trash_id {
          return false
        }
        current = node.parent
      }
    }
  }
  false
}

///|
/// Returns true if moving `target` to `new_parent` would create a cycle.
/// A cycle occurs when new_parent is target itself or a descendant of target.
pub fn MovableTree::would_create_cycle(
  self : MovableTree,
  target : TreeNodeId,
  new_parent : TreeNodeId,
) -> Bool {
  if target == new_parent {
    return true
  }
  self.is_ancestor_of(target, new_parent)
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/movable_tree`
Expected: PASS

- [ ] **Step 3: Write test that move_node rejects cycles**

Add to `tree_test.mbt`:

```moonbit
///|
test "move: rejects cycle (move parent under child)" {
  let tree = @movable_tree.MovableTree::new()
  let a = tree.create_node(
    parent=@movable_tree.root_id,
    position=@fi.FractionalIndex::between(None, None),
  )
  let b = tree.create_node(
    parent=a,
    position=@fi.FractionalIndex::between(None, None),
  )
  // Try to move a under b — would create cycle
  let result = tree.try_move_node(
    target=a,
    new_parent=b,
    position=@fi.FractionalIndex::between(None, None),
  )
  inspect(result, content="false")
  // a should still be under root
  inspect(tree.parent(a).unwrap() == @movable_tree.root_id, content="true")
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/movable_tree`
Expected: FAIL — `try_move_node` not defined

- [ ] **Step 4: Implement try_move_node with cycle check**

Add to `tree.mbt`:

```moonbit
///|
/// Attempts to move a node. Returns false if the move would create a cycle.
pub fn MovableTree::try_move_node(
  self : MovableTree,
  target~ : TreeNodeId,
  new_parent~ : TreeNodeId,
  position~ : @fi.FractionalIndex,
) -> Bool {
  if self.would_create_cycle(target, new_parent) {
    return false
  }
  self.move_node(target~, new_parent~, position~)
  true
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/movable_tree`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd event-graph-walker
git add internal/movable_tree/ancestor.mbt internal/movable_tree/tree.mbt internal/movable_tree/tree_test.mbt
git commit -m "feat: add cycle detection for MovableTree"
```

---

### Task 4: Kleppmann's Undo-Do-Redo Conflict Resolution

This is the core of the movable tree CRDT. When concurrent move operations arrive, they must be applied in Lamport timestamp order. If an operation arrives out of order, we undo back to that timestamp, apply it, then redo forward — skipping any redone move that would create a cycle.

**Files:**
- Create: `event-graph-walker/internal/movable_tree/conflict.mbt`
- Create: `event-graph-walker/internal/movable_tree/convergence_test.mbt`

- [ ] **Step 1: Write failing test for concurrent moves converging**

In `convergence_test.mbt`:

```moonbit
///|
/// Helper: apply a TreeMoveOp to a tree using the conflict resolution algorithm.
fn apply_op(
  tree : @movable_tree.MovableTree,
  log : @movable_tree.OpLog,
  op : @movable_tree.TreeMoveOp,
) -> Unit {
  log.apply(tree, op)
}

///|
test "convergence: two peers, same ops different order, same result" {
  // Peer A creates node 1 under root, then moves it
  // Peer B creates node 2 under root, then moves it
  // Both apply all ops — should converge to same tree
  let pos1 = @fi.FractionalIndex::new(b"\x40")
  let pos2 = @fi.FractionalIndex::new(b"\x80")
  let pos3 = @fi.FractionalIndex::new(b"\xC0")
  let node1 = @movable_tree.TreeNodeId::{ agent: "alice", counter: 0 }
  let node2 = @movable_tree.TreeNodeId::{ agent: "bob", counter: 0 }
  let root = @movable_tree.root_id

  let ops : Array[@movable_tree.TreeMoveOp] = [
    // Alice creates node1 (timestamp 1)
    @movable_tree.TreeMoveOp::{
      timestamp: 1, target: node1, new_parent: root,
      position: pos1, agent: "alice",
    },
    // Bob creates node2 (timestamp 2)
    @movable_tree.TreeMoveOp::{
      timestamp: 2, target: node2, new_parent: root,
      position: pos2, agent: "bob",
    },
    // Alice moves node1 under node2 (timestamp 3)
    @movable_tree.TreeMoveOp::{
      timestamp: 3, target: node1, new_parent: node2,
      position: pos3, agent: "alice",
    },
  ]

  // Peer A applies in order: 1, 2, 3
  let tree_a = @movable_tree.MovableTree::new(agent_id="alice")
  let log_a = @movable_tree.OpLog::new()
  for op in ops {
    apply_op(tree_a, log_a, op)
  }

  // Peer B applies in reverse order: 3, 2, 1
  let tree_b = @movable_tree.MovableTree::new(agent_id="bob")
  let log_b = @movable_tree.OpLog::new()
  apply_op(tree_b, log_b, ops[2])
  apply_op(tree_b, log_b, ops[1])
  apply_op(tree_b, log_b, ops[0])

  // Both should have node1 under node2, node2 under root
  inspect(tree_a.parent(node1).unwrap() == node2, content="true")
  inspect(tree_a.parent(node2).unwrap() == root, content="true")
  inspect(tree_b.parent(node1).unwrap() == node2, content="true")
  inspect(tree_b.parent(node2).unwrap() == root, content="true")
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/movable_tree`
Expected: FAIL — `OpLog` not defined

- [ ] **Step 2: Implement OpLog and Kleppmann's undo-do-redo**

In `conflict.mbt`:

```moonbit
///|
/// Operation log for the movable tree CRDT.
/// Maintains ops sorted by timestamp for Kleppmann's undo-do-redo.
pub struct OpLog {
  priv ops : Array[TreeMoveOp]     // Sorted by (timestamp, agent) — the global total order
  priv applied : Array[Bool]       // Whether each op is currently applied (not undone for cycle)
}

///|
pub fn OpLog::new() -> OpLog {
  OpLog::{ ops: [], applied: [] }
}

///|
/// Compare two ops for total ordering: (timestamp, agent).
fn op_order(a : TreeMoveOp, b : TreeMoveOp) -> Int {
  let ts_cmp = a.timestamp.compare(b.timestamp)
  if ts_cmp != 0 {
    return ts_cmp
  }
  a.agent.compare(b.agent)
}

///|
/// Apply a new operation using Kleppmann's undo-do-redo algorithm:
/// 1. Find where this op belongs in the timestamp-sorted log
/// 2. Undo all ops with higher timestamp
/// 3. Apply the new op (skip if it creates a cycle)
/// 4. Redo all undone ops in order (skip any that now create a cycle)
pub fn OpLog::apply(
  self : OpLog,
  tree : MovableTree,
  op : TreeMoveOp,
) -> Unit {
  // Find insertion point in sorted order
  let mut insert_idx = self.ops.length()
  while insert_idx > 0 && op_order(self.ops[insert_idx - 1], op) > 0 {
    insert_idx = insert_idx - 1
  }

  // Phase 1: Undo all ops from the end back to insert_idx
  // We need to record what we undo so we can redo
  let undo_stack : Array[(TreeMoveOp, TreeNodeId, @fi.FractionalIndex)] = []
  for i = self.ops.length() - 1; i >= insert_idx; i = i - 1 {
    if self.applied[i] {
      let old_op = self.ops[i]
      // Record current state before undo
      match tree.nodes[old_op.target] {
        Some(node) => {
          undo_stack.push((old_op, node.parent, node.position))
          // Undo: we need the PREVIOUS state of this node.
          // Since we don't store it, we reconstruct by replaying
          // For simplicity: undo = move back to state before this op
        }
        None => ()
      }
    }
  }

  // Actually, Kleppmann's algorithm is simpler:
  // We store the PREVIOUS parent/position for each applied op.
  // Let's redesign with that.
  self.apply_with_history(tree, op, insert_idx)
}

///|
/// Internal state tracking previous parent for each op.
struct AppliedState {
  old_parent : TreeNodeId
  old_position : @fi.FractionalIndex
}
```

Hmm, let me reconsider. The standard Kleppmann implementation stores the "old state" (previous parent) alongside each applied op, so undo can restore it. Let me restructure.

- [ ] **Step 3: Rewrite OpLog with proper state tracking**

Replace `conflict.mbt` entirely:

```moonbit
///|
/// Stores an applied move operation along with the state it replaced.
struct LogEntry {
  op : TreeMoveOp
  /// The parent and position the target had BEFORE this op was applied.
  /// None if the op was skipped (would create cycle).
  old_state : (TreeNodeId, @fi.FractionalIndex)?
}

///|
/// Operation log for the movable tree CRDT.
/// Implements Kleppmann's undo-do-redo for concurrent move conflict resolution.
pub struct OpLog {
  priv entries : Array[LogEntry]
}

///|
pub fn OpLog::new() -> OpLog {
  OpLog::{ entries: [] }
}

///|
fn op_order(a : TreeMoveOp, b : TreeMoveOp) -> Int {
  let ts_cmp = a.timestamp.compare(b.timestamp)
  if ts_cmp != 0 { return ts_cmp }
  a.agent.compare(b.agent)
}

///|
/// Apply a move to the tree, returning the old state if applied.
fn do_move(
  tree : MovableTree,
  op : TreeMoveOp,
) -> (TreeNodeId, @fi.FractionalIndex)? {
  // Check if target node exists; if not, create it (first-time create)
  match tree.nodes[op.target] {
    None => {
      // This is a create operation (node doesn't exist yet)
      // Create with the specified parent and position
      let node = TreeNode::{
        id: op.target,
        parent: op.new_parent,
        position: op.position,
        properties: Map::new(),
      }
      tree.nodes[op.target] = node
      match tree.children_cache[op.new_parent] {
        Some(children) => children.push(op.target)
        None => tree.children_cache[op.new_parent] = [op.target]
      }
      // Old state: was nowhere (use trash as sentinel for "didn't exist")
      Some((trash_id, @fi.FractionalIndex::new(b"\x00")))
    }
    Some(node) => {
      // Cycle check: skip if move would create a cycle
      if tree.would_create_cycle(op.target, op.new_parent) {
        return None // Skip this op
      }
      let old_parent = node.parent
      let old_position = node.position
      tree.move_node(target=op.target, new_parent=op.new_parent, position=op.position)
      Some((old_parent, old_position))
    }
  }
}

///|
/// Undo a previously applied move by restoring the old state.
fn undo_move(tree : MovableTree, op : TreeMoveOp, old_state : (TreeNodeId, @fi.FractionalIndex)) -> Unit {
  tree.move_node(target=op.target, new_parent=old_state.0, position=old_state.1)
}

///|
/// Apply a new operation using Kleppmann's undo-do-redo.
pub fn OpLog::apply(
  self : OpLog,
  tree : MovableTree,
  op : TreeMoveOp,
) -> Unit {
  // Find insertion point in timestamp-sorted order
  let mut insert_idx = self.entries.length()
  while insert_idx > 0 && op_order(self.entries[insert_idx - 1].op, op) > 0 {
    insert_idx = insert_idx - 1
  }

  // Phase 1: Undo all entries after insert_idx (in reverse order)
  for i = self.entries.length() - 1; i >= insert_idx; i = i - 1 {
    match self.entries[i].old_state {
      Some(old_state) => undo_move(tree, self.entries[i].op, old_state)
      None => () // Was skipped (cycle), nothing to undo
    }
  }

  // Phase 2: Apply the new operation
  let new_old_state = do_move(tree, op)
  let new_entry = LogEntry::{ op, old_state: new_old_state }

  // Insert at the correct position
  self.entries.insert(insert_idx, new_entry)

  // Phase 3: Redo all entries after the new one
  for i = insert_idx + 1; i < self.entries.length(); i = i + 1 {
    let redo_old_state = do_move(tree, self.entries[i].op)
    self.entries[i] = LogEntry::{ op: self.entries[i].op, old_state: redo_old_state }
  }
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/movable_tree`
Expected: PASS (convergence test should pass now)

- [ ] **Step 4: Write concurrent cycle test**

Add to `convergence_test.mbt`:

```moonbit
///|
test "convergence: concurrent moves that would create cycle" {
  // Alice moves A under B (timestamp 1)
  // Bob moves B under A (timestamp 2)
  // Result: Bob's move wins (higher timestamp), Alice's move is skipped (would cycle)
  let pos = @fi.FractionalIndex::between(None, None)
  let nodeA = @movable_tree.TreeNodeId::{ agent: "alice", counter: 0 }
  let nodeB = @movable_tree.TreeNodeId::{ agent: "bob", counter: 0 }
  let root = @movable_tree.root_id

  let create_a = @movable_tree.TreeMoveOp::{
    timestamp: 1, target: nodeA, new_parent: root, position: pos, agent: "alice",
  }
  let create_b = @movable_tree.TreeMoveOp::{
    timestamp: 2, target: nodeB, new_parent: root, position: pos, agent: "bob",
  }
  let move_a_under_b = @movable_tree.TreeMoveOp::{
    timestamp: 3, target: nodeA, new_parent: nodeB, position: pos, agent: "alice",
  }
  let move_b_under_a = @movable_tree.TreeMoveOp::{
    timestamp: 4, target: nodeB, new_parent: nodeA, position: pos, agent: "bob",
  }

  // Peer 1: applies in order
  let tree1 = @movable_tree.MovableTree::new(agent_id="peer1")
  let log1 = @movable_tree.OpLog::new()
  apply_op(tree1, log1, create_a)
  apply_op(tree1, log1, create_b)
  apply_op(tree1, log1, move_a_under_b)
  apply_op(tree1, log1, move_b_under_a)

  // Peer 2: applies in reverse order
  let tree2 = @movable_tree.MovableTree::new(agent_id="peer2")
  let log2 = @movable_tree.OpLog::new()
  apply_op(tree2, log2, move_b_under_a)
  apply_op(tree2, log2, move_a_under_b)
  apply_op(tree2, log2, create_b)
  apply_op(tree2, log2, create_a)

  // Both peers should converge:
  // Bob's move (ts 4) is applied last → B under A
  // Alice's move (ts 3) would then create cycle → skipped
  // So: B under A, A under root
  inspect(tree1.parent(nodeB).unwrap() == nodeA, content="true")
  inspect(tree1.parent(nodeA).unwrap() == root, content="true")
  inspect(tree2.parent(nodeB).unwrap() == nodeA, content="true")
  inspect(tree2.parent(nodeA).unwrap() == root, content="true")
}

///|
test "convergence: three peers, random order" {
  let pos1 = @fi.FractionalIndex::new(b"\x40")
  let pos2 = @fi.FractionalIndex::new(b"\x80")
  let pos3 = @fi.FractionalIndex::new(b"\xC0")
  let n1 = @movable_tree.TreeNodeId::{ agent: "a", counter: 0 }
  let n2 = @movable_tree.TreeNodeId::{ agent: "b", counter: 0 }
  let n3 = @movable_tree.TreeNodeId::{ agent: "c", counter: 0 }
  let root = @movable_tree.root_id

  let ops : Array[@movable_tree.TreeMoveOp] = [
    @movable_tree.TreeMoveOp::{ timestamp: 1, target: n1, new_parent: root, position: pos1, agent: "a" },
    @movable_tree.TreeMoveOp::{ timestamp: 2, target: n2, new_parent: root, position: pos2, agent: "b" },
    @movable_tree.TreeMoveOp::{ timestamp: 3, target: n3, new_parent: root, position: pos3, agent: "c" },
    @movable_tree.TreeMoveOp::{ timestamp: 4, target: n1, new_parent: n2, position: pos1, agent: "a" },
    @movable_tree.TreeMoveOp::{ timestamp: 5, target: n3, new_parent: n1, position: pos2, agent: "c" },
  ]

  // Apply in 3 different orders
  let orders : Array[Array[Int]] = [
    [0, 1, 2, 3, 4],   // In order
    [4, 3, 2, 1, 0],   // Reverse
    [2, 0, 4, 1, 3],   // Random
  ]

  let results : Array[(TreeNodeId, TreeNodeId, TreeNodeId)] = []
  for order in orders {
    let tree = @movable_tree.MovableTree::new()
    let log = @movable_tree.OpLog::new()
    for idx in order {
      apply_op(tree, log, ops[idx])
    }
    results.push((
      tree.parent(n1).unwrap(),
      tree.parent(n2).unwrap(),
      tree.parent(n3).unwrap(),
    ))
  }

  // All three orderings should produce same result
  inspect(results[0] == results[1], content="true")
  inspect(results[1] == results[2], content="true")
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/movable_tree`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd event-graph-walker
git add internal/movable_tree/conflict.mbt internal/movable_tree/convergence_test.mbt
git commit -m "feat: implement Kleppmann's undo-do-redo for MovableTree"
```

---

### Task 5: TreeDoc Public API

A public API mirroring TextDoc's pattern — handle-based, with version tracking and sync.

**Files:**
- Create: `event-graph-walker/tree/tree_doc.mbt`
- Create: `event-graph-walker/tree/tree_doc_test.mbt`
- Create: `event-graph-walker/tree/moon.pkg.json`

- [ ] **Step 1: Create moon.pkg.json**

```json
{
  "import": [
    "dowdiness/event-graph-walker/internal/movable_tree" "@mt",
    "dowdiness/event-graph-walker/internal/fractional_index" "@fi",
    "dowdiness/event-graph-walker/internal/causal_graph" "@cg"
  ]
}
```

Run: `cd event-graph-walker && moon check`
Expected: PASS

- [ ] **Step 2: Write failing test for TreeDoc basic usage**

In `tree_doc_test.mbt`:

```moonbit
///|
test "TreeDoc: create nodes and query structure" {
  let doc = @tree.TreeDoc::new("alice")
  let root = @tree.root_id
  let a = doc.create_node(parent=root)
  doc.set_property(a, "type", "heading")
  doc.set_property(a, "level", "1")
  let b = doc.create_node(parent=root)
  doc.set_property(b, "type", "paragraph")
  inspect(doc.children(root).length(), content="2")
  inspect(doc.get_property(a, "type"), content="Some(heading)")
  inspect(doc.is_alive(a), content="true")
}

///|
test "TreeDoc: move and delete" {
  let doc = @tree.TreeDoc::new("alice")
  let root = @tree.root_id
  let a = doc.create_node(parent=root)
  let b = doc.create_node(parent=root)
  // Move a under b
  doc.move_node(target=a, new_parent=b)
  inspect(doc.children(b).length(), content="1")
  inspect(doc.children(root).length(), content="1")
  // Delete a
  doc.delete_node(a)
  inspect(doc.is_alive(a), content="false")
  inspect(doc.children(b).length(), content="0")
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/tree`
Expected: FAIL — `TreeDoc` not defined

- [ ] **Step 3: Implement TreeDoc**

In `tree_doc.mbt`:

```moonbit
///|
pub let root_id : @mt.TreeNodeId = @mt.root_id

///|
pub let trash_id : @mt.TreeNodeId = @mt.trash_id

///|
pub struct TreeDoc {
  priv tree : @mt.MovableTree
  priv log : @mt.OpLog
  priv agent_id : String
  priv mut lamport : Int
}

///|
pub fn TreeDoc::new(agent_id : String) -> TreeDoc {
  TreeDoc::{
    tree: @mt.MovableTree::new(agent_id~),
    log: @mt.OpLog::new(),
    agent_id,
    lamport: 0,
  }
}

///|
fn TreeDoc::next_timestamp(self : TreeDoc) -> Int {
  self.lamport = self.lamport + 1
  self.lamport
}

///|
pub fn TreeDoc::create_node(
  self : TreeDoc,
  parent~ : @mt.TreeNodeId,
) -> @mt.TreeNodeId {
  let id = @mt.TreeNodeId::{ agent: self.agent_id, counter: self.lamport }
  let ts = self.next_timestamp()
  // Compute position: append after last child
  let children = self.tree.children(parent)
  let last_pos : @fi.FractionalIndex? = if children.is_empty() {
    None
  } else {
    let last = children[children.length() - 1]
    self.tree.get_position(last)
  }
  let position = @fi.FractionalIndex::between(last_pos, None)
  let op = @mt.TreeMoveOp::{
    timestamp: ts, target: id, new_parent: parent, position, agent: self.agent_id,
  }
  self.log.apply(self.tree, op)
  id
}

///|
pub fn TreeDoc::move_node(
  self : TreeDoc,
  target~ : @mt.TreeNodeId,
  new_parent~ : @mt.TreeNodeId,
) -> Unit {
  let ts = self.next_timestamp()
  let children = self.tree.children(new_parent)
  let last_pos : @fi.FractionalIndex? = if children.is_empty() {
    None
  } else {
    let last = children[children.length() - 1]
    self.tree.get_position(last)
  }
  let position = @fi.FractionalIndex::between(last_pos, None)
  let op = @mt.TreeMoveOp::{
    timestamp: ts, target, new_parent, position, agent: self.agent_id,
  }
  self.log.apply(self.tree, op)
}

///|
pub fn TreeDoc::move_node_before(
  self : TreeDoc,
  target~ : @mt.TreeNodeId,
  new_parent~ : @mt.TreeNodeId,
  before~ : @mt.TreeNodeId,
) -> Unit {
  let ts = self.next_timestamp()
  let children = self.tree.children(new_parent)
  let before_pos = self.tree.get_position(before)
  // Find the child before `before`
  let mut prev_pos : @fi.FractionalIndex? = None
  for child in children {
    if child == before {
      break
    }
    prev_pos = self.tree.get_position(child)
  }
  let position = @fi.FractionalIndex::between(prev_pos, before_pos)
  let op = @mt.TreeMoveOp::{
    timestamp: ts, target, new_parent, position, agent: self.agent_id,
  }
  self.log.apply(self.tree, op)
}

///|
pub fn TreeDoc::delete_node(self : TreeDoc, target : @mt.TreeNodeId) -> Unit {
  let ts = self.next_timestamp()
  let op = @mt.TreeMoveOp::{
    timestamp: ts,
    target,
    new_parent: @mt.trash_id,
    position: @fi.FractionalIndex::new(b"\x00"),
    agent: self.agent_id,
  }
  self.log.apply(self.tree, op)
}

///|
pub fn TreeDoc::children(
  self : TreeDoc,
  parent : @mt.TreeNodeId,
) -> Array[@mt.TreeNodeId] {
  self.tree.children(parent)
}

///|
pub fn TreeDoc::is_alive(
  self : TreeDoc,
  id : @mt.TreeNodeId,
) -> Bool {
  self.tree.is_alive(id)
}

///|
pub fn TreeDoc::set_property(
  self : TreeDoc,
  id : @mt.TreeNodeId,
  key : String,
  value : String,
) -> Unit {
  self.tree.set_property(id, key, value)
}

///|
pub fn TreeDoc::get_property(
  self : TreeDoc,
  id : @mt.TreeNodeId,
  key : String,
) -> String? {
  self.tree.get_property(id, key)
}
```

We also need to add `get_position` to `MovableTree`. Add to `tree.mbt`:

```moonbit
///|
pub fn MovableTree::get_position(
  self : MovableTree,
  id : TreeNodeId,
) -> @fi.FractionalIndex? {
  match self.nodes[id] {
    Some(node) => Some(node.position)
    None => None
  }
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/tree`
Expected: PASS

- [ ] **Step 4: Write sync convergence test**

Add to `tree_doc_test.mbt`:

```moonbit
///|
test "TreeDoc: two peers converge after sync" {
  let alice = @tree.TreeDoc::new("alice")
  let bob = @tree.TreeDoc::new("bob")
  let root = @tree.root_id

  // Alice creates two nodes
  let a1 = alice.create_node(parent=root)
  alice.set_property(a1, "type", "heading")
  let a2 = alice.create_node(parent=root)
  alice.set_property(a2, "type", "paragraph")

  // Bob creates a node
  let b1 = bob.create_node(parent=root)
  bob.set_property(b1, "type", "list_item")

  // Export ops from both
  let alice_ops = alice.export_ops()
  let bob_ops = bob.export_ops()

  // Cross-apply
  for op in bob_ops {
    alice.apply_remote_op(op)
  }
  for op in alice_ops {
    bob.apply_remote_op(op)
  }

  // Both should have 3 children under root
  inspect(alice.children(root).length(), content="3")
  inspect(bob.children(root).length(), content="3")

  // Same children in same order
  let alice_children = alice.children(root)
  let bob_children = bob.children(root)
  for i = 0; i < 3; i = i + 1 {
    inspect(alice_children[i] == bob_children[i], content="true")
  }
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/tree`
Expected: FAIL — `export_ops` and `apply_remote_op` not defined

- [ ] **Step 5: Implement export_ops and apply_remote_op**

Add to `tree_doc.mbt`:

```moonbit
///|
pub fn TreeDoc::export_ops(self : TreeDoc) -> Array[@mt.TreeMoveOp] {
  self.log.all_ops()
}

///|
pub fn TreeDoc::apply_remote_op(self : TreeDoc, op : @mt.TreeMoveOp) -> Unit {
  // Update Lamport clock: max(local, remote) + 1
  if op.timestamp >= self.lamport {
    self.lamport = op.timestamp
  }
  self.log.apply(self.tree, op)
}
```

Add to `conflict.mbt`:

```moonbit
///|
pub fn OpLog::all_ops(self : OpLog) -> Array[TreeMoveOp] {
  self.entries.map(fn(e) { e.op })
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/tree`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
cd event-graph-walker
git add tree/ internal/movable_tree/tree.mbt internal/movable_tree/conflict.mbt
git commit -m "feat: add TreeDoc public API with sync support"
```

---

### Task 6: Property-Based Convergence Tests

Randomized testing to verify that all operation orderings converge to the same tree state.

**Files:**
- Create: `event-graph-walker/internal/movable_tree/convergence_properties_test.mbt`

- [ ] **Step 1: Write property test for universal convergence**

In `convergence_properties_test.mbt`:

```moonbit
///|
/// Generate a random sequence of tree ops, apply them in every permutation
/// of 2-peer ordering, and verify all peers converge.
test "property: all 2-peer orderings converge for 5 random ops" {
  // Fixed seed scenario: 3 nodes, 5 operations
  let pos = @fi.FractionalIndex::between(None, None)
  let n1 = @movable_tree.TreeNodeId::{ agent: "a", counter: 0 }
  let n2 = @movable_tree.TreeNodeId::{ agent: "b", counter: 0 }
  let n3 = @movable_tree.TreeNodeId::{ agent: "c", counter: 0 }
  let root = @movable_tree.root_id

  let ops : Array[@movable_tree.TreeMoveOp] = [
    @movable_tree.TreeMoveOp::{ timestamp: 1, target: n1, new_parent: root, position: @fi.FractionalIndex::new(b"\x40"), agent: "a" },
    @movable_tree.TreeMoveOp::{ timestamp: 2, target: n2, new_parent: root, position: @fi.FractionalIndex::new(b"\x80"), agent: "b" },
    @movable_tree.TreeMoveOp::{ timestamp: 3, target: n3, new_parent: n1, position: pos, agent: "c" },
    @movable_tree.TreeMoveOp::{ timestamp: 4, target: n2, new_parent: n3, position: pos, agent: "b" },
    @movable_tree.TreeMoveOp::{ timestamp: 5, target: n1, new_parent: n2, position: pos, agent: "a" },
    // This last op creates a potential cycle: n1 -> n2 -> n3 -> n1
  ]

  // Apply in multiple orderings
  let orderings : Array[Array[Int]] = [
    [0, 1, 2, 3, 4],
    [4, 3, 2, 1, 0],
    [2, 4, 0, 3, 1],
    [1, 3, 0, 4, 2],
    [3, 0, 4, 1, 2],
    [4, 0, 2, 1, 3],
  ]

  // Collect parent state from each ordering
  let results : Array[Array[@movable_tree.TreeNodeId]] = []
  for order in orderings {
    let tree = @movable_tree.MovableTree::new()
    let log = @movable_tree.OpLog::new()
    for idx in order {
      log.apply(tree, ops[idx])
    }
    let state = [n1, n2, n3].map(fn(n) { tree.parent(n).unwrap() })
    results.push(state)
  }

  // All orderings should produce identical state
  for i = 1; i < results.length(); i = i + 1 {
    for j = 0; j < 3; j = j + 1 {
      inspect(results[i][j] == results[0][j], content="true")
    }
  }

  // Verify no cycles: every node should be reachable to root
  let tree = @movable_tree.MovableTree::new()
  let log = @movable_tree.OpLog::new()
  for op in ops {
    log.apply(tree, op)
  }
  for n in [n1, n2, n3] {
    let mut current = n
    let mut steps = 0
    while current != root && current != @movable_tree.trash_id && steps < 10 {
      current = tree.parent(current).unwrap()
      steps = steps + 1
    }
    // Should reach root or trash within 10 steps (no infinite loop = no cycle)
    inspect(steps < 10, content="true")
  }
}
```

Run: `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/movable_tree`
Expected: PASS

- [ ] **Step 2: Commit**

```bash
cd event-graph-walker
git add internal/movable_tree/convergence_properties_test.mbt
git commit -m "test: add property-based convergence tests for MovableTree"
```

---

### Task 7: Interface Files and Format

Generate `.mbti` interface files and run formatting.

**Files:**
- All new packages

- [ ] **Step 1: Generate interfaces and format**

```bash
cd event-graph-walker && moon info && moon fmt
```

Expected: `.mbti` files generated for `internal/fractional_index/`, `internal/movable_tree/`, `tree/`

- [ ] **Step 2: Verify API surface**

```bash
cd event-graph-walker && moon check
```

Expected: PASS with no warnings

- [ ] **Step 3: Check interface diffs**

```bash
cd event-graph-walker && git diff *.mbti
```

Review: New `.mbti` files for the 3 new packages. No changes to existing packages.

- [ ] **Step 4: Run all tests (existing + new)**

```bash
cd event-graph-walker && moon test
```

Expected: All existing tests still pass. All new tests pass.

- [ ] **Step 5: Commit**

```bash
cd event-graph-walker
git add -A
git commit -m "chore: generate interfaces and format for MovableTree packages"
```

---

## Notes for the Implementing Engineer

**MoonBit conventions to follow:**
- `///|` block separator between items
- `pub impl Trait for Type with method(self) { ... }` — one method per impl block
- `*_test.mbt` for blackbox tests, `*_wbtest.mbt` for whitebox tests
- `inspect(expr, content="expected")` for snapshot assertions
- Always `moon info && moon fmt` before committing

**The FractionalIndex implementation above is a starting point.** The `between()` algorithm handles basic cases but may need refinement for edge cases with very long byte sequences. The property tests should catch issues. If `between()` produces keys that aren't strictly ordered, the bug is in the midpoint calculation — add more test cases for the specific failing input pair.

**Kleppmann's undo-do-redo is O(n) per operation** in the worst case (when an operation arrives with timestamp 0, everything must be undone and redone). This is acceptable for the block editor use case (operations arrive roughly in order, with small reorderings for network latency). If performance becomes an issue, the log can be segmented by timestamp ranges.

**The property map on TreeNode is `Map[String, String]`** for simplicity. The block editor will use keys like `"type"`, `"level"`, `"style"`, `"checked"`. Property changes are NOT CRDT operations yet — they're local mutations. Making properties CRDT-safe (last-writer-wins per key) is a follow-up task for Plan 3 (block document model).
