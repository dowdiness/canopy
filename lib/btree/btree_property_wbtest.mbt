// Model-based property tests for dowdiness/btree.

///|
fn model_items(pairs : Array[(Int, Int)]) -> Array[TItem] {
  pairs.map(fn(pair) { make_item(pair.0, pair.1) })
}

///|
fn model_sorted_items(pairs : Array[(Int, Int)]) -> Array[(TItem, Int)] {
  pairs.map(fn(pair) { (make_item(pair.0, pair.1), pair.1) })
}

///|
fn model_span(items : Array[TItem]) -> Int {
  items.fold(init=0, fn(acc, item) { acc + item.span })
}

///|
fn model_copy(items : Array[TItem]) -> Array[TItem] {
  items.map(fn(item) { item })
}

///|
fn model_view_range(
  items : Array[TItem],
  start : Int,
  end_ : Int,
) -> Array[TItem] {
  let total = model_span(items)
  let start = if start < 0 { 0 } else { start }
  let end_ = if end_ > total { total } else { end_ }
  let result : Array[TItem] = []
  guard start < end_ && start < total else { return result }
  let mut pos = 0
  for item in items {
    let item_start = pos
    let item_end = pos + item.span
    if item_end > start && item_start < end_ {
      let slice_start = if start > item_start { start - item_start } else { 0 }
      let slice_end = if end_ < item_end {
        end_ - item_start
      } else {
        item.span
      }
      if slice_start == 0 && slice_end == item.span {
        result.push(item)
      } else {
        result.push(must_slice(item, start=slice_start, end=slice_end))
      }
    }
    pos = item_end
  }
  result
}

///|
fn model_concat_with_boundary_merge(
  left : Array[TItem],
  right : Array[TItem],
) -> Array[TItem] {
  let result = model_copy(left)
  for i in 0..<right.length() {
    let item = right[i]
    if i == 0 && result.length() > 0 {
      let last_idx = result.length() - 1
      let last = result[last_idx]
      if @rle.Mergeable::can_merge(last, item) {
        result[last_idx] = @rle.Mergeable::merge(last, item)
      } else {
        result.push(item)
      }
    } else {
      result.push(item)
    }
  }
  result
}

///|
fn model_delete_range(
  items : Array[TItem],
  start : Int,
  end_ : Int,
) -> Array[TItem] {
  let total = model_span(items)
  if start < 0 || start >= end_ || start >= total {
    return model_copy(items)
  }
  let clamped_end = if end_ > total { total } else { end_ }
  let left = model_view_range(items, 0, start)
  let right = model_view_range(items, clamped_end, total)
  model_concat_with_boundary_merge(left, right)
}

///|
fn model_find(items : Array[TItem], pos : Int) -> FindResult[TItem]? {
  guard pos >= 0 else { return None }
  let mut offset = 0
  for item in items {
    let next = offset + item.span
    if pos < next {
      return Some({ elem: item, offset: pos - offset })
    }
    offset = next
  }
  None
}

///|
fn model_get_at(items : Array[TItem], pos : Int) -> TItem? {
  model_find(items, pos).map(fn(result) { result.elem })
}

///|
fn normalized_index(raw : Int, upper_inclusive : Int) -> Int {
  guard upper_inclusive > 0 else { return 0 }
  let width = upper_inclusive + 1
  let idx = raw % width
  if idx < 0 {
    idx + width
  } else {
    idx
  }
}

///|
fn query_matches_model(
  t : BTree[TItem],
  model : Array[TItem],
  pos : Int,
  start : Int,
  end_ : Int,
) -> Bool {
  t.find(pos) == model_find(model, pos) &&
  t.get_at(pos) == model_get_at(model, pos) &&
  t.view(start~, end=end_) == model_view_range(model, start, end_)
}

///|
fn all_queries_match_model(t : BTree[TItem], model : Array[TItem]) -> Bool {
  let total = model_span(model)
  if t.view(start=-total - 2, end=total + 2) !=
    model_view_range(model, -total - 2, total + 2) {
    return false
  }
  for pos in -1..<(total + 2) {
    if !query_matches_model(t, model, pos, 0, total) {
      return false
    }
  }
  true
}

///|
fn tree_iter_items(t : BTree[TItem]) -> Array[TItem] {
  let items : Array[TItem] = []
  for item in t.iter() {
    items.push(item)
  }
  items
}

///|
fn tree_matches_model(t : BTree[TItem], model : Array[TItem]) -> Bool {
  if !btree_invariants_hold(t) {
    return false
  }
  if t.size() != model.length() {
    return false
  }
  if t.span() != model_span(model) {
    return false
  }
  if t.view(start=0, end=t.span()) != model {
    return false
  }
  tree_iter_items(t) == model && all_queries_match_model(t, model)
}

///|
fn model_insert_item_at(
  model : Array[TItem],
  pos : Int,
  item : TItem,
) -> Array[TItem] {
  let left = model_view_range(model, 0, pos)
  let right = model_view_range(model, pos, model_span(model))
  let result = model_copy(left)
  result.push(item)
  for right_item in right {
    result.push(right_item)
  }
  result
}

///|
fn tree_insert_item_at(t : BTree[TItem], pos : Int, item : TItem) -> Unit {
  if t.is_empty() {
    t.init_root(item, item.span)
  } else {
    t.mutate_for_insert(pos, fn(ctx) {
      let new_leaves : Array[(TItem, Int)] = []
      if ctx.offset > 0 {
        let left = must_slice(ctx.elem, start=0, end=ctx.offset)
        new_leaves.push((left, left.span))
      }
      new_leaves.push((item, item.span))
      if ctx.offset < ctx.span {
        let right = must_slice(ctx.elem, start=ctx.offset, end=ctx.span)
        new_leaves.push((right, right.span))
      }
      { start_idx: ctx.child_idx, end_idx: ctx.child_idx + 1, new_leaves }
    })
  }
}

///|
fn insert_item_at(
  t : BTree[TItem],
  model : Array[TItem],
  raw_pos : Int,
  item : TItem,
) -> Array[TItem] {
  let pos = normalized_index(raw_pos, model_span(model))
  tree_insert_item_at(t, pos, item)
  model_insert_item_at(model, pos, item)
}

///|
fn model_delete_leaf_at(
  items : Array[TItem],
  pos : Int,
) -> (Array[TItem], TItem?) {
  guard pos >= 0 else { return (model_copy(items), None) }
  let mut offset = 0
  let result : Array[TItem] = []
  let mut deleted : TItem? = None
  for item in items {
    let next = offset + item.span
    if deleted is None && pos < next {
      deleted = Some(item)
    } else {
      result.push(item)
    }
    offset = next
  }
  (result, deleted)
}

///|
fn delete_leaf_at(
  t : BTree[TItem],
  model : Array[TItem],
  pos : Int,
) -> Array[TItem] {
  let (expected_model, expected_deleted) = model_delete_leaf_at(model, pos)
  let deleted = t.mutate_for_delete(pos, fn(ctx) {
    (
      { start_idx: ctx.child_idx, end_idx: ctx.child_idx + 1, new_leaves: [] },
      ctx.elem,
    )
  })
  if deleted != expected_deleted {
    abort("delete_leaf_at: model and tree returned different deleted items")
  }
  expected_model
}

///|
struct QueryCase {
  items : Array[(Int, Int)]
  start : Int
  end_ : Int
  pos : Int
} derive(Debug, Eq)

///|
impl @quickcheck.Arbitrary for QueryCase with fn arbitrary(size, rs) {
  let capped = if size < 0 { 0 } else if size > 40 { 40 } else { size }
  let item_count = rs.split().next_positive_int() % (capped + 1)
  let items : Array[(Int, Int)] = []
  let mut total = 0
  for _ in 0..<item_count {
    let id = 1 + rs.split().next_positive_int() % 8
    let span = 1 + rs.split().next_positive_int() % 6
    items.push((id, span))
    total = total + span
  }
  let bound = total + 6
  {
    items,
    start: signed_bounded(rs.split(), bound),
    end_: signed_bounded(rs.split(), bound),
    pos: signed_bounded(rs.split(), bound),
  }
}

///|
fn push_query_case_shrinks(
  results : Array[QueryCase],
  items : Array[(Int, Int)],
  start : Int,
  end_ : Int,
  pos : Int,
) -> Unit {
  let total = generated_items_span(items)
  if start != 0 || end_ != 0 || pos != 0 {
    results.push({ items, start: 0, end_: 0, pos: 0 })
  }
  if total > 0 {
    if start != 0 || end_ != total || pos != 0 {
      results.push({ items, start: 0, end_: total, pos: 0 })
    }
    if start != 0 || end_ != total || pos != total + 1 {
      results.push({ items, start: 0, end_: total, pos: total + 1 })
    }
    if start != total - 1 || end_ != total || pos != total {
      results.push({ items, start: total - 1, end_: total, pos: total })
    }
    if start != 0 || end_ != total || pos != total - 1 {
      results.push({ items, start: 0, end_: total, pos: total - 1 })
    }
    if start != 0 || end_ != total || pos != total {
      results.push({ items, start: 0, end_: total, pos: total })
    }
  }
  if start < 0 && start != -1 {
    results.push({ items, start: -1, end_, pos })
  }
  if end_ < 0 && end_ != -1 {
    results.push({ items, start, end_: -1, pos })
  }
  if pos < 0 && pos != -1 {
    results.push({ items, start, end_, pos: -1 })
  }
  if start > total && start != total + 1 {
    results.push({ items, start: total + 1, end_, pos })
  }
  if end_ > total && end_ != total + 1 {
    results.push({ items, start, end_: total + 1, pos })
  }
  if pos > total && pos != total + 1 {
    results.push({ items, start, end_, pos: total + 1 })
  }
  if start > end_ {
    results.push({ items, start: end_, end_: start, pos })
  }
  for next_start in @qc.Shrink::shrink(start) {
    results.push({ items, start: next_start, end_, pos })
  }
  for next_end in @qc.Shrink::shrink(end_) {
    results.push({ items, start, end_: next_end, pos })
  }
  for next_pos in @qc.Shrink::shrink(pos) {
    results.push({ items, start, end_, pos: next_pos })
  }
}

///|
fn query_case_abs(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
fn QueryCase::is_minimal_witness(self : QueryCase) -> Bool {
  self.start == 0 &&
  self.end_ == 0 &&
  self.pos == 0 &&
  self.items.length() == 1 &&
  self.items[0].0 == 1 &&
  self.items[0].1 == 1
}

///|
fn QueryCase::shrink_score(self : QueryCase) -> Int {
  let len = self.items.length()
  if len == 0 {
    return 1_000_000
  }
  let mut item_score = 0
  for item in self.items {
    item_score = item_score + query_case_abs(item.0) + item.1
  }
  len * 1_000 +
  item_score +
  query_case_abs(self.start) +
  query_case_abs(self.end_) +
  query_case_abs(self.pos)
}

///|
fn QueryCase::to_stable_witness(self : QueryCase) -> QueryCase {
  fn shrink_query_case_to_stable_witness_inner(
    current : QueryCase,
  ) -> QueryCase {
    let current_score = current.shrink_score()
    let mut next_case : QueryCase? = None
    let mut next_score = current_score
    for candidate in @qc.Shrink::shrink(current) {
      if candidate.is_minimal_witness() {
        return candidate
      }
      let score = candidate.shrink_score()
      if score < next_score {
        next_case = Some(candidate)
        next_score = score
      }
    }
    match next_case {
      Some(next) => shrink_query_case_to_stable_witness_inner(next)
      None => current
    }
  }
  shrink_query_case_to_stable_witness_inner(self)
}

///|
impl @qc.Shrink for QueryCase with fn shrink(case_) {
  let results : Array[QueryCase] = []
  push_query_case_shrinks(
    results,
    case_.items,
    case_.start,
    case_.end_,
    case_.pos,
  )
  for items in shrink_generated_items(case_.items) {
    results.push({ items, start: case_.start, end_: case_.end_, pos: case_.pos })
    push_query_case_shrinks(results, items, case_.start, case_.end_, case_.pos)
  }
  results.iter()
}

///|
fn prop_view_find_get_at_matches_model(case_ : QueryCase) -> Bool {
  let t = build_tree(case_.items)
  if !btree_invariants_hold(t) {
    abort("build_tree produced invalid tree")
  }
  let model = model_items(case_.items)
  query_matches_model(t, model, case_.pos, case_.start, case_.end_)
}

///|
fn prop_delete_range_exact_content(case_ : DeleteRangeCase) -> Bool {
  let t = build_tree(case_.items)
  if !btree_invariants_hold(t) {
    abort("build_tree produced invalid tree")
  }
  let model = model_items(case_.items)
  let expected = model_delete_range(model, case_.start, case_.end_)
  t.delete_range(case_.start, case_.end_)
  tree_matches_model(t, expected)
}

///|
fn prop_from_sorted_exact_content(case_ : FromSortedCase) -> Bool {
  let items = model_sorted_items(case_.items)
  let model = model_items(case_.items)
  let t : BTree[TItem] = BTree::from_sorted(items, min_degree=case_.min_degree)
  tree_matches_model(t, model)
}

///|
enum ModelOp {
  Append(Int, Int)
  Insert(Int, Int, Int)
  DeleteAt(Int)
  DeleteRange(Int, Int)
  Query(Int, Int, Int)
} derive(Debug, Eq)

///|
struct OpSequenceCase {
  ops : Array[ModelOp]
  min_degree : Int
} derive(Debug)

///|
impl @quickcheck.Arbitrary for ModelOp with fn arbitrary(size, rs) {
  let bound = if size < 1 { 8 } else { size * 4 + 8 }
  let id = 1 + rs.split().next_positive_int() % 8
  let span = 1 + rs.split().next_positive_int() % 6
  match rs.split().next_positive_int() % 5 {
    0 => Append(id, span)
    1 => Insert(signed_bounded(rs.split(), bound), id, span)
    2 => DeleteAt(signed_bounded(rs.split(), bound))
    3 =>
      DeleteRange(
        signed_bounded(rs.split(), bound),
        signed_bounded(rs.split(), bound),
      )
    _ =>
      Query(
        signed_bounded(rs.split(), bound),
        signed_bounded(rs.split(), bound),
        signed_bounded(rs.split(), bound),
      )
  }
}

///|
impl @qc.Shrink for ModelOp with fn shrink(op) {
  let results : Array[ModelOp] = []
  match op {
    Append(id, span) => {
      if id > 1 {
        results.push(Append(1, span))
      }
      if span > 1 {
        results.push(Append(id, 1))
      }
    }
    Insert(pos, id, span) => {
      if pos != 0 {
        results.push(Insert(0, id, span))
      }
      if pos < 0 && pos != -1 {
        results.push(Insert(-1, id, span))
      }
      if id > 1 {
        results.push(Insert(pos, 1, span))
      }
      if span > 1 {
        results.push(Insert(pos, id, 1))
      }
      for next_pos in @qc.Shrink::shrink(pos) {
        results.push(Insert(next_pos, id, span))
      }
    }
    DeleteAt(pos) => {
      if pos != 0 {
        results.push(DeleteAt(0))
      }
      if pos < 0 && pos != -1 {
        results.push(DeleteAt(-1))
      }
      for next_pos in @qc.Shrink::shrink(pos) {
        results.push(DeleteAt(next_pos))
      }
    }
    DeleteRange(start, end_) => {
      if start != 0 || end_ != 0 {
        results.push(DeleteRange(0, 0))
      }
      if start < 0 && start != -1 {
        results.push(DeleteRange(-1, end_))
      }
      if end_ < 0 && end_ != -1 {
        results.push(DeleteRange(start, -1))
      }
      if start != end_ {
        results.push(DeleteRange(start, start))
      }
      for next_start in @qc.Shrink::shrink(start) {
        results.push(DeleteRange(next_start, end_))
      }
      for next_end in @qc.Shrink::shrink(end_) {
        results.push(DeleteRange(start, next_end))
      }
    }
    Query(pos, start, end_) => {
      if pos != 0 || start != 0 || end_ != 0 {
        results.push(Query(0, 0, 0))
      }
      if pos < 0 && pos != -1 {
        results.push(Query(-1, start, end_))
      }
      if start < 0 && start != -1 {
        results.push(Query(pos, -1, end_))
      }
      if end_ < 0 && end_ != -1 {
        results.push(Query(pos, start, -1))
      }
      for next_pos in @qc.Shrink::shrink(pos) {
        results.push(Query(next_pos, start, end_))
      }
      for next_start in @qc.Shrink::shrink(start) {
        results.push(Query(pos, next_start, end_))
      }
      for next_end in @qc.Shrink::shrink(end_) {
        results.push(Query(pos, start, next_end))
      }
    }
  }
  results.iter()
}

///|
impl @quickcheck.Arbitrary for OpSequenceCase with fn arbitrary(size, rs) {
  let capped = if size < 0 { 0 } else if size > 32 { 32 } else { size }
  let op_count = rs.split().next_positive_int() % (capped + 1)
  let ops : Array[ModelOp] = []
  for _ in 0..<op_count {
    let op : ModelOp = @quickcheck.Arbitrary::arbitrary(capped, rs.split())
    ops.push(op)
  }
  let min_degree = match rs.split().next_positive_int() % 4 {
    0 => 2
    1 => 3
    2 => 5
    _ => DEFAULT_MIN_DEGREE
  }
  { ops, min_degree }
}

///|
fn push_min_degree_shrinks(
  results : Array[OpSequenceCase],
  ops : Array[ModelOp],
  min_degree : Int,
) -> Unit {
  if min_degree == DEFAULT_MIN_DEGREE {
    results.push({ ops, min_degree: 5 })
    results.push({ ops, min_degree: 3 })
    results.push({ ops, min_degree: 2 })
  } else if min_degree > 3 {
    results.push({ ops, min_degree: 3 })
    results.push({ ops, min_degree: 2 })
  } else if min_degree > 2 {
    results.push({ ops, min_degree: 2 })
  }
}

///|
impl @qc.Shrink for OpSequenceCase with fn shrink(case_) {
  let results : Array[OpSequenceCase] = []
  let len = case_.ops.length()
  if len > 0 {
    results.push({ ops: case_.ops[:0].to_owned(), min_degree: case_.min_degree })
    let half = len / 2
    if half > 0 {
      results.push({
        ops: case_.ops[:half].to_owned(),
        min_degree: case_.min_degree,
      })
      let suffix_start = len - half
      if suffix_start != 0 && suffix_start != half {
        results.push({
          ops: case_.ops[suffix_start:len].to_owned(),
          min_degree: case_.min_degree,
        })
      }
    }
    if len > 1 {
      results.push({
        ops: case_.ops[:len - 1].to_owned(),
        min_degree: case_.min_degree,
      })
      for i in 0..<len {
        results.push({
          ops: array_without_at(case_.ops, i),
          min_degree: case_.min_degree,
        })
      }
    }
    for i in 0..<len {
      for op in @qc.Shrink::shrink(case_.ops[i]) {
        results.push({
          ops: array_replaced_at(case_.ops, i, op),
          min_degree: case_.min_degree,
        })
      }
    }
  }
  push_min_degree_shrinks(results, case_.ops, case_.min_degree)
  results.iter()
}

///|
fn apply_model_op(
  t : BTree[TItem],
  model : Array[TItem],
  op : ModelOp,
) -> Array[TItem] {
  match op {
    Append(id, span) =>
      insert_item_at(t, model, model_span(model), make_item(id, span))
    Insert(pos, id, span) => insert_item_at(t, model, pos, make_item(id, span))
    DeleteAt(pos) => delete_leaf_at(t, model, pos)
    DeleteRange(start, end_) => {
      t.delete_range(start, end_)
      model_delete_range(model, start, end_)
    }
    Query(pos, start, end_) => {
      if !query_matches_model(t, model, pos, start, end_) {
        abort("query operation diverged from model")
      }
      model_copy(model)
    }
  }
}

///|
fn prop_operation_sequence_matches_model(case_ : OpSequenceCase) -> Bool {
  let t : BTree[TItem] = BTree::new(min_degree=case_.min_degree)
  let mut model : Array[TItem] = []
  if !tree_matches_model(t, model) {
    return false
  }
  for op in case_.ops {
    model = apply_model_op(t, model, op)
    if !tree_matches_model(t, model) {
      return false
    }
  }
  true
}

///|
test "property: delete_range exact content matches array model" {
  @qc.quick_check_fn(prop_delete_range_exact_content)
}

///|
test "property: view find and get_at match array model" {
  @qc.quick_check_fn(prop_view_find_get_at_matches_model)
}

///|
test "property: from_sorted exact content matches array model" {
  @qc.quick_check_fn(prop_from_sorted_exact_content)
}

///|
test "property: operation sequences match array model" {
  @qc.quick_check_fn(prop_operation_sequence_matches_model)
}

///|
test "regression: QueryCase shrinker reaches stable minimal witness" {
  let seed : QueryCase = {
    items: [(8, 7), (7, 5), (6, 3), (5, 6), (4, 4), (3, 2)],
    start: 27,
    end_: 34,
    pos: 99,
  }
  let shrunk_once = seed.to_stable_witness()
  let shrunk_twice = shrunk_once.to_stable_witness()
  let expected : QueryCase = { items: [(1, 1)], start: 0, end_: 0, pos: 0 }
  inspect(shrunk_once.items.length(), content="1")
  inspect(shrunk_once.start, content="0")
  inspect(shrunk_once.end_, content="0")
  inspect(shrunk_once.pos, content="0")
  inspect(shrunk_once.items[0].0, content="1")
  inspect(shrunk_once.items[0].1, content="1")
  inspect(shrunk_once.shrink_score(), content="1002")
  inspect(shrunk_once.is_minimal_witness(), content="true")
  inspect(shrunk_once == expected, content="true")
  inspect(shrunk_once == shrunk_twice, content="true")
}

///|
test "quickcheck delete_range generator covers important shapes" {
  let samples : Array[DeleteRangeCase] = @quickcheck.samples(400)
  let mut saw_empty = false
  let mut saw_one_leaf = false
  let mut saw_split_boundary = false
  let mut saw_deep_candidate = false
  let mut saw_negative = false
  let mut saw_empty_range = false
  let mut saw_full_range = false
  let mut saw_boundary_delete = false
  let mut saw_out_of_bounds = false
  for case_ in samples {
    let total = model_span(model_items(case_.items))
    if case_.items.is_empty() {
      saw_empty = true
    }
    if case_.items.length() == 1 {
      saw_one_leaf = true
    }
    if case_.items.length() == 4 || case_.items.length() == 5 {
      saw_split_boundary = true
    }
    if case_.items.length() > 20 {
      saw_deep_candidate = true
    }
    if case_.start < 0 || case_.end_ < 0 {
      saw_negative = true
    }
    if case_.start == case_.end_ {
      saw_empty_range = true
    }
    if total > 0 && case_.start <= 0 && case_.end_ >= total {
      saw_full_range = true
    }
    if total > 0 && (case_.start == 0 || case_.end_ == total) {
      saw_boundary_delete = true
    }
    if case_.start > total || case_.end_ > total {
      saw_out_of_bounds = true
    }
  }
  inspect(saw_empty, content="true")
  inspect(saw_one_leaf, content="true")
  inspect(saw_split_boundary, content="true")
  inspect(saw_deep_candidate, content="true")
  inspect(saw_negative, content="true")
  inspect(saw_empty_range, content="true")
  inspect(saw_full_range, content="true")
  inspect(saw_boundary_delete, content="true")
  inspect(saw_out_of_bounds, content="true")
}
