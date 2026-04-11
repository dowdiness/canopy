///|
priv struct BItem {
  value : Int
}

///|
impl @rle.HasLength for BItem with length(_self) {
  1
}

///|
impl @rle.Spanning for BItem with span(_self) {
  1
}

///|
impl @rle.Mergeable for BItem with can_merge(_self, _other) -> Bool {
  false
}

///|
impl @rle.Mergeable for BItem with merge(_self, _other) -> BItem {
  abort("unreachable")
}

///|
impl @rle.Sliceable for BItem with slice(self, start~ : Int, end~ : Int) -> Result[
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
