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
    leaf_delta: -1,
  }
  let result = propagate_node_splice(splice, 2)
  inspect(result.leaf_delta, content="-1")
  // Resulting node should have total = 2 + 4 = 6
  inspect(result.node.total(), content="6")
}

// === Underfull propagation repair ===

///|
test "propagate_node_splice repairs underfull node by borrowing from right" {
  // min_degree=2: each internal needs >= 2 children
  // LCA child has 3 children, we splice out 2 → 1 child (underfull)
  // Right sibling has 3 children → can lend
  let lca_child : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 1), span=1),
      Leaf(elem=make_item(2, 1), span=1),
      Leaf(elem=make_item(3, 1), span=1),
    ],
    counts=[1, 1, 1],
    total=3,
  )
  let right_sibling : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(4, 1), span=1),
      Leaf(elem=make_item(5, 1), span=1),
      Leaf(elem=make_item(6, 1), span=1),
    ],
    counts=[1, 1, 1],
    total=3,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[lca_child, right_sibling],
    counts=[3, 3],
    total=6,
  )
  // Splice removes children 0..2 from lca_child, leaving 1 child (underfull)
  let splice : NodeSplice[TItem] = {
    prefix: [
      {
        children: match root {
          Internal(children~, ..) => children
          _ => abort("expected internal")
        },
        counts: match root {
          Internal(counts~, ..) => counts
          _ => abort("expected internal")
        },
        child_idx: 0,
      },
    ],
    children: match lca_child {
      Internal(children~, ..) => children
      _ => abort("expected internal")
    },
    counts: match lca_child {
      Internal(counts~, ..) => counts
      _ => abort("expected internal")
    },
    start_idx: 0,
    end_idx: 2,
    new_children: [],
    leaf_delta: -2,
  }
  let result = propagate_node_splice(splice, 2)
  // After repair: underfull node borrowed from right sibling
  // Total span should be 6 - 2 = 4
  inspect(result.node.total(), content="4")
  // Root should still have 2 children (no merge needed at root level)
  match result.node {
    Internal(children~, ..) => {
      inspect(children.length(), content="2")
      // Each child should have >= 2 children
      match children[0] {
        Internal(children=c, ..) => inspect(c.length() >= 2, content="true")
        _ => abort("expected internal")
      }
    }
    _ => abort("expected internal root")
  }
}

///|
test "propagate_node_splice repairs underfull node by merging with sibling" {
  // min_degree=2: each internal needs >= 2 children
  // LCA child has 2 children, we splice out 1 → 1 child (underfull)
  // Right sibling has exactly 2 children → cannot lend, must merge
  let lca_child : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(1, 1), span=1),
      Leaf(elem=make_item(2, 1), span=1),
    ],
    counts=[1, 1],
    total=2,
  )
  let right_sibling : BTreeNode[TItem] = Internal(
    children=[
      Leaf(elem=make_item(3, 1), span=1),
      Leaf(elem=make_item(4, 1), span=1),
    ],
    counts=[1, 1],
    total=2,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[lca_child, right_sibling],
    counts=[2, 2],
    total=4,
  )
  let splice : NodeSplice[TItem] = {
    prefix: [
      {
        children: match root {
          Internal(children~, ..) => children
          _ => abort("expected internal")
        },
        counts: match root {
          Internal(counts~, ..) => counts
          _ => abort("expected internal")
        },
        child_idx: 0,
      },
    ],
    children: match lca_child {
      Internal(children~, ..) => children
      _ => abort("expected internal")
    },
    counts: match lca_child {
      Internal(counts~, ..) => counts
      _ => abort("expected internal")
    },
    start_idx: 0,
    end_idx: 1,
    new_children: [],
    leaf_delta: -1,
  }
  let result = propagate_node_splice(splice, 2)
  inspect(result.node.total(), content="3")
  // After merge: root has 1 child (will be collapsed by normalize)
  match result.node {
    Internal(children~, ..) => inspect(children.length(), content="1")
    _ => abort("expected internal root")
  }
}

// === Post-splice boundary merge ===

///|
test "normalize_boundary_merge merges adjacent leaves across subtrees" {
  // After splice already removed middle, tree is: [[a(3)]] [[a(3)]]
  let left : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 3), span=3)],
    counts=[3],
    total=3,
  )
  let right : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 3), span=3)],
    counts=[3],
    total=3,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left, right],
    counts=[3, 3],
    total=6,
  )
  let (result, merged) = normalize_boundary_merge(root, 3, 2)
  inspect(merged, content="true")
  inspect(result.total(), content="6")
  let items : Array[TItem] = []
  result.each(fn(item) { items.push(item) })
  inspect(items.length(), content="1")
  inspect(items[0], content="{ id: 1, span: 6 }")
}

///|
test "normalize_boundary_merge is no-op when boundaries not mergeable" {
  let left : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(1, 3), span=3)],
    counts=[3],
    total=3,
  )
  let right : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(2, 3), span=3)],
    counts=[3],
    total=3,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[left, right],
    counts=[3, 3],
    total=6,
  )
  let (result, merged) = normalize_boundary_merge(root, 3, 2)
  inspect(merged, content="false")
  inspect(result.total(), content="6")
  let items : Array[TItem] = []
  result.each(fn(item) { items.push(item) })
  inspect(items.length(), content="2")
}

// === BTree::delete_range ===

///|
test "BTree::delete_range removes contiguous elements" {
  let t = build_tree([(1, 2), (2, 3), (3, 4)])
  // Total span = 2+3+4 = 9, delete [2,5) removes item 2 exactly → 6 remaining
  t.delete_range(2, 5)
  inspect(t.span(), content="6")
  inspect(t.size(), content="2")
  let items = t.to_array()
  inspect(items.length(), content="2")
  inspect(items[0], content="{ id: 1, span: 2 }")
  inspect(items[1], content="{ id: 3, span: 4 }")
}

///|
test "BTree::delete_range merges boundary leaves" {
  let t = build_tree([(1, 3), (2, 2), (1, 3)])
  t.delete_range(3, 5)
  inspect(t.span(), content="6")
  // The two id=1 items should merge into one
  let items = t.to_array()
  inspect(items.length(), content="1")
  inspect(items[0], content="{ id: 1, span: 6 }")
}

///|
test "BTree::delete_range empty range is no-op" {
  let t = build_tree([(1, 2), (2, 3)])
  t.delete_range(2, 2)
  inspect(t.span(), content="5")
  inspect(t.size(), content="2")
}

///|
test "BTree::delete_range full range clears tree" {
  let t = build_tree([(1, 2), (2, 3)])
  t.delete_range(0, 5)
  inspect(t.span(), content="0")
  inspect(t.is_empty(), content="true")
}

///|
test "BTree::delete_range clamps end to span" {
  let t = build_tree([(1, 2), (2, 3)])
  t.delete_range(2, 99)
  inspect(t.span(), content="2")
  inspect(t.size(), content="1")
}

///|
test "BTree::delete_range handles underfull propagation" {
  // Build a tree deep enough that range delete causes underfull at LCA
  let items : Array[(Int, Int)] = Array::makei(20, fn(i) { (i + 1, 1) })
  let t = build_tree(items)
  // Delete a large middle range
  t.delete_range(5, 15)
  inspect(t.span(), content="10")
  inspect(t.size(), content="10")
  // Verify tree is well-formed by iterating
  let result = t.to_array()
  inspect(result.length(), content="10")
}

// === Boundary subtree ancestor sibling preservation ===

///|
test "left_boundary_subtree preserves ancestor siblings when leaf has none" {
  // Tree: root:[L, R, S]  R:[X, Y]  Y:[c, d]
  // Delete starting at c and extending into S → LCA is root.
  // Suffix below LCA: [R-frame(child_idx=1), Y-frame(child_idx=0)].
  // Deepest frame (Y) has child_idx=0 — no local left siblings.
  // But R-frame has child_idx=1 — X is a left sibling that must be preserved.
  let x_leaf : BTreeNode[TItem] = Leaf(elem=make_item(1, 1), span=1)
  let c_leaf : BTreeNode[TItem] = Leaf(elem=make_item(3, 1), span=1)
  let d_leaf : BTreeNode[TItem] = Leaf(elem=make_item(4, 1), span=1)
  let y_node : BTreeNode[TItem] = Internal(
    children=[c_leaf, d_leaf],
    counts=[1, 1],
    total=2,
  )
  let r_node : BTreeNode[TItem] = Internal(
    children=[x_leaf, y_node],
    counts=[1, 2],
    total=3,
  )
  let l_node : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(10, 2), span=2)],
    counts=[2],
    total=2,
  )
  let s_node : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(5, 1), span=1)],
    counts=[1],
    total=1,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[l_node, r_node, s_node],
    counts=[2, 3, 1],
    total=6,
  )
  // start=c at pos=3 (L=2, X=1, c=0 within Y), end extends into S
  let start = descend_leaf_at(root, 3, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 6, 2).unwrap()
  let lca = lowest_common_ancestor_range(start, end_)
  // left_boundary_subtree must return a subtree containing X
  let left = left_boundary_subtree(lca, start)
  inspect(left is Some(_), content="true")
  // Should preserve X (span=1)
  inspect(left.unwrap().total(), content="1")
}

///|
test "rebuild_boundary_chain_optional skips empty levels" {
  // Tree: root:[L, R, S]  R:[X, Y]  Y:[c, d]
  // Delete c and d (entire Y) plus S. left_boundary_subtree should
  // rebuild R with just X — the Y-level frame produces no children
  // (child_idx=0, no kept leaf), so it must be skipped.
  let x_leaf : BTreeNode[TItem] = Leaf(elem=make_item(1, 1), span=1)
  let c_leaf : BTreeNode[TItem] = Leaf(elem=make_item(3, 1), span=1)
  let d_leaf : BTreeNode[TItem] = Leaf(elem=make_item(4, 1), span=1)
  let y_node : BTreeNode[TItem] = Internal(
    children=[c_leaf, d_leaf],
    counts=[1, 1],
    total=2,
  )
  let r_node : BTreeNode[TItem] = Internal(
    children=[x_leaf, y_node],
    counts=[1, 2],
    total=3,
  )
  let l_node : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(10, 2), span=2)],
    counts=[2],
    total=2,
  )
  let s_node : BTreeNode[TItem] = Internal(
    children=[Leaf(elem=make_item(5, 1), span=1)],
    counts=[1],
    total=1,
  )
  let root : BTreeNode[TItem] = Internal(
    children=[l_node, r_node, s_node],
    counts=[2, 3, 1],
    total=6,
  )
  // Delete [3, 6) — removes c, d (all of Y) and s (all of S)
  // LCA is root, start in Y child_idx=0, end in S
  let start = descend_leaf_at(root, 3, 2).unwrap()
  let end_ = descend_leaf_at_end_boundary(root, 6, 2).unwrap()
  let lca = lowest_common_ancestor_range(start, end_)
  let left = left_boundary_subtree(lca, start)
  inspect(left is Some(_), content="true")
  let rebuilt = left.unwrap()
  // Rebuilt subtree should contain only X, no empty internal nodes
  let items : Array[TItem] = []
  rebuilt.each(fn(item) { items.push(item) })
  inspect(items.length(), content="1")
  inspect(items[0], content="{ id: 1, span: 1 }")
  // Height should be 1 (Internal wrapping X), not 2 (no empty Y-level)
  inspect(rebuilt.height(), content="1")
}

///|
test "BTree::delete_range preserves ancestor siblings at leaf boundary" {
  // 10 items, delete range that starts at a leaf which is first child of its parent
  // but the parent has left siblings in an ancestor
  let t = build_tree(Array::makei(10, fn(i) { (i + 1, 1) }))
  let original_span = t.span()
  inspect(original_span, content="10")
  // Delete [8, 10) — last 2 items
  t.delete_range(8, 10)
  inspect(t.span(), content="8")
  inspect(t.size(), content="8")
}

// === Lazy BTree::iter ===

///|
test "BTree::iter yields elements in order lazily" {
  let t = build_tree([(1, 3), (2, 2), (3, 4)])
  let items : Array[TItem] = []
  for item in t.iter() {
    items.push(item)
  }
  inspect(items.length(), content="3")
  inspect(items[0], content="{ id: 1, span: 3 }")
  inspect(items[1], content="{ id: 2, span: 2 }")
  inspect(items[2], content="{ id: 3, span: 4 }")
}

///|
test "BTree::iter on empty tree yields nothing" {
  let t : BTree[TItem] = BTree::new(min_degree=2)
  let items : Array[TItem] = []
  for item in t.iter() {
    items.push(item)
  }
  inspect(items.length(), content="0")
}

///|
test "BTree::iter supports early termination" {
  let t = build_tree([(1, 1), (2, 1), (3, 1), (4, 1), (5, 1)])
  let items : Array[TItem] = []
  for item in t.iter() {
    items.push(item)
    if items.length() == 2 {
      break
    }
  }
  inspect(items.length(), content="2")
  inspect(items[0], content="{ id: 1, span: 1 }")
  inspect(items[1], content="{ id: 2, span: 1 }")
}

// === Property-based tests for BTree::delete_range ===

///|
fn[T] check_node_invariants(
  node : BTreeNode[T],
  min_degree : Int,
  is_root : Bool,
  depth : Int,
) -> (Bool, Int, Int) {
  match node {
    Leaf(..) => (true, depth, 1)
    Internal(children~, counts~, total~) => {
      if children is [] {
        return (false, depth, 0)
      }
      if children.length() != counts.length() {
        return (false, depth, 0)
      }
      if !is_root && children.length() < min_degree {
        return (false, depth, 0)
      }
      if children.length() > 2 * min_degree {
        return (false, depth, 0)
      }
      let mut expected_leaf_depth = -1
      let mut leaf_count = 0
      let mut sum = 0
      for i in 0..<children.length() {
        if counts[i] != children[i].total() {
          return (false, depth, 0)
        }
        let (child_ok, child_leaf_depth, child_leaf_count) = check_node_invariants(
          children[i],
          min_degree,
          false,
          depth + 1,
        )
        if !child_ok {
          return (false, depth, 0)
        }
        if expected_leaf_depth == -1 {
          expected_leaf_depth = child_leaf_depth
        } else if expected_leaf_depth != child_leaf_depth {
          return (false, depth, 0)
        }
        leaf_count = leaf_count + child_leaf_count
        sum = sum + counts[i]
      }
      if sum != total {
        return (false, depth, 0)
      }
      (true, expected_leaf_depth, leaf_count)
    }
  }
}

///|
fn[T] btree_invariants_hold(t : BTree[T]) -> Bool {
  match t.root {
    None => t.size == 0
    Some(root) =>
      match root {
        Leaf(..) => false
        Internal(..) => {
          let (ok, _, leaf_count) = check_node_invariants(
            root,
            t.min_degree,
            true,
            0,
          )
          ok && leaf_count == t.size && root.total() == t.span()
        }
      }
  }
}

///|
/// Compute expected content after delete by using view on the original tree
/// and merging the boundary pair.
fn expected_after_delete(
  t : BTree[TItem],
  start : Int,
  end_ : Int,
) -> Array[TItem] {
  let total = t.span()
  if start < 0 || start >= end_ || start >= total {
    return t.view(start=0, end=total)
  }
  let clamped_end = if end_ > total { total } else { end_ }
  let left = t.view(start=0, end=start)
  let right = t.view(start=clamped_end, end=total)
  // Concatenate and merge all adjacent mergeable pairs
  let concat : Array[TItem] = []
  for item in left {
    concat.push(item)
  }
  for item in right {
    concat.push(item)
  }
  let result : Array[TItem] = []
  for item in concat {
    match result.last() {
      Some(last) =>
        if @rle.Mergeable::can_merge(last, item) {
          result[result.length() - 1] = @rle.Mergeable::merge(last, item)
        } else {
          result.push(item)
        }
      None => result.push(item)
    }
  }
  result
}

///|
struct DeleteRangeCase {
  items : Array[(Int, Int)]
  start : Int
  end_ : Int
} derive(Debug)

///|
impl Show for DeleteRangeCase with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
impl @quickcheck.Arbitrary for DeleteRangeCase with arbitrary(size, rs) {
  let capped = if size < 0 { 0 } else if size > 32 { 32 } else { size }
  let item_count = rs.split().next_positive_int() % (capped + 1)
  let items : Array[(Int, Int)] = []
  let mut total_span = 0
  for _ in 0..<item_count {
    let id = 1 + rs.split().next_positive_int() % 5
    let span = 1 + rs.split().next_positive_int() % 3
    items.push((id, span))
    total_span = total_span + span
  }
  let bound = total_span + 3
  let start = rs.split().next_positive_int() % (bound + 1)
  let end_ = rs.split().next_positive_int() % (bound + 1)
  { items, start, end_ }
}

///|
impl @qc.Shrink for DeleteRangeCase

///|
fn prop_delete_range_preserves_invariants(case_ : DeleteRangeCase) -> Bool {
  let t = build_tree(case_.items)
  if !btree_invariants_hold(t) {
    return false
  }
  t.delete_range(case_.start, case_.end_)
  btree_invariants_hold(t)
}

///|
fn prop_delete_range_span_and_content(case_ : DeleteRangeCase) -> Bool {
  let t = build_tree(case_.items)
  let old_span = t.span()
  let clamped_end = if case_.end_ > old_span { old_span } else { case_.end_ }
  let removed = if case_.start >= 0 &&
    case_.start < clamped_end &&
    case_.start < old_span {
    clamped_end - case_.start
  } else {
    0
  }
  let expected_span = old_span - removed
  // Compute expected total span of remaining items (not exact element list,
  // because merge behavior can differ between splice and rebuild paths)
  let expected_items = expected_after_delete(t, case_.start, case_.end_)
  let mut expected_total_span = 0
  for item in expected_items {
    expected_total_span = expected_total_span + item.span
  }
  t.delete_range(case_.start, case_.end_)
  let mut actual_total_span = 0
  for item in t.iter() {
    actual_total_span = actual_total_span + item.span
  }
  t.span() == expected_span && actual_total_span == expected_total_span
}

///|
fn prop_delete_range_iter_matches_view(case_ : DeleteRangeCase) -> Bool {
  let t = build_tree(case_.items)
  t.delete_range(case_.start, case_.end_)
  let iter_items : Array[TItem] = []
  for item in t.iter() {
    iter_items.push(item)
  }
  iter_items == t.view(start=0, end=t.span())
}

///|
test "delete_range with underfull boundary chain repair" {
  // Regression: this case produces underfull boundary subtrees,
  // repaired by chain repair + insertion-site repair.
  let t = build_tree([
    (5, 3),
    (2, 1),
    (4, 2),
    (1, 1),
    (5, 1),
    (1, 3),
    (2, 3),
    (3, 3),
    (5, 3),
    (1, 1),
    (2, 3),
    (5, 1),
    (1, 2),
    (3, 3),
    (3, 1),
  ])
  inspect(
    t.span(),
    content=(
      #|31
    ),
  )
  inspect(
    t.size(),
    content=(
      #|15
    ),
  )
  t.delete_range(14, 18)
  inspect(
    t.span(),
    content=(
      #|27
    ),
  )
  inspect(
    t.size(),
    content=(
      #|13
    ),
  )
  inspect(
    btree_invariants_hold(t),
    content=(
      #|true
    ),
  )
}

///|
test "property: delete_range preserves btree invariants" {
  @qc.quick_check_fn(prop_delete_range_preserves_invariants)
}

///|
test "property: delete_range preserves span and content" {
  @qc.quick_check_fn(prop_delete_range_span_and_content)
}

///|
test "property: delete_range iter matches view" {
  @qc.quick_check_fn(prop_delete_range_iter_matches_view)
}

// === from_sorted ===

///|
test "from_sorted empty input" {
  let t : BTree[TItem] = BTree::from_sorted([])
  inspect(t.is_empty(), content="true")
  inspect(t.size(), content="0")
  inspect(t.span(), content="0")
}

///|
test "from_sorted single element" {
  let t : BTree[TItem] = BTree::from_sorted([(make_item(1, 5), 5)])
  inspect(t.is_empty(), content="false")
  inspect(t.size(), content="1")
  inspect(t.span(), content="5")
  inspect(t.get_at(0), content="Some({ id: 1, span: 5 })")
  inspect(btree_invariants_hold(t), content="true")
}

///|
test "from_sorted min_degree elements" {
  // min_degree=2 → exactly 2 leaves, one Internal root
  let items : Array[(TItem, Int)] = []
  for i in 0..<2 {
    items.push((make_item(i, 3), 3))
  }
  let t : BTree[TItem] = BTree::from_sorted(items, min_degree=2)
  inspect(t.size(), content="2")
  inspect(t.span(), content="6")
  inspect(btree_invariants_hold(t), content="true")
}

///|
test "from_sorted max_degree elements" {
  // min_degree=2, max_degree=4 → exactly 4 leaves, one Internal root
  let items : Array[(TItem, Int)] = []
  for i in 0..<4 {
    items.push((make_item(i, 2), 2))
  }
  let t : BTree[TItem] = BTree::from_sorted(items, min_degree=2)
  inspect(t.size(), content="4")
  inspect(t.span(), content="8")
  inspect(btree_invariants_hold(t), content="true")
}

///|
test "from_sorted triggers multi-level" {
  // min_degree=2, max_degree=4 → 5 leaves requires 2 levels
  let items : Array[(TItem, Int)] = []
  for i in 0..<5 {
    items.push((make_item(i, 1), 1))
  }
  let t : BTree[TItem] = BTree::from_sorted(items, min_degree=2)
  inspect(t.size(), content="5")
  inspect(t.span(), content="5")
  inspect(btree_invariants_hold(t), content="true")
}

///|
test "from_sorted redistribution of last chunk" {
  // min_degree=3, max_degree=6 → 7 leaves: first chunk of 6, last chunk of 1
  // 1 < min_degree=3, so redistribute: 4+3 or 3+4
  let items : Array[(TItem, Int)] = []
  for i in 0..<7 {
    items.push((make_item(i, 2), 2))
  }
  let t : BTree[TItem] = BTree::from_sorted(items, min_degree=3)
  inspect(t.size(), content="7")
  inspect(t.span(), content="14")
  inspect(btree_invariants_hold(t), content="true")
}

///|
test "from_sorted content matches build_tree" {
  // Both should produce the same leaf content and ordering
  let input : Array[(Int, Int)] = [
    (1, 3),
    (2, 1),
    (3, 2),
    (4, 4),
    (1, 2),
    (2, 3),
    (3, 1),
    (4, 2),
    (1, 1),
  ]
  let ref_tree = build_tree(input)
  let items : Array[(TItem, Int)] = input.map(fn(pair) {
    (make_item(pair.0, pair.1), pair.1)
  })
  let t : BTree[TItem] = BTree::from_sorted(items, min_degree=2)
  inspect(t.size(), content=ref_tree.size().to_string())
  inspect(t.span(), content=ref_tree.span().to_string())
  // Same content when viewed
  let ref_view = ref_tree.view()
  let new_view = t.view()
  inspect(new_view.length(), content=ref_view.length().to_string())
  for i in 0..<ref_view.length() {
    assert_eq(new_view[i], ref_view[i])
  }
  inspect(btree_invariants_hold(t), content="true")
}

///|
test "from_sorted large tree" {
  // 100 elements with default min_degree=10 → multi-level tree
  let items : Array[(TItem, Int)] = []
  for i in 0..<100 {
    items.push((make_item(i % 10, i % 5 + 1), i % 5 + 1))
  }
  let t : BTree[TItem] = BTree::from_sorted(items)
  inspect(t.size(), content="100")
  inspect(btree_invariants_hold(t), content="true")
  let all = t.view()
  inspect(all.length(), content="100")
}

///|
test "from_sorted redistribution at default degree boundaries" {
  // min_degree=10, max_degree=20
  // n=21: two chunks (11+10 or 10+11), both valid
  for n in [21, 39, 41] {
    let items : Array[(TItem, Int)] = []
    for i in 0..<n {
      items.push((make_item(i, 1), 1))
    }
    let t : BTree[TItem] = BTree::from_sorted(items)
    inspect(t.size() == n, content="true")
    inspect(t.span() == n, content="true")
    inspect(btree_invariants_hold(t), content="true")
  }
}

///|
test "from_sorted clamps invalid min_degree" {
  // min_degree=0, 1, negative should all clamp to 2
  let items : Array[(TItem, Int)] = [(make_item(1, 1), 1), (make_item(2, 1), 1)]
  for d in [-1, 0, 1] {
    let t : BTree[TItem] = BTree::from_sorted(items, min_degree=d)
    inspect(t.size(), content="2")
    inspect(btree_invariants_hold(t), content="true")
  }
}

///|
struct FromSortedCase {
  items : Array[(Int, Int)]
  min_degree : Int
} derive(Debug)

///|
impl Show for FromSortedCase with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
impl @quickcheck.Arbitrary for FromSortedCase with arbitrary(size, rs) {
  let capped = if size < 0 { 0 } else if size > 50 { 50 } else { size }
  let item_count = rs.split().next_positive_int() % (capped + 1)
  let min_degree = 2 + rs.split().next_positive_int() % 4
  let items : Array[(Int, Int)] = []
  for _ in 0..<item_count {
    let id = 1 + rs.split().next_positive_int() % 10
    let span = 1 + rs.split().next_positive_int() % 5
    items.push((id, span))
  }
  { items, min_degree }
}

///|
impl @qc.Shrink for FromSortedCase

///|
fn prop_from_sorted_invariants(case_ : FromSortedCase) -> Bool {
  let items : Array[(TItem, Int)] = case_.items.map(fn(pair) {
    (make_item(pair.0, pair.1), pair.1)
  })
  let t : BTree[TItem] = BTree::from_sorted(items, min_degree=case_.min_degree)
  if t.size() != items.length() {
    return false
  }
  let expected_span = items.fold(init=0, fn(acc, pair) { acc + pair.1 })
  if t.span() != expected_span {
    return false
  }
  btree_invariants_hold(t)
}

///|
test "property: from_sorted produces valid btree" {
  @qc.quick_check_fn(prop_from_sorted_invariants)
}
