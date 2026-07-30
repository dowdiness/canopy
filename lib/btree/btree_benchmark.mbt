///|
priv struct BItem {
  value : Int
}

///|
impl @rle.HasLength for BItem with fn length(_self) {
  1
}

///|
impl @rle.Spanning for BItem with fn span(_self) {
  1
}

///|
impl @rle.Mergeable for BItem with fn can_merge(_self, _other) -> Bool {
  false
}

///|
impl @rle.Mergeable for BItem with fn merge(_self, _other) -> BItem {
  abort("unreachable")
}

///|
impl @rle.Sliceable for BItem with fn slice(self, start~ : Int, end~ : Int) -> Result[
  BItem,
  @rle.RleError,
] {
  if start == 0 && end == 1 {
    Ok({ value: self.value })
  } else {
    Err(@rle.RleError::InvalidSlice(reason=@rle.SliceError::InvalidIndex))
  }
}

///|
impl BTreeElem for BItem

///|
priv struct MergeBenchItem {
  value : Int
  span : Int
}

///|
impl @rle.HasLength for MergeBenchItem with fn length(self) -> Int {
  self.span
}

///|
impl @rle.Spanning for MergeBenchItem with fn span(self) -> Int {
  self.span
}

///|
impl @rle.Mergeable for MergeBenchItem with fn can_merge(self, other) -> Bool {
  self.value == other.value
}

///|
impl @rle.Mergeable for MergeBenchItem with fn merge(self, other) -> MergeBenchItem {
  { value: self.value, span: self.span + other.span }
}

///|
fn bi(v : Int) -> BItem {
  { value: v }
}

///|
/// Build tree via repeated inserts (O(n log n) baseline)
fn build_via_inserts(n : Int, min_degree : Int) -> BTree[BItem] {
  let t : BTree[BItem] = BTree::new(min_degree~)
  if n == 0 {
    return t
  }
  t.init_root(bi(0), 1)
  for i in 1..<n {
    t.mutate_for_insert(i, fn(ctx) {
      {
        start_idx: ctx.child_idx + 1,
        end_idx: ctx.child_idx + 1,
        new_leaves: [(bi(i), 1)],
      }
    })
  }
  t
}

///|
/// Build tree via from_sorted (O(n) bulk)
fn build_via_from_sorted(n : Int, min_degree : Int) -> BTree[BItem] {
  let items : Array[(BItem, Int)] = []
  for i in 0..<n {
    items.push((bi(i), 1))
  }
  BTree::from_sorted(items, min_degree~)
}

///|
fn build_boundary_merge_root(
  n : Int,
  boundary : Int,
  variant : Int,
  expect_cross_parent : Bool,
) -> BTreeNode[MergeBenchItem] {
  let merge_value = -variant - 1
  let items = Array::makei(n, i => {
    let value = if i == boundary - 1 || i == boundary {
      merge_value
    } else {
      variant * n + i + 1
    }
    let item : MergeBenchItem = { value, span: 1 }
    (item, 1)
  })
  let t : BTree[MergeBenchItem] = BTree::from_sorted(items, min_degree=10)
  let root = t.root.unwrap()
  let left = descend_leaf_at_end_boundary(
    root,
    boundary,
    10,
    copy_on_write=false,
  ).unwrap()
  let right = descend_leaf_at(root, boundary, 10, copy_on_write=false).unwrap()
  let is_cross_parent = left.path.length() == right.path.length() &&
    left.path.length() > 0 &&
    shared_prefix_length(left.path, right.path) < left.path.length() - 1
  guard is_cross_parent == expect_cross_parent else {
    abort("boundary merge benchmark topology drifted")
  }
  root
}

///|
fn bench_boundary_merge(
  b : @bench.T,
  n : Int,
  boundary : Int,
  expect_cross_parent : Bool,
) -> Unit {
  let roots = Array::makei(8, variant => {
    build_boundary_merge_root(n, boundary, variant, expect_cross_parent)
  })
  let mut variant = 0
  b.bench(fn() {
    let (root, leaf_delta) = normalize_boundary_chain(
      roots[variant],
      boundary,
      10,
    )
    variant = (variant + 1) % roots.length()
    b.keep(if leaf_delta < 0 { root.total() } else { -1 })
  })
}

// === 100 elements ===

///|
test "bench: build via inserts (100)" (b : @bench.T) {
  b.bench(fn() { b.keep(build_via_inserts(100, 10).span()) })
}

///|
test "bench: build via from_sorted (100)" (b : @bench.T) {
  b.bench(fn() { b.keep(build_via_from_sorted(100, 10).span()) })
}

// === 1000 elements ===

///|
test "bench: build via inserts (1000)" (b : @bench.T) {
  b.bench(fn() { b.keep(build_via_inserts(1000, 10).span()) })
}

///|
test "bench: build via from_sorted (1000)" (b : @bench.T) {
  b.bench(fn() { b.keep(build_via_from_sorted(1000, 10).span()) })
}

// === 10000 elements ===

///|
test "bench: build via inserts (10000)" (b : @bench.T) {
  b.bench(fn() { b.keep(build_via_inserts(10000, 10).span()) })
}

///|
test "bench: build via from_sorted (10000)" (b : @bench.T) {
  b.bench(fn() { b.keep(build_via_from_sorted(10000, 10).span()) })
}

// === delete_range ===

///|
test "bench: delete_range middle 10% (1000)" (b : @bench.T) {
  b.bench(fn() {
    let t = build_via_from_sorted(1000, 10)
    t.delete_range(450, 550)
    b.keep(t.span())
  })
}

///|
test "bench: delete_range middle 50% (1000)" (b : @bench.T) {
  b.bench(fn() {
    let t = build_via_from_sorted(1000, 10)
    t.delete_range(250, 750)
    b.keep(t.span())
  })
}

///|
test "bench: delete_range middle 10% (10000)" (b : @bench.T) {
  b.bench(fn() {
    let t = build_via_from_sorted(10000, 10)
    t.delete_range(4500, 5500)
    b.keep(t.span())
  })
}

///|
test "bench: delete_range middle 50% (10000)" (b : @bench.T) {
  b.bench(fn() {
    let t = build_via_from_sorted(10000, 10)
    t.delete_range(2500, 7500)
    b.keep(t.span())
  })
}

// === isolated boundary merge ===

///|
test "bench: boundary merge cross-parent (401)" (b : @bench.T) {
  bench_boundary_merge(b, 401, 200, true)
}

///|
test "bench: boundary merge same-parent (401)" (b : @bench.T) {
  bench_boundary_merge(b, 401, 201, false)
}

///|
test "bench: boundary merge cross-parent (8001)" (b : @bench.T) {
  bench_boundary_merge(b, 8001, 4000, true)
}

///|
test "bench: boundary merge same-parent (8001)" (b : @bench.T) {
  bench_boundary_merge(b, 8001, 4001, false)
}
