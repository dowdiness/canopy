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
