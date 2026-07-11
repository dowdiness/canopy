# CST Integration Plan for eg-walker CRDT

## Overview

Extend the eg-walker CRDT implementation to support Concrete Syntax Trees (CST) for programming language editors while preserving the existing text-based API. The design uses polymorphic content types, bidirectional tree navigation, ID-based operations, and adapts the FugueMax algorithm to support both linear text sequences and hierarchical syntax trees.

## Requirements Summary

- **CST Type**: Programming language AST/CST nodes with types and attributes
- **Conflict Resolution**: Preserve both conflicting nodes, order deterministically
- **API Style**: ID-based operations using stable LV identifiers
- **Compatibility**: Support both text and CST modes side-by-side

## Architecture Approach

### Dual-Mode Content Model
Items can contain either text strings (`Text(String)`) or CST nodes (`CSTNode(CSTNodeData)`). This enables both traditional text editing and structured tree editing within the same CRDT framework.

### Unified FugueMax Algorithm
The existing parent-finding algorithm works for both modes:
- **Text mode**: Parents represent sequential ordering
- **CST mode**: Parents represent both tree hierarchy (semantic parent-child) and sibling ordering (FugueMax conflict resolution)

### Two Parent Concepts
- **`Item.parent`**: FugueMax ordering parent (determines sibling order during concurrent inserts)
- **`CSTNodeData.parent_node`**: Semantic tree parent (the actual CST parent node)

This dual concept enables deterministic ordering of concurrent sibling insertions while maintaining semantic tree structure.

## Implementation Phases

### Phase 1: Data Model Foundation

**Objective**: Make Item content polymorphic without changing API behavior.

**Files to Create**:
- `fugue/cst_node.mbt` - CST node data structure

**Files to Modify**:
- `fugue/item.mbt`

**Changes**:

1. Create `ItemContent` enum:
```moonbit
pub enum ItemContent {
  Text(String)
  CSTNode(CSTNodeData)
} derive(Show, Eq)
```

2. Create `CSTNodeData` structure in new file:
```moonbit
pub struct CSTNodeData {
  node_type : String              // "function", "if_statement", "identifier"
  attributes : @immut/hashmap.HashMap[String, String]  // name="foo", type="int"
  parent_node : Int               // Semantic tree parent LV (-1 for root)
  children : Array[Int]           // Ordered child LVs
  text_value : String            // For leaf nodes (identifiers, literals)
} derive(Show, Eq)
```

3. Update `Item` struct to use `ItemContent`:
```moonbit
pub struct Item {
  id : Int
  content : ItemContent  // Changed from String
  parent : Int
  deleted : Bool
  timestamp : Int
}
```

4. Refactor constructors:
   - Rename `Item::new()` to `Item::new_text()`
   - Add `Item::new_cst_node()`
   - Update all callsites to use `Item::new_text()`

5. Add helper methods:
   - `is_text() -> Bool`
   - `is_cst_node() -> Bool`
   - `get_text() -> String?`
   - `get_cst_node() -> CSTNodeData?`

**Validation**: All existing tests pass with no behavior changes.

---

### Phase 2: Bidirectional Tree Navigation

**Objective**: Add children tracking to FugueTree for efficient CST traversal.

**Files to Modify**:
- `fugue/tree.mbt`

**Changes**:

1. Add `children_map` field to `FugueTree`:
```moonbit
pub struct FugueTree {
  mut items : @immut/hashmap.HashMap[Int, Item]
  root : Int
  mut length : Int
  mut children_map : @immut/hashmap.HashMap[Int, Array[Int]]  // NEW
}
```

2. Add navigation methods:
   - `get_children(parent_lv: Int) -> Array[Int]` - Get child LVs
   - `update_children_map(child_lv, parent_lv)` - Internal: update map on insert
   - `remove_from_children_map(child_lv, parent_lv)` - Internal: update on delete

3. Update `add_item()` to call `update_children_map()`

4. Update `delete()` to call `remove_from_children_map()`

5. Implement `to_tree()` for CST serialization:
```moonbit
pub fn FugueTree::to_tree(self : FugueTree, root_lv : Int) -> CSTTreeView?
```

6. Add `CSTTreeView` structure for external consumption:
```moonbit
pub struct CSTTreeView {
  lv : Int
  node_type : String
  attributes : @immut/hashmap.HashMap[String, String]
  text_value : String
  children : Array[CSTTreeView]
}
```

**Validation**: Children map stays synchronized with item additions/deletions.

---

### Phase 3: CST Operations

**Objective**: Extend OpContent with CST operation types.

**Files to Modify**:
- `oplog/operation.mbt`

**Changes**:

1. Extend `OpContent` enum:
```moonbit
pub enum OpContent {
  Insert(String)                    // Existing
  Delete                           // Existing
  InsertNode(CSTNodeInsert)        // NEW
  DeleteNode                       // NEW
  UpdateNodeAttributes(NodeAttrUpdate)  // NEW
}
```

2. Add new structures:
```moonbit
pub struct CSTNodeInsert {
  node_type : String
  attributes : @immut/hashmap.HashMap[String, String]
  parent_node : Int      // Semantic parent in CST
  text_value : String
}

pub struct NodeAttrUpdate {
  target_lv : Int        // Node to update
  attributes : @immut/hashmap.HashMap[String, String]
}
```

3. Add operation constructors:
   - `Op::new_insert_node(...) -> Op`
   - `Op::new_delete_node(...) -> Op`
   - `Op::new_update_attributes(...) -> Op`

**Files to Modify**:
- `fugue/tree.mbt`

**Changes**:

4. Add `FugueTree::insert_cst_node()`:
```moonbit
pub fn FugueTree::insert_cst_node(
  self : FugueTree,
  id : Int,
  node_data : CSTNodeData,
  origin_left : Int,
  origin_right : Int,
  timestamp : Int
) -> Unit
```

**Validation**: CST operations can be created and applied to tree.

---

### Phase 4: TreeDocument API

**Objective**: Create ID-based document API for CST editing.

**Files to Create**:
- `editor/tree_document.mbt`

**Structure**:
```moonbit
pub struct TreeDocument {
  tree : @fugue.FugueTree
  oplog : @oplog.OpLog
  agent_id : String
  mut root_nodes : Array[Int]  // Top-level CST nodes
}
```

**API Methods**:

1. **Constructor**:
   - `TreeDocument::new(agent_id: String) -> TreeDocument`

2. **Mutating Operations**:
   - `insert_child(parent_lv, position, node_type, text_value) -> Int` - Returns new node's LV
   - `delete_node(node_lv) -> Unit`
   - `update_attributes(node_lv, attributes) -> Unit`

3. **Query Operations**:
   - `get_node(lv) -> CSTNodeData?`
   - `get_children(parent_lv) -> Array[Int]`
   - `get_parent(node_lv) -> Int`
   - `to_tree() -> Array[CSTTreeView]`

4. **Merge Operations**:
   - `merge_remote(ops, frontier) -> Unit`
   - `apply_remote(op) -> Unit`
   - `get_frontier() -> Array[Int]`
   - `get_operations() -> Array[Op]`

**Key Implementation Details**:

**`insert_child` algorithm**:
1. Query parent's current children
2. Determine `origin_left` and `origin_right` based on position
3. Create `InsertNode` operation via OpLog
4. Apply to FugueTree using `insert_cst_node()`
5. Update parent's children list in `CSTNodeData`
6. Return new node's LV

**`delete_node` algorithm**:
1. Create `DeleteNode` operation
2. Mark node as deleted (tombstone)
3. Remove from parent's children list
4. Children become orphaned (application handles policy)

**`update_attributes` algorithm**:
1. Create `UpdateNodeAttributes` operation
2. Apply with last-write-wins based on timestamp
3. Update node's attributes map

**Validation**: Can build and manipulate CST trees, serialize to `CSTTreeView`.

---

### Phase 5: OpLog Extensions

**Objective**: Add OpLog methods for CST operations.

**Files to Modify**:
- `oplog/oplog.mbt`

**Changes**:

Add methods:
- `insert_node(node_type, attributes, parent_node, text_value, origin_left, origin_right) -> Op`
- `delete_node(target_lv) -> Op`
- `update_node_attributes(target_lv, attributes) -> Op`

Each method:
1. Gets current frontier
2. Adds version to causal graph
3. Creates operation with appropriate content
4. Adds to oplog
5. Returns operation

**Validation**: Operations can be created and stored in OpLog.

---

### Phase 6: Merge Algorithm Extensions

**Objective**: Handle CST operations during merge.

**Files to Modify**:
- `merge/merge.mbt`

**Changes**:

1. Extend `MergeContext::apply_operations()` to handle new operation types:

```moonbit
match op.content {
  @oplog.Insert(text) => { /* existing code */ }
  @oplog.Delete => { /* existing code */ }
  @oplog.InsertNode(insert_data) => {
    let node_data = @fugue.CSTNodeData::new(...)
    self.tree.insert_cst_node(op.lv, node_data, op.origin_left, op.origin_right, timestamp)
  }
  @oplog.DeleteNode => {
    self.tree.delete(op.origin_left)
  }
  @oplog.UpdateNodeAttributes(update_data) => {
    self.apply_attribute_update(update_data, timestamp)
  }
}
```

2. Add `apply_attribute_update()` helper:
   - Implements last-write-wins for attribute updates
   - Compares timestamps
   - Updates node's attributes map

**Conflict Resolution**:
- **Concurrent sibling inserts**: Both preserved, ordered by FugueMax (LV/timestamp)
- **Concurrent attribute updates**: Last-write-wins by Lamport timestamp
- **Insert-delete conflicts**: Handled by causal order (same as text mode)

**Validation**: Concurrent CST edits merge correctly.

---

### Phase 7: Public API

**Objective**: Expose CST API while maintaining backward compatibility.

**Files to Modify**:
- `crdt.mbt`

**Changes**:

Add CST API exports:
```moonbit
// CST types
pub type TreeDocument = @editor.TreeDocument
pub type CSTTreeView = @fugue.CSTTreeView
pub type CSTNodeData = @fugue.CSTNodeData

// CST functions
pub let new_tree_document : (String) -> TreeDocument
pub let insert_child : (TreeDocument, Int, Int, String, String) -> Int
pub let delete_node : (TreeDocument, Int) -> Unit
pub let update_node_attributes : (TreeDocument, Int, @immut/hashmap.HashMap[String, String]) -> Unit
pub let get_node : (TreeDocument, Int) -> CSTNodeData?
pub let get_children_lvs : (TreeDocument, Int) -> Array[Int]
pub let get_parent_lv : (TreeDocument, Int) -> Int
pub let tree_to_tree : (TreeDocument) -> Array[CSTTreeView]
pub let tree_doc_merge_remote : (TreeDocument, Array[Op], Array[Int]) -> Unit
// ... etc
```

**Existing text API remains unchanged**:
- All existing exports continue working
- No breaking changes
- Regression tests pass

**Validation**: Both APIs work side-by-side.

---

## Critical Files Summary

### Must Modify
1. `fugue/item.mbt` - Polymorphic content (Text | CSTNode)
2. `fugue/tree.mbt` - Children tracking, CST insertion, to_tree()
3. `oplog/operation.mbt` - New operation types
4. `merge/merge.mbt` - Handle CST operations
5. `crdt.mbt` - Export CST API
6. `oplog/oplog.mbt` - Add CST operation methods

### Must Create
7. `fugue/cst_node.mbt` - CSTNodeData structure
8. `editor/tree_document.mbt` - ID-based CST API

## Testing Strategy

### Unit Tests
- `fugue/tree_test.mbt`: CST node insertion, deletion, children tracking, to_tree()
- `fugue/cst_node_test.mbt`: Node creation, attribute updates
- New operation tests for InsertNode, DeleteNode, UpdateAttributes

### Integration Tests
- Concurrent sibling inserts → both preserved, deterministic order
- Concurrent attribute updates → LWW convergence
- Delete during insert → proper conflict handling
- Multi-level tree construction and traversal

### Regression Tests
- All existing text-mode tests must pass unchanged
- Verify text operations don't interact with CST operations

## Design Tradeoffs

### Polymorphic Content vs Separate Trees
**Chosen**: Polymorphic `ItemContent` enum
- **Pro**: Single merge algorithm, code reuse, simpler architecture
- **Con**: Slightly larger Item size, pattern matching overhead

### Children Storage
**Chosen**: Store in both `CSTNodeData.children` and `FugueTree.children_map`
- **Pro**: Self-contained node data, easier serialization
- **Con**: Synchronization required (mitigated by clear ownership)

### Attribute Merge Strategy
**Chosen**: Whole-map last-write-wins
- **Pro**: Simple, works for most use cases
- **Con**: Coarse-grained (can enhance later with per-attribute LWW if needed)

### Delete Semantics
**Chosen**: Manual deletion (application-level policy)
- **Pro**: Flexible, application chooses recursive delete vs re-parent
- **Con**: More code for users (document recommended patterns)

## Potential Challenges & Mitigations

### Challenge 1: Two Parent Concepts
- **Mitigation**: Clear naming (`fugue_parent` vs `parent_node`), comprehensive documentation
- **Validation**: Unit tests verify both set correctly

### Challenge 2: Children List Synchronization
- **Mitigation**: Internal methods update both, to_tree() traverses actual structure
- **Alternative**: Only store in children_map, query on demand

### Challenge 3: Orphan Nodes After Delete
- **Mitigation**: CRDT provides primitives, application implements policy
- **Document**: Recommended patterns (recursive delete, re-parent, show conflict UI)

### Challenge 4: Testing Concurrent Scenarios
- **Mitigation**: Property-based tests, canonical conflict test cases
- **Categories**: Concurrent sibling inserts, insert during delete, attribute conflicts

## Future Enhancements

1. **Per-attribute LWW** with version vectors for finer-grained merge
2. **Language-specific adapters** (JavaScript AST, Python AST, etc.)
3. **Move operation** for subtree repositioning
4. **Schema validation** for tree invariants
5. **Performance optimizations** (ropes for large child lists, caching)
6. **3-way merge visualization** for UI conflict display

## Example Usage

### Creating a Simple CST

```moonbit
// Create a tree document
let doc = new_tree_document("agent1")

// Create a function node (top-level)
let func_lv = insert_child(doc, -1, 0, "function", "")

// Set function name
let attrs = @immut/hashmap.new().add("name", "main")
update_node_attributes(doc, func_lv, attrs)

// Add parameters as children
let param1 = insert_child(doc, func_lv, 0, "parameter", "x")
let param2 = insert_child(doc, func_lv, 1, "parameter", "y")

// Add function body
let body = insert_child(doc, func_lv, 2, "block", "")

// Add a statement to the body
let stmt = insert_child(doc, body, 0, "return_statement", "")
let expr = insert_child(doc, stmt, 0, "binary_expression", "")

// Set expression operator
let expr_attrs = @immut/hashmap.new().add("operator", "+")
update_node_attributes(doc, expr, expr_attrs)

// Add operands
let left = insert_child(doc, expr, 0, "identifier", "x")
let right = insert_child(doc, expr, 1, "identifier", "y")

// Serialize to tree view
let tree_views = tree_to_tree(doc)
```

This creates a CST representing:
```
function main(x, y) {
  return x + y
}
```

### Concurrent Editing

```moonbit
// Agent 1
let doc1 = new_tree_document("agent1")
let root = insert_child(doc1, -1, 0, "program", "")

// Agent 2 gets the same root
let doc2 = new_tree_document("agent2")
merge_remote(doc2, get_operations(doc1), get_frontier(doc1))

// Both add statements concurrently
let stmt_a = insert_child(doc1, root, 0, "statement", "a")
let stmt_b = insert_child(doc2, root, 0, "statement", "b")

// Merge
merge_remote(doc1, get_operations(doc2), get_frontier(doc2))
merge_remote(doc2, get_operations(doc1), get_frontier(doc1))

// Both converge to same tree with both statements
// Order determined by FugueMax algorithm
```

## Summary

This plan extends eg-walker to support CST editing while preserving the elegant FugueMax algorithm and causal graph infrastructure. The phased approach ensures each component is validated before building the next layer. The dual-mode design allows gradual adoption without breaking existing text-based usage.

**Estimated Complexity**: Medium-High (7 phases, 8 files)
**Key Innovation**: Dual parent concept enables FugueMax sibling ordering within semantic tree structure
**Risk Level**: Low (changes are additive, existing API unchanged)
