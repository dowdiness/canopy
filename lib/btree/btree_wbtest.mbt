// White-box tests for dowdiness/btree.
//
// Uses a simple test element: TItem(id, span) where merging combines
// adjacent items with the same id, and slicing adjusts span.

///|
struct TItem {
  id : Int
  span : Int
} derive(Debug, Eq)

///|
impl Show for TItem with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
impl @rle.HasLength for TItem with length(self) -> Int {
  self.span
}

///|
impl @rle.Spanning for TItem with span(self) -> Int {
  self.span
}

///|
impl @rle.Mergeable for TItem with can_merge(a : TItem, b : TItem) -> Bool {
  a.id == b.id
}

///|
impl @rle.Mergeable for TItem with merge(a : TItem, b : TItem) -> TItem {
  { id: a.id, span: a.span + b.span }
}

///|
impl @rle.Sliceable for TItem with slice(self : TItem, start~ : Int, end~ : Int) -> Result[
  TItem,
  @rle.RleError,
] {
  if start < 0 || end > self.span || start >= end {
    Err(@rle.RleError::InvalidSlice(reason=@rle.SliceError::InvalidIndex))
  } else {
    Ok({ id: self.id, span: end - start })
  }
}

///|
impl BTreeElem for TItem

///|
fn make_item(id : Int, span : Int) -> TItem {
  { id, span }
}

///|
fn build_tree(items : Array[(Int, Int)]) -> BTree[TItem] {
  let t : BTree[TItem] = BTree::new(min_degree=2)
  if items.is_empty() {
    return t
  }
  let (id, span) = items[0]
  t.init_root(make_item(id, span), span)
  let mut pos = span
  for i in 1..<items.length() {
    let (id, span) = items[i]
    let elem = make_item(id, span)
    t.mutate_for_insert(pos, fn(ctx) {
      // Insert after current leaf (at end of span)
      {
        start_idx: ctx.child_idx + 1,
        end_idx: ctx.child_idx + 1,
        new_leaves: [(elem, span)],
      }
    })
    pos = pos + span
  }
  t
}

// === Construction & basic queries ===

///|
test "new tree is empty" {
  let t : BTree[TItem] = BTree::new()
  inspect(t.is_empty(), content="true")
  inspect(t.size(), content="0")
  inspect(t.span(), content="0")
}

///|
test "init_root creates single-element tree" {
  let t : BTree[TItem] = BTree::new()
  t.init_root(make_item(1, 5), 5)
  inspect(t.is_empty(), content="false")
  inspect(t.size(), content="1")
  inspect(t.span(), content="5")
}

///|
test "get_at on single element" {
  let t = build_tree([(1, 3)])
  inspect(
    t.get_at(0),
    content=(
      #|Some({ id: 1, span: 3 })
    ),
  )
  inspect(
    t.get_at(1),
    content=(
      #|Some({ id: 1, span: 3 })
    ),
  )
  inspect(
    t.get_at(2),
    content=(
      #|Some({ id: 1, span: 3 })
    ),
  )
  inspect(t.get_at(3), content="None")
  inspect(t.get_at(-1), content="None")
}

///|
test "find returns offset within element" {
  let t = build_tree([(1, 5)])
  inspect(
    t.find(0),
    content=(
      #|Some({ elem: { id: 1, span: 5 }, offset: 0 })
    ),
  )
  inspect(
    t.find(3),
    content=(
      #|Some({ elem: { id: 1, span: 5 }, offset: 3 })
    ),
  )
  inspect(t.find(5), content="None")
}

// === Insert ===

///|
test "insert multiple elements" {
  let t = build_tree([(1, 3), (2, 2), (3, 4)])
  inspect(t.size(), content="3")
  inspect(t.span(), content="9")
  inspect(
    t.get_at(0),
    content=(
      #|Some({ id: 1, span: 3 })
    ),
  )
  inspect(
    t.get_at(3),
    content=(
      #|Some({ id: 2, span: 2 })
    ),
  )
  inspect(
    t.get_at(5),
    content=(
      #|Some({ id: 3, span: 4 })
    ),
  )
}

///|
test "insert causes split with small min_degree" {
  // min_degree=2: max 4 children per node, splits at 5
  let t = build_tree([(1, 1), (2, 1), (3, 1), (4, 1), (5, 1)])
  inspect(t.size(), content="5")
  inspect(t.span(), content="5")
  // All elements should be navigable
  for i in 0..<5 {
    inspect(t.get_at(i) is Some(_), content="true")
  }
}

// === Delete ===

///|
test "delete single element empties tree" {
  let t = build_tree([(1, 3)])
  let deleted = t.mutate_for_delete(0, fn(ctx) {
    (
      { start_idx: ctx.child_idx, end_idx: ctx.child_idx + 1, new_leaves: [] },
      ctx.elem,
    )
  })
  inspect(
    deleted,
    content=(
      #|Some({ id: 1, span: 3 })
    ),
  )
  inspect(t.is_empty(), content="true")
}

///|
test "delete on empty returns None" {
  let t : BTree[TItem] = BTree::new()
  let result : Unit? = t.mutate_for_delete(0, fn(_ctx) {
    abort("should not be called")
  })
  inspect(result, content="None")
}

///|
test "panic insert on empty tree aborts" {
  let t : BTree[TItem] = BTree::new()
  t.mutate_for_insert(0, fn(_ctx) { abort("should not reach callback") })
}

// === Iteration ===

///|
test "each visits all elements in order" {
  let t = build_tree([(1, 2), (2, 3), (3, 1)])
  let ids : Array[Int] = []
  t.each(fn(item) { ids.push(item.id) })
  inspect(
    ids,
    content=(
      #|[1, 2, 3]
    ),
  )
}

///|
test "to_array collects all elements" {
  let t = build_tree([(10, 1), (20, 1)])
  let arr = t.to_array()
  inspect(arr.length(), content="2")
  inspect(
    arr[0].id,
    content=(
      #|10
    ),
  )
  inspect(
    arr[1].id,
    content=(
      #|20
    ),
  )
}

// === View ===

///|
test "view full range" {
  let t = build_tree([(1, 5)])
  let v = t.view()
  inspect(v.length(), content="1")
  inspect(
    v[0],
    content=(
      #|{ id: 1, span: 5 }
    ),
  )
}

///|
test "view sliced range" {
  let t = build_tree([(1, 5)])
  let v = t.view(start=1, end=4)
  inspect(v.length(), content="1")
  inspect(
    v[0],
    content=(
      #|{ id: 1, span: 3 }
    ),
  )
}

///|
test "view on empty tree" {
  let t : BTree[TItem] = BTree::new()
  let v = t.view()
  inspect(v.length(), content="0")
}

// === Node helpers ===

///|
test "node total" {
  let leaf : BTreeNode[TItem] = Leaf(elem=make_item(1, 5), span=5)
  inspect(leaf.total(), content="5")
}

///|
test "node height" {
  let leaf : BTreeNode[TItem] = Leaf(elem=make_item(1, 1), span=1)
  inspect(leaf.height(), content="0")
  let internal : BTreeNode[TItem] = Internal(
    children=[leaf],
    counts=[1],
    total=1,
  )
  inspect(internal.height(), content="1")
}

// === Multi-level delete & rebalancing ===

///|
test "delete from multi-level tree triggers rebalancing" {
  // Build a tree with enough elements to have 2+ levels (min_degree=2, splits at 5)
  let t = build_tree(Array::makei(10, fn(i) { (i, 1) }))
  inspect(t.size(), content="10")
  // Delete several elements from the front — triggers borrow/merge rebalancing
  for _ in 0..<5 {
    let deleted = t.mutate_for_delete(0, fn(ctx) {
      (
        { start_idx: ctx.child_idx, end_idx: ctx.child_idx + 1, new_leaves: [] },
        ctx.elem,
      )
    })
    inspect(deleted is Some(_), content="true")
  }
  inspect(t.size(), content="5")
  inspect(t.span(), content="5")
  // Remaining elements should still be navigable
  for i in 0..<5 {
    inspect(t.get_at(i) is Some(_), content="true")
  }
}

///|
test "delete all elements collapses tree to empty" {
  let t = build_tree(Array::makei(8, fn(i) { (i, 1) }))
  for _ in 0..<8 {
    let _ = t.mutate_for_delete(0, fn(ctx) {
      (
        { start_idx: ctx.child_idx, end_idx: ctx.child_idx + 1, new_leaves: [] },
        ctx.elem,
      )
    })
  }
  inspect(t.is_empty(), content="true")
  inspect(t.size(), content="0")
  inspect(t.span(), content="0")
}

// === Cross-leaf view ===

///|
test "view spanning multiple leaves" {
  // 5 elements each with span 2, total span 10
  let t = build_tree(Array::makei(5, fn(i) { (i, 2) }))
  inspect(t.span(), content="10")
  // View [1, 7) — starts mid-first-leaf, ends mid-fourth-leaf
  let v = t.view(start=1, end=7)
  // Should get sliced pieces from multiple leaves
  inspect(v.length() > 1, content="true")
  // Total span of view elements should be 6
  let mut total = 0
  for item in v {
    total = total + item.span
  }
  inspect(total, content="6")
}

///|
test "view with boundary clamping" {
  let t = build_tree([(1, 5)])
  // Start negative, end beyond span — should clamp
  let v = t.view(start=-10, end=100)
  inspect(v.length(), content="1")
  inspect(v[0].span, content="5")
}

// === Structural invariants ===

///|
test "many inserts preserve structure" {
  let t = build_tree(Array::makei(20, fn(i) { (i, 1) }))
  inspect(t.size(), content="20")
  inspect(t.span(), content="20")
  for i in 0..<20 {
    inspect(t.get_at(i) is Some(_), content="true")
  }
}

///|
test "insert then delete roundtrip" {
  let t = build_tree(Array::makei(15, fn(i) { (i, 1) }))
  // Delete all from the back
  for i in 14>=..0 {
    let _ = t.mutate_for_delete(i, fn(ctx) {
      (
        { start_idx: ctx.child_idx, end_idx: ctx.child_idx + 1, new_leaves: [] },
        ctx.elem,
      )
    })
  }
  inspect(t.is_empty(), content="true")
}

///|
test "descend_rightmost returns rightmost leaf with end offset" {
  let t = build_tree([(1, 3), (2, 2), (3, 4)])
  let root = t.root.unwrap()
  let cursor = descend_rightmost(root, [])
  // Should be at the rightmost leaf (id=3, span=4) with offset=span
  inspect(cursor.leaf_elem, content="{ id: 3, span: 4 }")
  inspect(cursor.offset, content="4")
  inspect(cursor.leaf_span, content="4")
}

// === Range delete tests (migrated from order-tree) ===

///|
test "shared_prefix_length handles same leaf and divergence" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 1), span=1),
      Leaf(elem=make_item(2, 1), span=1),
    ],
    counts=[1, 1],
    total=2,
  )
  let left = descend_leaf_at(root, 0, 2).unwrap()
  let right = descend_leaf_at(root, 1, 2).unwrap()
  inspect(shared_prefix_length(left.path, left.path), content="1")
  inspect(shared_prefix_length(left.path, right.path), content="0")
}

///|
test "lowest_common_ancestor_range handles same leaf" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
    ],
    counts=[3, 2],
    total=5,
  )
  let start = descend_leaf_at(root, 1, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 2, 2).unwrap()
  let range = lowest_common_ancestor_range(start, end_)
  inspect(range.prefix.length(), content="0")
  inspect(range.start_idx, content="0")
  inspect(range.end_idx, content="1")
  inspect(range.child_height, content="0")
}

///|
test "lowest_common_ancestor_range handles same parent different children" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 2), span=2),
      Leaf(elem=make_item(2, 2), span=2),
      Leaf(elem=make_item(3, 2), span=2),
    ],
    counts=[2, 2, 2],
    total=6,
  )
  let start = descend_leaf_at(root, 1, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 5, 2).unwrap()
  let range = lowest_common_ancestor_range(start, end_)
  inspect(range.prefix.length(), content="0")
  inspect(range.start_idx, content="0")
  inspect(range.end_idx, content="3")
  inspect(range.child_height, content="0")
}

///|
test "lowest_common_ancestor_range handles higher level divergence" {
  let left_child : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 1), span=1),
      Leaf(elem=make_item(2, 1), span=1),
    ],
    counts=[1, 1],
    total=2,
  )
  let right_child : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(3, 1), span=1),
      Leaf(elem=make_item(4, 1), span=1),
    ],
    counts=[1, 1],
    total=2,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left_child, right_child],
    counts=[2, 2],
    total=4,
  )
  let start = descend_leaf_at(root, 1, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 3, 2).unwrap()
  let range = lowest_common_ancestor_range(start, end_)
  inspect(range.prefix.length(), content="0")
  inspect(range.start_idx, content="0")
  inspect(range.end_idx, content="2")
  inspect(range.child_height, content="1")
}

///|
test "left_boundary_subtree returns none when start is on leaf boundary" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 2), span=2),
      Leaf(elem=make_item(2, 2), span=2),
    ],
    counts=[2, 2],
    total=4,
  )
  let start = descend_leaf_at(root, 2, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 4, 2).unwrap()
  let lca = lowest_common_ancestor_range(start, end_)
  inspect(left_boundary_subtree(lca, start) is None, content="true")
}

///|
test "right_boundary_subtree returns none when end is on leaf boundary" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 2), span=2),
      Leaf(elem=make_item(2, 2), span=2),
    ],
    counts=[2, 2],
    total=4,
  )
  let start = descend_leaf_at(root, 1, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 2, 2).unwrap()
  let lca = lowest_common_ancestor_range(start, end_)
  inspect(right_boundary_subtree(lca, end_) is None, content="true")
}

///|
test "left_boundary_subtree rebuilds to lca child height" {
  let left_child : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 2), span=2),
      Leaf(elem=make_item(2, 1), span=1),
    ],
    counts=[2, 1],
    total=3,
  )
  let right_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(3, 2), span=2)],
    counts=[2],
    total=2,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left_child, right_child],
    counts=[3, 2],
    total=5,
  )
  let start = descend_leaf_at(root, 1, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 4, 2).unwrap()
  let lca = lowest_common_ancestor_range(start, end_)
  let rebuilt = left_boundary_subtree(lca, start).unwrap()
  inspect(rebuilt.height(), content="1")
  inspect(rebuilt.total(), content="1")
}

///|
test "right_boundary_subtree rebuilds to lca child height" {
  let left_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 2), span=2)],
    counts=[2],
    total=2,
  )
  let right_child : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(2, 1), span=1),
      Leaf(elem=make_item(3, 2), span=2),
    ],
    counts=[1, 2],
    total=3,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left_child, right_child],
    counts=[2, 3],
    total=5,
  )
  let start = descend_leaf_at(root, 0, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 4, 2).unwrap()
  let lca = lowest_common_ancestor_range(start, end_)
  let rebuilt = right_boundary_subtree(lca, end_).unwrap()
  inspect(rebuilt.height(), content="1")
  inspect(rebuilt.total(), content="1")
}

///|
test "plan_delete_range handles same leaf splice" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 5), span=5),
      Leaf(elem=make_item(2, 2), span=2),
    ],
    counts=[5, 2],
    total=7,
  )
  let splice = plan_delete_range(root, 1, 4, 2).unwrap()
  inspect(splice.prefix.length(), content="0")
  inspect(splice.start_idx, content="0")
  inspect(splice.end_idx, content="1")
  inspect(splice.new_children.length(), content="1")
  inspect(splice.new_children[0].total(), content="2")
  inspect(splice.leaf_delta, content="0")
}

///|
test "plan_delete_range handles multi child lca splice" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 2), span=2),
      Leaf(elem=make_item(2, 2), span=2),
      Leaf(elem=make_item(3, 2), span=2),
    ],
    counts=[2, 2, 2],
    total=6,
  )
  let splice = plan_delete_range(root, 1, 5, 2).unwrap()
  inspect(splice.prefix.length(), content="0")
  inspect(splice.start_idx, content="0")
  inspect(splice.end_idx, content="3")
  inspect(splice.new_children.length(), content="2")
  inspect(splice.new_children[0].height(), content="0")
  inspect(splice.new_children[0].total(), content="1")
  inspect(splice.new_children[1].height(), content="0")
  inspect(splice.new_children[1].total(), content="1")
  inspect(splice.leaf_delta, content="-1")
}

///|
test "plan_delete_range merges partial kept boundaries in same parent" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
      Leaf(elem=make_item(1, 2), span=2),
    ],
    counts=[3, 2, 2],
    total=7,
  )
  let splice = plan_delete_range(root, 1, 6, 2).unwrap()
  inspect(splice.new_children.length(), content="1")
  inspect(splice.new_children[0].height(), content="0")
  inspect(splice.new_children[0].total(), content="2")
  inspect(splice.leaf_delta, content="-2")
}

///|
test "plan_delete_range merges partial kept boundaries across higher lca" {
  let left_child : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
    ],
    counts=[3, 2],
    total=5,
  )
  let right_child : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(3, 2), span=2),
      Leaf(elem=make_item(1, 2), span=2),
    ],
    counts=[2, 2],
    total=4,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left_child, right_child],
    counts=[5, 4],
    total=9,
  )
  let splice = plan_delete_range(root, 1, 8, 2).unwrap()
  inspect(splice.prefix.length(), content="0")
  inspect(splice.start_idx, content="0")
  inspect(splice.end_idx, content="2")
  inspect(splice.new_children.length(), content="1")
  inspect(splice.new_children[0].height(), content="1")
  inspect(splice.new_children[0].total(), content="2")
  inspect(splice.leaf_delta, content="-3")
}

///|
test "plan_delete_range keeps split partial boundaries when not mergeable" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
      Leaf(elem=make_item(3, 2), span=2),
    ],
    counts=[3, 2, 2],
    total=7,
  )
  let splice = plan_delete_range(root, 1, 6, 2).unwrap()
  inspect(splice.new_children.length(), content="2")
  inspect(splice.new_children[0].total(), content="1")
  inspect(splice.new_children[1].total(), content="1")
}

///|
test "plan_delete_range absorbs exact leaf-level gap merge" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
      Leaf(elem=make_item(1, 2), span=2),
    ],
    counts=[3, 2, 2],
    total=7,
  )
  let splice = plan_delete_range(root, 3, 5, 2).unwrap()
  inspect(splice.start_idx, content="0")
  inspect(splice.end_idx, content="3")
  inspect(splice.new_children.length(), content="1")
  inspect(splice.new_children[0].total(), content="5")
  inspect(splice.leaf_delta, content="-2")
}

///|
test "plan_delete_range absorbs exact higher-level gap merge" {
  let left_child : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(5, 1), span=1),
      Leaf(elem=make_item(1, 2), span=2),
    ],
    counts=[1, 2],
    total=3,
  )
  let middle_child : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(2, 2), span=2)],
    counts=[2],
    total=2,
  )
  let right_child : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(6, 1), span=1),
    ],
    counts=[3, 1],
    total=4,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left_child, middle_child, right_child],
    counts=[3, 2, 4],
    total=9,
  )
  let splice = plan_delete_range(root, 3, 5, 2).unwrap()
  inspect(splice.start_idx, content="0")
  inspect(splice.end_idx, content="3")
  inspect(splice.new_children.length(), content="1")
  inspect(splice.new_children[0].height(), content="1")
  inspect(splice.new_children[0].total(), content="7")
  inspect(splice.leaf_delta, content="-2")
}

// === Test debt: LeafContext ===

///|
test "LeafContext::from_cursor extracts leaf info" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
    ],
    counts=[3, 2],
    total=5,
  )
  let cursor = descend(root, 0, 2, prepare_noop, find_slot, false).unwrap()
  let ctx = LeafContext::from_cursor(cursor)
  inspect(ctx.elem, content="{ id: 1, span: 3 }")
  inspect(ctx.span, content="3")
  inspect(ctx.child_idx, content="0")
}

///|
test "LeafContext neighbors return adjacent siblings" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
      Leaf(elem=make_item(3, 4), span=4),
    ],
    counts=[3, 2, 4],
    total=9,
  )
  // Middle leaf at position 3
  let cursor = descend(root, 3, 2, prepare_noop, find_slot, false).unwrap()
  let ctx = LeafContext::from_cursor(cursor)
  inspect(ctx.left_neighbor(), content="Some({ id: 1, span: 3 })")
  inspect(ctx.right_neighbor(), content="Some({ id: 3, span: 4 })")
}

///|
test "LeafContext boundary neighbors are None" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
    ],
    counts=[3, 2],
    total=5,
  )
  // First leaf — no left neighbor
  let left_cursor = descend(root, 0, 2, prepare_noop, find_slot, false).unwrap()
  let left_ctx = LeafContext::from_cursor(left_cursor)
  inspect(left_ctx.left_neighbor() is None, content="true")
  inspect(left_ctx.right_neighbor(), content="Some({ id: 2, span: 2 })")
  // Last leaf — no right neighbor
  let right_cursor = descend(root, 3, 2, prepare_noop, find_slot, false).unwrap()
  let right_ctx = LeafContext::from_cursor(right_cursor)
  inspect(right_ctx.left_neighbor(), content="Some({ id: 1, span: 3 })")
  inspect(right_ctx.right_neighbor() is None, content="true")
}

// === Test debt: descend_leaf_at boundary semantics ===

///|
test "descend_leaf_at returns leaf containing position" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
    ],
    counts=[3, 2],
    total=5,
  )
  // Position 0 → first leaf, offset 0
  let leaf0 = descend_leaf_at(root, 0, 2).unwrap()
  inspect(leaf0.elem, content="{ id: 1, span: 3 }")
  inspect(leaf0.offset, content="0")
  // Position 2 → still first leaf, offset 2
  let leaf2 = descend_leaf_at(root, 2, 2).unwrap()
  inspect(leaf2.elem, content="{ id: 1, span: 3 }")
  inspect(leaf2.offset, content="2")
  // Position 3 → second leaf (at boundary, goes to next leaf)
  let leaf3 = descend_leaf_at(root, 3, 2).unwrap()
  inspect(leaf3.elem, content="{ id: 2, span: 2 }")
  inspect(leaf3.offset, content="0")
}

///|
test "descend_leaf_at_end_boundary stays at current leaf at boundary" {
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 3), span=3),
      Leaf(elem=make_item(2, 2), span=2),
    ],
    counts=[3, 2],
    total=5,
  )
  // End position 3 → first leaf (stays at current, offset=span=3)
  let leaf3 = descend_leaf_at_end_boundary(root, 3, 2).unwrap()
  inspect(leaf3.elem, content="{ id: 1, span: 3 }")
  inspect(leaf3.offset, content="3")
  inspect(leaf3.span, content="3")
  // End position 5 → second leaf (at end, offset=span=2)
  let leaf5 = descend_leaf_at_end_boundary(root, 5, 2).unwrap()
  inspect(leaf5.elem, content="{ id: 2, span: 2 }")
  inspect(leaf5.offset, content="2")
}

// === Test debt: ensure_min_children rebalancing ===

///|
test "ensure_min_children borrows from right sibling" {
  // min_degree=2: need at least 2 children
  let underfull : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 1), span=1)],
    counts=[1],
    total=1,
  )
  let donor : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(2, 1), span=1),
      Leaf(elem=make_item(3, 1), span=1),
      Leaf(elem=make_item(4, 1), span=1),
    ],
    counts=[1, 1, 1],
    total=3,
  )
  let children : Array[BTreeNode[TItem]] = [underfull, donor]
  let counts : Array[Int] = [1, 3]
  ensure_min_children(children, counts, 0, 2)
  // After borrow: underfull gets 2 children, donor keeps 2
  match children[0] {
    Internal(children=c, ..) => inspect(c.length(), content="2")
    _ => abort("expected internal node")
  }
  match children[1] {
    Internal(children=c, ..) => inspect(c.length(), content="2")
    _ => abort("expected internal node")
  }
  // Counts updated
  inspect(counts[0], content="2")
  inspect(counts[1], content="2")
}

// === Test debt: propagate_node_splice ===

///|
test "propagate_node_splice updates ancestor counts after removal" {
  // Build a 3-leaf tree: [a(2), b(3), c(4)] total=9
  let root : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 2), span=2),
      Leaf(elem=make_item(2, 3), span=3),
      Leaf(elem=make_item(3, 4), span=4),
    ],
    counts=[2, 3, 4],
    total=9,
  )
  // Splice that removes the middle child (index 1)
  let splice : NodeSplice[TItem] = {
    prefix: [],
    children: match root {
      Internal(children~, ..) => children
      _ => abort("expected internal")
    },
    counts: match root {
      Internal(counts~, ..) => counts
      _ => abort("expected internal")
    },
    start_idx: 1,
    end_idx: 2,
    new_children: [],
    original_child_count: 3,
    leaf_delta: -1,
  }
  let result = propagate_node_splice(splice, 2)
  inspect(result.leaf_delta, content="-1")
  // Resulting node should have total = 2 + 4 = 6
  inspect(result.node.total(), content="6")
}
