// Property-based tests for reconcile.mbt using @qc (quickcheck).
// These tests verify invariants that hand-written snapshot tests cannot catch:
// ID uniqueness, ID preservation, kind propagation, idempotency,
// and LCS matching behavior under sibling insert/delete/reorder.

///|
/// Arbitrary impl for TestExpr — generates bounded random trees.
impl @quickcheck.Arbitrary for TestExpr with fn arbitrary(size, rs) {
  gen_test_expr(rs, if size < 1 { 1 } else if size > 4 { 4 } else { size })
}

///|
/// No-op shrink impl (required by quick_check_fn).
impl @qc.Shrink for TestExpr

///|
struct TestExprPair {
  old : TestExpr
  new : TestExpr
} derive(Debug)

///|
impl @quickcheck.Arbitrary for TestExprPair with fn arbitrary(size, rs) {
  let depth = if size < 1 { 1 } else if size > 4 { 4 } else { size }
  {
    old: gen_test_expr(rs.split(), depth),
    new: gen_test_expr(rs.split(), depth),
  }
}

///|
impl @qc.Shrink for TestExprPair

///|
/// Bounded-depth recursive generator for TestExpr trees.
fn gen_test_expr(rs : @splitmix.RandomState, depth : Int) -> TestExpr {
  if depth <= 0 {
    let tag = rs.split().next_positive_int() % 10
    Leaf("l" + tag.to_string())
  } else {
    let coin = rs.split().next_positive_int() % 3
    if coin == 0 {
      let tag = rs.split().next_positive_int() % 10
      Leaf("l" + tag.to_string())
    } else {
      let child_count = rs.split().next_positive_int() % 4
      let children : Array[TestExpr] = []
      for i = 0; i < child_count; i = i + 1 {
        children.push(gen_test_expr(rs.split(), depth - 1))
      }
      let tag = rs.split().next_positive_int() % 10
      Branch("b" + tag.to_string(), children)
    }
  }
}

///|
/// Convert a TestExpr into a ProjNode[TestExpr] with post-order IDs
/// (children numbered before parent, matching assign_fresh_ids).
fn to_proj_node(expr : TestExpr, counter : Ref[Int]) -> ProjNode[TestExpr] {
  let children : Array[ProjNode[TestExpr]] = match expr {
    Leaf(_) => []
    Branch(_, cs) => cs.map(fn(c) { to_proj_node(c, counter) })
  }
  let id = next_proj_node_id(counter)
  ProjNode(expr, 0, 0, id, children)
}

///|
/// Collect all node_ids from a ProjNode tree (pre-order).
fn collect_ids(node : ProjNode[TestExpr]) -> Array[Int] {
  let result : Array[Int] = []
  collect_ids_rec(node, result)
  result
}

///|
fn collect_ids_rec(node : ProjNode[TestExpr], acc : Array[Int]) -> Unit {
  acc.push(node.node_id)
  for child in node.children {
    collect_ids_rec(child, acc)
  }
}

///|
/// Collect all .kind values from a ProjNode tree (pre-order).
fn collect_kinds(node : ProjNode[TestExpr]) -> Array[TestExpr] {
  let result : Array[TestExpr] = []
  collect_kinds_rec(node, result)
  result
}

///|
fn collect_kinds_rec(node : ProjNode[TestExpr], acc : Array[TestExpr]) -> Unit {
  acc.push(node.kind)
  for child in node.children {
    collect_kinds_rec(child, acc)
  }
}

///|
/// Insert an element at position `idx` in an array (returns new array).
fn[T] insert_at(arr : Array[T], idx : Int, elem : T) -> Array[T] {
  let result : Array[T] = []
  for i = 0; i < arr.length(); i = i + 1 {
    if i == idx {
      result.push(elem)
    }
    result.push(arr[i])
  }
  if idx >= arr.length() {
    result.push(elem)
  }
  result
}

///|
/// Remove element at position `idx` from an array (returns new array).
fn[T] remove_at(arr : Array[T], idx : Int) -> Array[T] {
  let result : Array[T] = []
  for i = 0; i < arr.length(); i = i + 1 {
    if i != idx {
      result.push(arr[i])
    }
  }
  result
}

///|
/// Check that all elements in an array are unique.
fn all_unique(arr : Array[Int]) -> Bool {
  let seen : Map[Int, Bool] = Map([])
  for id in arr {
    if seen.contains(id) {
      return false
    }
    seen[id] = true
  }
  true
}

///|
/// Property 1: All NodeIds are unique after reconcile.
/// After reconcile(old, new, counter), the result tree has no duplicate IDs.
fn prop_unique_ids_after_reconcile(pair : TestExprPair) -> Bool {
  let old_expr = pair.old
  let new_expr = pair.new
  let old_counter = Ref(0)
  let old_node = to_proj_node(old_expr, old_counter)
  let new_counter = Ref(0)
  let new_node = to_proj_node(new_expr, new_counter)
  let counter = Ref(1000)
  let result = reconcile(old_node, new_node, counter)
  let ids = collect_ids(result)
  all_unique(ids)
}

///|
test "property: unique IDs after reconcile" {
  @qc.quick_check_fn(prop_unique_ids_after_reconcile)
}

///|
/// Property 2: Reconcile preserves all old IDs when old and new are identical trees.
/// Building two ProjNodes from the same TestExpr (with different ID ranges)
/// and reconciling should yield the old tree's IDs positionally.
fn prop_preserves_ids_for_identical_trees(expr : TestExpr) -> Bool {
  let counter = Ref(0)
  let old_node = to_proj_node(expr, counter)
  let new_counter = Ref(500)
  let new_node = to_proj_node(expr, new_counter)
  let reconcile_counter = Ref(1000)
  let result = reconcile(old_node, new_node, reconcile_counter)
  let old_ids = collect_ids(old_node)
  let result_ids = collect_ids(result)
  // Every ID from old should be in result
  if old_ids.length() != result_ids.length() {
    return false
  }
  for i = 0; i < old_ids.length(); i = i + 1 {
    if old_ids[i] != result_ids[i] {
      return false
    }
  }
  true
}

///|
test "property: preserves IDs for identical trees" {
  @qc.quick_check_fn(prop_preserves_ids_for_identical_trees)
}

///|
/// Property 3: Reconcile uses new kind values.
/// After reconcile, the .kind values should come from the new tree.
/// We test this by building two trees with the same shape but different labels.
fn prop_uses_new_kind_values(expr : TestExpr) -> Bool {
  let relabeled = relabel_expr(expr, "old_")
  let counter_old = Ref(0)
  let old_node = to_proj_node(relabeled, counter_old)
  let counter_new = Ref(500)
  let new_node = to_proj_node(expr, counter_new)
  let reconcile_counter = Ref(1000)
  let result = reconcile(old_node, new_node, reconcile_counter)
  let result_kinds = collect_kinds(result)
  let new_kinds = collect_kinds(new_node)
  if result_kinds.length() != new_kinds.length() {
    return false
  }
  for i = 0; i < result_kinds.length(); i = i + 1 {
    if result_kinds[i] != new_kinds[i] {
      return false
    }
  }
  true
}

///|
/// Relabel a TestExpr by prefixing all labels while preserving tree shape.
fn relabel_expr(expr : TestExpr, prefix : String) -> TestExpr {
  match expr {
    Leaf(s) => Leaf(prefix + s)
    Branch(s, cs) =>
      Branch(prefix + s, cs.map(fn(c) { relabel_expr(c, prefix) }))
  }
}

///|
test "property: uses new kind values after reconcile" {
  @qc.quick_check_fn(prop_uses_new_kind_values)
}

///|
/// Property 4: Reconcile is idempotent on stable trees.
/// reconcile(tree, tree) then reconcile(result, tree) should produce
/// the same IDs as the first reconcile.
fn prop_idempotent_on_stable(expr : TestExpr) -> Bool {
  let counter1 = Ref(0)
  let tree1 = to_proj_node(expr, counter1)
  let counter2 = Ref(500)
  let tree2 = to_proj_node(expr, counter2)
  let counter3 = Ref(800)
  let tree3 = to_proj_node(expr, counter3)
  // First reconcile
  let rc1 = Ref(1000)
  let result1 = reconcile(tree1, tree2, rc1)
  // Second reconcile: reconcile(result1, tree3)
  let rc2 = Ref(2000)
  let result2 = reconcile(result1, tree3, rc2)
  // IDs from result1 and result2 should be the same
  let ids1 = collect_ids(result1)
  let ids2 = collect_ids(result2)
  if ids1.length() != ids2.length() {
    return false
  }
  for i = 0; i < ids1.length(); i = i + 1 {
    if ids1[i] != ids2[i] {
      return false
    }
  }
  true
}

///|
test "property: reconcile is idempotent on stable trees" {
  @qc.quick_check_fn(prop_idempotent_on_stable)
}

///|
/// Property 5: Retained siblings keep their old IDs after a child insertion.
/// Given a Branch with children, insert a new Leaf in the middle to form
/// a new tree. Reconcile should preserve old IDs for the siblings that
/// remained (matched by LCS), and assign fresh IDs only for the inserted child.
fn prop_retained_siblings_keep_ids_after_insert(expr : TestExpr) -> Bool {
  // Only meaningful for Branch nodes with at least 1 child
  let children = match expr {
    Branch(_, cs) => if cs.length() > 0 { cs } else { return true }
    Leaf(_) => return true
  }
  let tag = match expr {
    Branch(t, _) => t
    _ => ""
  }
  let old_counter = Ref(0)
  let old_node = to_proj_node(expr, old_counter)
  // Build new tree with an extra Leaf inserted in the middle
  let insert_idx = children.length() / 2
  let new_children = insert_at(children, insert_idx, Leaf("inserted"))
  let new_expr = Branch(tag, new_children)
  let new_counter = Ref(500)
  let new_node = to_proj_node(new_expr, new_counter)
  let reconcile_counter = Ref(1000)
  let result = reconcile(old_node, new_node, reconcile_counter)
  // The old IDs for retained children should appear in the result.
  // Build a set of old child IDs
  let old_child_ids : Map[Int, Bool] = Map([])
  for child in old_node.children {
    old_child_ids[child.node_id] = true
  }
  // Count how many result children reuse an old child ID
  let mut reused = 0
  for child in result.children {
    if old_child_ids.contains(child.node_id) {
      reused = reused + 1
    }
  }
  // At least all original children should be matched (LCS finds them all
  // since they're in the same order with one insertion)
  reused >= old_node.children.length()
}

///|
test "property: retained siblings keep IDs after child insertion" {
  @qc.quick_check_fn(prop_retained_siblings_keep_ids_after_insert)
}

///|
fn exact_test_key(expr : TestExpr) -> String {
  match expr {
    Leaf(value) => "Leaf:" + value
    Branch(tag, _) => "Branch:" + tag
  }
}

///|
test "reconcile: positional fast path only accepts equal-kind sibling lists" {
  let old_node = to_proj_node(Branch("root", [Leaf("a"), Leaf("b")]), Ref(0))
  let same_shape = to_proj_node(
    Branch("root", [Leaf("x"), Leaf("y")]),
    Ref(500),
  )
  inspect(
    can_reconcile_children_positionally(
      old_node.children,
      same_shape.children,
      Map([]),
    ),
    content="true",
  )
  let different_kind = to_proj_node(
    Branch("root", [Leaf("x"), Branch("nested", [])]),
    Ref(500),
  )
  inspect(
    can_reconcile_children_positionally(
      old_node.children,
      different_kind.children,
      Map([]),
    ),
    content="false",
  )
  let inserted = to_proj_node(
    Branch("root", [Leaf("x"), Leaf("inserted"), Leaf("y")]),
    Ref(500),
  )
  inspect(
    can_reconcile_children_positionally(
      old_node.children,
      inserted.children,
      Map([]),
    ),
    content="false",
  )
  let hints : Map[NodeId, IdentityTransform] = Map([])
  hints[old_node.children[0].id()] = IdentityTransform::Opaque
  inspect(
    can_reconcile_children_positionally(
      old_node.children,
      same_shape.children,
      hints,
    ),
    content="false",
  )
}

///|
test "reconcile: append equal-kind siblings preserves positional IDs" {
  let old_node = to_proj_node(Branch("root", [Leaf("a"), Leaf("b")]), Ref(0))
  let new_node = to_proj_node(
    Branch("root", [Leaf("a"), Leaf("b"), Leaf("c")]),
    Ref(500),
  )
  let result = reconcile_with_exact_key(
    old_node,
    new_node,
    Ref(1000),
    exact_test_key,
  )
  inspect(
    result.children[0].node_id == old_node.children[0].node_id,
    content="true",
  )
  inspect(
    result.children[1].node_id == old_node.children[1].node_id,
    content="true",
  )
  inspect(
    result.children[2].node_id != old_node.children[0].node_id,
    content="true",
  )
}

///|
test "reconcile: prepend equal-kind siblings preserves positional IDs" {
  let old_node = to_proj_node(Branch("root", [Leaf("a"), Leaf("b")]), Ref(0))
  let new_node = to_proj_node(
    Branch("root", [Leaf("x"), Leaf("a"), Leaf("b")]),
    Ref(500),
  )
  let result = reconcile_with_exact_key(
    old_node,
    new_node,
    Ref(1000),
    exact_test_key,
  )
  inspect(
    result.children[1].node_id == old_node.children[0].node_id,
    content="true",
  )
  inspect(
    result.children[2].node_id == old_node.children[1].node_id,
    content="true",
  )
}

///|
test "reconcile: middle equal-kind insertion preserves positional IDs" {
  let old_node = to_proj_node(Branch("root", [Leaf("a"), Leaf("b")]), Ref(0))
  let new_node = to_proj_node(
    Branch("root", [Leaf("a"), Leaf("x"), Leaf("b")]),
    Ref(500),
  )
  let result = reconcile_with_exact_key(
    old_node,
    new_node,
    Ref(1000),
    exact_test_key,
  )
  inspect(
    result.children[0].node_id == old_node.children[0].node_id,
    content="true",
  )
  inspect(
    result.children[2].node_id == old_node.children[1].node_id,
    content="true",
  )
}

///|
test "reconcile: exact preference does not reduce match cardinality" {
  let old_node = to_proj_node(
    Branch("root", [Leaf("a"), Leaf("b"), Leaf("c")]),
    Ref(0),
  )
  let new_node = to_proj_node(
    Branch("root", [Leaf("x"), Leaf("y"), Leaf("z"), Leaf("a")]),
    Ref(500),
  )
  let result = reconcile_with_exact_key(
    old_node,
    new_node,
    Ref(1000),
    exact_test_key,
  )
  let old_ids : Map[Int, Bool] = Map([])
  for child in old_node.children {
    old_ids[child.node_id] = true
  }
  let mut reused = 0
  for child in result.children {
    if old_ids.contains(child.node_id) {
      reused += 1
    }
  }
  inspect(reused, content="3")
}

///|
test "reconcile: exact duplicate append preserves prefix identities" {
  let old_node = to_proj_node(Branch("root", [Leaf("a"), Leaf("a")]), Ref(0))
  let new_node = to_proj_node(
    Branch("root", [Leaf("a"), Leaf("a"), Leaf("a")]),
    Ref(500),
  )
  let result = reconcile_with_exact_key(
    old_node,
    new_node,
    Ref(1000),
    exact_test_key,
  )
  inspect(
    result.children[0].node_id == old_node.children[0].node_id,
    content="true",
  )
  inspect(
    result.children[1].node_id == old_node.children[1].node_id,
    content="true",
  )
  inspect(result.children[2].node_id >= 1000, content="true")
}

///|
test "reconcile: exact duplicate deletion preserves prefix identities" {
  let old_node = to_proj_node(
    Branch("root", [Leaf("a"), Leaf("a"), Leaf("a")]),
    Ref(0),
  )
  let new_node = to_proj_node(Branch("root", [Leaf("a"), Leaf("a")]), Ref(500))
  let result = reconcile_with_exact_key(
    old_node,
    new_node,
    Ref(1000),
    exact_test_key,
  )
  inspect(
    result.children[0].node_id == old_node.children[0].node_id,
    content="true",
  )
  inspect(
    result.children[1].node_id == old_node.children[1].node_id,
    content="true",
  )
}

///|
test "reconcile: mixed same-kind tie chooses earliest feasible pair" {
  let old_node = to_proj_node(
    Branch("root", [Leaf("a"), Leaf("b"), Leaf("c"), Leaf("d")]),
    Ref(0),
  )
  let new_node = to_proj_node(Branch("root", [Leaf("w"), Leaf("x")]), Ref(500))
  let result = reconcile_with_exact_key(
    old_node,
    new_node,
    Ref(1000),
    exact_test_key,
  )
  inspect(
    result.children[0].node_id == old_node.children[0].node_id,
    content="true",
  )
  inspect(
    result.children[1].node_id == old_node.children[1].node_id,
    content="true",
  )
}

///|
/// Property 6: After deleting a child, the number of reused old IDs equals
/// the LCS length between old and new children (by same_kind).
/// We can't assume WHICH old children are matched (LCS tie-breaking is
/// implementation-defined), but we can verify the COUNT of reused IDs
/// matches the number of surviving same-kind matches.
fn prop_reused_id_count_after_delete(expr : TestExpr) -> Bool {
  // Only meaningful for Branch nodes with at least 2 children
  let children = match expr {
    Branch(_, cs) => if cs.length() >= 2 { cs } else { return true }
    Leaf(_) => return true
  }
  let tag = match expr {
    Branch(t, _) => t
    _ => ""
  }
  let old_counter = Ref(0)
  let old_node = to_proj_node(expr, old_counter)
  // Build new tree with one child removed from the middle
  let remove_idx = children.length() / 2
  let new_children = remove_at(children, remove_idx)
  let new_expr = Branch(tag, new_children)
  let new_counter = Ref(500)
  let new_node = to_proj_node(new_expr, new_counter)
  let reconcile_counter = Ref(1000)
  let result = reconcile(old_node, new_node, reconcile_counter)
  // Result should have one fewer child
  if result.children.length() != old_node.children.length() - 1 {
    return false
  }
  // Collect all old child root IDs
  let old_child_ids : Map[Int, Bool] = Map([])
  for child in old_node.children {
    old_child_ids[child.node_id] = true
  }
  // Count how many result children reuse an old child ID
  let mut reused = 0
  for child in result.children {
    if old_child_ids.contains(child.node_id) {
      reused = reused + 1
    }
  }
  // new_children is a subsequence of old_children (one element removed),
  // so LCS length = new_children.length() (all can be matched).
  // Therefore ALL result children should reuse old IDs.
  reused == result.children.length()
}

///|
test "property: reused ID count correct after child deletion" {
  @qc.quick_check_fn(prop_reused_id_count_after_delete)
}

///|
/// Property 7: Reconcile is idempotent on different trees.
/// Given different old and new trees, reconcile(old, new) then
/// reconcile(result1, new_copy) should produce the same IDs —
/// a second pass on the same new tree shouldn't change anything.
fn prop_reconcile_idempotent_on_diff_trees(pair : TestExprPair) -> Bool {
  let old_expr = pair.old
  let new_expr = pair.new
  // Build old tree with counter range 0+
  let old_node = to_proj_node(old_expr, Ref(0))
  // Build first new tree with counter range 500+
  let new_node1 = to_proj_node(new_expr, Ref(500))
  // First reconcile with fresh IDs from 1000+
  let result1 = reconcile(old_node, new_node1, Ref(1000))
  // Build second copy of new tree with counter range 600+
  let new_node2 = to_proj_node(new_expr, Ref(600))
  // Second reconcile with fresh IDs from 2000+
  let result2 = reconcile(result1, new_node2, Ref(2000))
  // IDs should match positionally
  let ids1 = collect_ids(result1)
  let ids2 = collect_ids(result2)
  if ids1.length() != ids2.length() {
    return false
  }
  for i = 0; i < ids1.length(); i = i + 1 {
    if ids1[i] != ids2[i] {
      return false
    }
  }
  true
}

///|
test "property: reconcile idempotent on different trees" {
  @qc.quick_check_fn(prop_reconcile_idempotent_on_diff_trees)
}

///|
/// Property 8: Triple reconcile is stable — no drift after multiple passes.
/// Runs reconcile three times: old→new, result1→new, result2→new.
/// result2 and result3 should have identical IDs, catching any drift
/// that only manifests after multiple passes.
fn prop_reconcile_triple_idempotent(pair : TestExprPair) -> Bool {
  let old_expr = pair.old
  let new_expr = pair.new
  // Build old tree with counter range 0+
  let old_node = to_proj_node(old_expr, Ref(0))
  // Build three copies of new tree with different counter ranges
  let new_node1 = to_proj_node(new_expr, Ref(500))
  let new_node2 = to_proj_node(new_expr, Ref(600))
  let new_node3 = to_proj_node(new_expr, Ref(700))
  // Three rounds of reconcile with well-separated counter ranges
  let result1 = reconcile(old_node, new_node1, Ref(1000))
  let result2 = reconcile(result1, new_node2, Ref(2000))
  let result3 = reconcile(result2, new_node3, Ref(3000))
  // result2 and result3 should have identical IDs
  let ids2 = collect_ids(result2)
  let ids3 = collect_ids(result3)
  if ids2.length() != ids3.length() {
    return false
  }
  for i = 0; i < ids2.length(); i = i + 1 {
    if ids2[i] != ids3[i] {
      return false
    }
  }
  true
}

///|
test "property: triple reconcile is stable" {
  @qc.quick_check_fn(prop_reconcile_triple_idempotent)
}

///|
/// Count total nodes in a ProjNode tree.
fn count_nodes(node : ProjNode[TestExpr]) -> Int {
  let mut count = 1
  for child in node.children {
    count = count + count_nodes(child)
  }
  count
}

///|
/// Collect child counts at each node (pre-order) — captures tree shape.
fn collect_child_counts(node : ProjNode[TestExpr]) -> Array[Int] {
  let result : Array[Int] = []
  collect_child_counts_rec(node, result)
  result
}

///|
fn collect_child_counts_rec(
  node : ProjNode[TestExpr],
  acc : Array[Int],
) -> Unit {
  acc.push(node.children.length())
  for child in node.children {
    collect_child_counts_rec(child, acc)
  }
}

///|
/// Property 9: Result has the same shape as the new tree.
/// Node count and child counts at every position match.
fn prop_result_same_shape_as_new(pair : TestExprPair) -> Bool {
  let old_expr = pair.old
  let new_expr = pair.new
  let old_node = to_proj_node(old_expr, Ref(0))
  let new_node = to_proj_node(new_expr, Ref(500))
  let result = reconcile(old_node, new_node, Ref(1000))
  // Same total node count
  if count_nodes(result) != count_nodes(new_node) {
    return false
  }
  // Same child counts at every position (pre-order)
  let result_shape = collect_child_counts(result)
  let new_shape = collect_child_counts(new_node)
  if result_shape.length() != new_shape.length() {
    return false
  }
  for i = 0; i < result_shape.length(); i = i + 1 {
    if result_shape[i] != new_shape[i] {
      return false
    }
  }
  true
}

///|
test "property: result has same shape as new tree" {
  @qc.quick_check_fn(prop_result_same_shape_as_new)
}

///|
/// Property 10: Different root kind → all fresh IDs from counter range.
/// When same_kind fails at the root, no old IDs leak into the result.
fn prop_different_root_kind_all_fresh(expr : TestExpr) -> Bool {
  // Force old=Leaf, new=Branch (always different kind)
  let old_expr = Leaf("old")
  let new_expr = match expr {
    Leaf(s) => Branch(s, [])
    Branch(_, _) => expr
  }
  let old_node = to_proj_node(old_expr, Ref(0))
  let new_node = to_proj_node(new_expr, Ref(500))
  let counter_start = 1000
  let result = reconcile(old_node, new_node, Ref(counter_start))
  // All result IDs should be fresh (>= counter_start)
  let result_ids = collect_ids(result)
  for id in result_ids {
    if id < counter_start {
      return false
    }
  }
  // No old IDs should appear
  let old_ids = collect_ids(old_node)
  let old_set : Map[Int, Bool] = Map([])
  for id in old_ids {
    old_set[id] = true
  }
  for id in result_ids {
    if old_set.contains(id) {
      return false
    }
  }
  true
}

///|
test "property: different root kind produces all fresh IDs" {
  @qc.quick_check_fn(prop_different_root_kind_all_fresh)
}

///|
/// Property 11: Fresh IDs come from the counter range.
/// After reconcile, any ID not reused from old must be >= counter start.
fn prop_fresh_ids_from_counter_range(pair : TestExprPair) -> Bool {
  let old_expr = pair.old
  let new_expr = pair.new
  let old_node = to_proj_node(old_expr, Ref(0))
  let new_node = to_proj_node(new_expr, Ref(500))
  let counter_start = 1000
  let counter = Ref(counter_start)
  let result = reconcile(old_node, new_node, counter)
  // Build set of old IDs
  let old_id_set : Map[Int, Bool] = Map([])
  for id in collect_ids(old_node) {
    old_id_set[id] = true
  }
  // Every result ID should be either from old or from counter range
  let result_ids = collect_ids(result)
  for id in result_ids {
    if !old_id_set.contains(id) && id < counter_start {
      return false
    }
  }
  // Counter should have advanced by exactly the number of fresh IDs
  let mut fresh_count = 0
  for id in result_ids {
    if !old_id_set.contains(id) {
      fresh_count = fresh_count + 1
    }
  }
  counter.val == counter_start + fresh_count
}

///|
test "property: fresh IDs come from counter range" {
  @qc.quick_check_fn(prop_fresh_ids_from_counter_range)
}

///|
/// Property 12: Swapping two adjacent siblings preserves at least n-1 IDs.
/// LCS of a sequence with one adjacent swap has length n-1.
fn prop_swap_siblings_preserves_most_ids(expr : TestExpr) -> Bool {
  // Only meaningful for Branch with >= 2 children
  let (tag, children) = match expr {
    Branch(t, cs) => if cs.length() >= 2 { (t, cs) } else { return true }
    Leaf(_) => return true
  }
  let old_counter = Ref(0)
  let old_node = to_proj_node(expr, old_counter)
  // Swap first two children
  let swapped : Array[TestExpr] = []
  swapped.push(children[1])
  swapped.push(children[0])
  for i = 2; i < children.length(); i = i + 1 {
    swapped.push(children[i])
  }
  let new_expr = Branch(tag, swapped)
  let new_counter = Ref(500)
  let new_node = to_proj_node(new_expr, new_counter)
  let result = reconcile(old_node, new_node, Ref(1000))
  // Collect old child root IDs
  let old_child_ids : Map[Int, Bool] = Map([])
  for child in old_node.children {
    old_child_ids[child.node_id] = true
  }
  // Count reused IDs among result children
  let mut reused = 0
  for child in result.children {
    if old_child_ids.contains(child.node_id) {
      reused = reused + 1
    }
  }
  // LCS of adjacent swap = n-1, so at least n-1 children keep old IDs
  reused >= children.length() - 1
}

///|
test "property: swap siblings preserves at least n-1 IDs" {
  @qc.quick_check_fn(prop_swap_siblings_preserves_most_ids)
}

///|
/// Property 13: Deep leaf change preserves all ancestor IDs.
/// Change the leftmost leaf's label (same kind) — every ancestor
/// on the path should keep its old ID.
fn prop_deep_change_preserves_ancestor_ids(expr : TestExpr) -> Bool {
  // Need a tree with at least one Branch to be meaningful
  match expr {
    Leaf(_) => return true
    _ => ()
  }
  let old_counter = Ref(0)
  let old_node = to_proj_node(expr, old_counter)
  // Modify the leftmost leaf's label (Leaf→Leaf stays same_kind)
  let new_expr = modify_leftmost_leaf(expr)
  let new_counter = Ref(500)
  let new_node = to_proj_node(new_expr, new_counter)
  let result = reconcile(old_node, new_node, Ref(1000))
  // Collect ancestor IDs along the leftmost path in old and result
  let old_path_ids = collect_leftmost_path_ids(old_node)
  let result_path_ids = collect_leftmost_path_ids(result)
  if old_path_ids.length() != result_path_ids.length() {
    return false
  }
  // All ancestors (all but the last, which is the leaf) should keep IDs.
  // The leaf itself also keeps its ID since Leaf→Leaf is same_kind.
  for i = 0; i < old_path_ids.length(); i = i + 1 {
    if old_path_ids[i] != result_path_ids[i] {
      return false
    }
  }
  true
}

///|
/// Modify the leftmost leaf's label to "modified".
fn modify_leftmost_leaf(expr : TestExpr) -> TestExpr {
  match expr {
    Leaf(_) => Leaf("modified")
    Branch(tag, cs) =>
      if cs.length() == 0 {
        Branch(tag, cs)
      } else {
        let new_children : Array[TestExpr] = []
        new_children.push(modify_leftmost_leaf(cs[0]))
        for i = 1; i < cs.length(); i = i + 1 {
          new_children.push(cs[i])
        }
        Branch(tag, new_children)
      }
  }
}

///|
test "property: deep leaf change preserves ancestor IDs" {
  @qc.quick_check_fn(prop_deep_change_preserves_ancestor_ids)
}

///|
/// Collect node_ids along the leftmost path (root → leftmost leaf).
fn collect_leftmost_path_ids(node : ProjNode[TestExpr]) -> Array[Int] {
  let result : Array[Int] = []
  let mut current = node
  result.push(current.node_id)
  while current.children.length() > 0 {
    current = current.children[0]
    result.push(current.node_id)
  }
  result
}

///|
/// Property 14: No new-tree ID leakage.
/// Result IDs come from {old IDs} ∪ {counter range} only — never
/// from the new tree's temporary IDs.
fn prop_no_new_tree_id_leakage(pair : TestExprPair) -> Bool {
  let old_expr = pair.old
  let new_expr = pair.new
  let old_node = to_proj_node(old_expr, Ref(0))
  // New tree IDs in range 500-999
  let new_node = to_proj_node(new_expr, Ref(500))
  let counter_start = 1000
  let result = reconcile(old_node, new_node, Ref(counter_start))
  // Build sets of old and new IDs
  let old_id_set : Map[Int, Bool] = Map([])
  for id in collect_ids(old_node) {
    old_id_set[id] = true
  }
  let new_id_set : Map[Int, Bool] = Map([])
  for id in collect_ids(new_node) {
    new_id_set[id] = true
  }
  // Every result ID must be from old tree OR from counter range (>= 1000).
  // It must NOT be a new-tree-only ID (in new_id_set but not old_id_set
  // and not in counter range).
  for id in collect_ids(result) {
    if new_id_set.contains(id) && !old_id_set.contains(id) && id < counter_start {
      return false
    }
  }
  true
}

///|
test "property: no new-tree ID leakage" {
  @qc.quick_check_fn(prop_no_new_tree_id_leakage)
}

///|
/// Collect all (start, end) spans from a ProjNode tree (pre-order).
fn collect_spans(node : ProjNode[TestExpr]) -> Array[(Int, Int)] {
  let result : Array[(Int, Int)] = []
  collect_spans_rec(node, result)
  result
}

///|
fn collect_spans_rec(
  node : ProjNode[TestExpr],
  acc : Array[(Int, Int)],
) -> Unit {
  acc.push((node.start, node.end))
  for child in node.children {
    collect_spans_rec(child, acc)
  }
}

///|
/// Convert TestExpr to ProjNode with synthetic spans: each node gets
/// (start=offset, end=offset+1), incrementing in pre-order.
fn to_proj_node_with_spans(
  expr : TestExpr,
  counter : Ref[Int],
  span_offset : Ref[Int],
) -> ProjNode[TestExpr] {
  let my_span = span_offset.val
  span_offset.val = span_offset.val + 1
  let children : Array[ProjNode[TestExpr]] = match expr {
    Leaf(_) => []
    Branch(_, cs) =>
      cs.map(fn(c) { to_proj_node_with_spans(c, counter, span_offset) })
  }
  let id = next_proj_node_id(counter)
  ProjNode(expr, my_span, my_span + 1, id, children)
}

///|
/// Property 15: Result uses new tree's start/end positions.
/// Old and new trees from the same expr get different span offsets
/// (0-based vs 100-based). Result should match new tree's spans.
fn prop_result_uses_new_spans(expr : TestExpr) -> Bool {
  // Old tree: spans from 0+
  let old_node = to_proj_node_with_spans(expr, Ref(0), Ref(0))
  // New tree: spans from 100+ (different positions)
  let new_node = to_proj_node_with_spans(expr, Ref(500), Ref(100))
  let result = reconcile(old_node, new_node, Ref(1000))
  let result_spans = collect_spans(result)
  let new_spans = collect_spans(new_node)
  if result_spans.length() != new_spans.length() {
    return false
  }
  for i = 0; i < result_spans.length(); i = i + 1 {
    if result_spans[i] != new_spans[i] {
      return false
    }
  }
  true
}

///|
test "property: result uses new tree spans" {
  @qc.quick_check_fn(prop_result_uses_new_spans)
}

///|
/// Count nodes in a TestExpr tree (tree shape, not ProjNode).
fn count_expr_nodes(expr : TestExpr) -> Int {
  match expr {
    Leaf(_) => 1
    Branch(_, cs) =>
      1 + cs.fold(init=0, fn(acc, c) { acc + count_expr_nodes(c) })
  }
}

///|
/// Property 16: Trace event count is bounded by total nodes in both trees.
/// Each event corresponds to at most one (old_child, new_child) position, so
/// the total event count cannot exceed the combined node count.
fn prop_trace_event_count_bounded_by_total_nodes(pair : TestExprPair) -> Bool {
  let old_node = to_proj_node(pair.old, Ref(0))
  let new_node = to_proj_node(pair.new, Ref(500))
  let trace = Ref([])
  let _result = reconcile(old_node, new_node, Ref(1000), trace_ref=Some(trace))
  let bound = count_expr_nodes(pair.old) + count_expr_nodes(pair.new)
  trace.val.length() <= bound
}

///|
test "property: trace event count bounded by total nodes" {
  @qc.quick_check_fn(prop_trace_event_count_bounded_by_total_nodes)
}

// ---------------------------------------------------------------------------
// Characterization pins for the LCS-fallback paths (Phase 1 of
// docs/plans/2026-08-08-core-reconcile-engine-deepening.md).
// These pin today's observable behavior through the public seam so the
// engine extraction cannot silently change identity assignment, counter
// consumption, or fresh-id allocation order.
// ---------------------------------------------------------------------------

///|
/// Compare `reconcile` against `reconcile_hinted` with an empty hint map on
/// all observables: result tree, final counter, and trace. Empty hints bypass
/// all hint machinery, so the two must be observably identical.
fn reconcile_plain_equals_empty_hinted(
  old : ProjNode[TestExpr],
  new : ProjNode[TestExpr],
) -> Bool {
  let counter_a = Ref(1000)
  let trace_a = Ref([])
  let a = reconcile(old, new, counter_a, trace_ref=Some(trace_a))
  let counter_b = Ref(1000)
  let trace_b = Ref([])
  let b = reconcile_hinted(
    old,
    new,
    counter_b,
    Map([]),
    trace_ref=Some(trace_b),
  )
  a == b && counter_a.val == counter_b.val && trace_a.val == trace_b.val
}

///|
test "reconcile: LCS fallback on shorter duplicate list preserves suffix identity" {
  // old [L,L,L] → new [L,L]: unequal lengths force the LCS fallback;
  // end-backtracking keeps old[1]/old[2] ids on the new list (tail-oriented),
  // old[0] is deleted, and no fresh ids are consumed.
  let old_node = to_proj_node(
    Branch("root", [Leaf("a"), Leaf("b"), Leaf("c")]),
    Ref(0),
  )
  let new_node = to_proj_node(Branch("root", [Leaf("x"), Leaf("y")]), Ref(500))
  let counter = Ref(1000)
  let result = reconcile(old_node, new_node, counter)
  inspect(
    result.children[0].node_id == old_node.children[1].node_id,
    content="true",
  )
  inspect(
    result.children[1].node_id == old_node.children[2].node_id,
    content="true",
  )
  inspect(counter.val, content="1000")
}

///|
test "reconcile: LCS fallback on longer duplicate list carries old ids onto the new suffix" {
  // old [L,L] → new [L,L,L]: end-backtracking maps old[0]→new[1] and
  // old[1]→new[2]; new[0] is fresh (suffix-aligned carry, not prefix).
  let old_node = to_proj_node(Branch("root", [Leaf("a"), Leaf("b")]), Ref(0))
  let new_node = to_proj_node(
    Branch("root", [Leaf("x"), Leaf("y"), Leaf("z")]),
    Ref(500),
  )
  let counter = Ref(1000)
  let result = reconcile(old_node, new_node, counter)
  inspect(result.children[0].node_id, content="1000")
  inspect(
    result.children[1].node_id == old_node.children[0].node_id,
    content="true",
  )
  inspect(
    result.children[2].node_id == old_node.children[1].node_id,
    content="true",
  )
  inspect(counter.val, content="1001")
}

///|
test "reconcile: LCS fallback crossing tie drops the trailing old sibling" {
  // old [L,B] → new [B,L]: the `dp[i-1][j] >= dp[i][j-1]` tie rule drops the
  // trailing old B (Deleted); old L keeps its id on the new L; new B is fresh.
  let old_node = to_proj_node(
    Branch("root", [Leaf("a"), Branch("b", [])]),
    Ref(0),
  )
  let new_node = to_proj_node(
    Branch("root", [Branch("b", []), Leaf("x")]),
    Ref(500),
  )
  let counter = Ref(1000)
  let result = reconcile(old_node, new_node, counter)
  inspect(result.children[0].node_id, content="1000")
  inspect(
    result.children[1].node_id == old_node.children[0].node_id,
    content="true",
  )
  inspect(counter.val, content="1001")
}

///|
test "reconcile: hinted mode with empty hints matches plain on fallback" {
  // Empty hints bypass all hint machinery; reconcile_hinted must be
  // observably identical to reconcile on the fallback shapes of tests 1–3
  // (result tree, final counter, and trace).
  let old_short = to_proj_node(
    Branch("root", [Leaf("a"), Leaf("b"), Leaf("c")]),
    Ref(0),
  )
  let new_short = to_proj_node(Branch("root", [Leaf("x"), Leaf("y")]), Ref(500))
  inspect(
    reconcile_plain_equals_empty_hinted(old_short, new_short),
    content="true",
  )
  let old_long = to_proj_node(Branch("root", [Leaf("a"), Leaf("b")]), Ref(0))
  let new_long = to_proj_node(
    Branch("root", [Leaf("x"), Leaf("y"), Leaf("z")]),
    Ref(500),
  )
  inspect(
    reconcile_plain_equals_empty_hinted(old_long, new_long),
    content="true",
  )
  let old_cross = to_proj_node(
    Branch("root", [Leaf("a"), Branch("b", [])]),
    Ref(0),
  )
  let new_cross = to_proj_node(
    Branch("root", [Branch("b", []), Leaf("x")]),
    Ref(500),
  )
  inspect(
    reconcile_plain_equals_empty_hinted(old_cross, new_cross),
    content="true",
  )
}

///|
test "reconcile: hinted non-empty fallback combines exclusion, LCS, and singleton pairing" {
  // old [Leaf a@1, Leaf b@2] → new [Leaf c@20, Branch(w,[Leaf x@21])@22].
  // Wrap(1) excludes old Leaf a from LCS (its hint lands on the wrapper);
  // LCS matches old Leaf b ↔ new Leaf c; the wrapper itself is fresh (1000)
  // and its Leaf child carries old Leaf a's id. Unequal kinds at equal length
  // force the fallback.
  let old = ProjNode(Branch("root", [Leaf("a"), Leaf("b")]), 0, 5, 0, [
    ProjNode(Leaf("a"), 0, 1, 1, []),
    ProjNode(Leaf("b"), 1, 2, 2, []),
  ])
  let new_ = ProjNode(
    Branch("root", [Leaf("c"), Branch("w", [Leaf("x")])]),
    0,
    5,
    23,
    [
      ProjNode(Leaf("c"), 0, 1, 20, []),
      ProjNode(Branch("w", [Leaf("x")]), 1, 3, 22, [
        ProjNode(Leaf("x"), 1, 2, 21, []),
      ]),
    ],
  )
  let hints = mk_hints([(1, IdentityTransform::Wrap(inner=NodeId::from_int(1)))])
  let counter = Ref(1000)
  let trace = Ref([])
  let result = reconcile_hinted(
    old,
    new_,
    counter,
    hints,
    trace_ref=Some(trace),
  )
  // LCS match: old Leaf b → new Leaf c
  inspect(result.children[0].node_id == old.children[1].node_id, content="true")
  // hint pair: wrapper fresh, its child carries old Leaf a's id
  inspect(result.children[1].node_id, content="1000")
  inspect(
    result.children[1].children[0].node_id == old.children[0].node_id,
    content="true",
  )
  inspect(counter.val, content="1001")
  // trace: Matched(Leaf b), Wrapped, Matched(wrapper, old_index=-1), Deleted(old Leaf a)
  inspect(trace.val.length(), content="4")
  guard trace.val[0] is Matched(_, 1, 0, _, _) else {
    fail("first should be Matched (old Leaf b ↔ new Leaf c)")
  }
  guard trace.val[1] is Wrapped(_, _, _) else {
    fail("second should be Wrapped")
  }
  guard trace.val[2] is Matched(_, -1, 1, _, _) else {
    fail("third should be Matched with old_index=-1")
  }
  guard trace.val[3] is Deleted(_, 0, _, _) else {
    fail("fourth should be Deleted (old Leaf a)")
  }
}

///|
test "reconcile: fallback freshening consumes counter exactly for unmatched new nodes" {
  // Crossing tie [L,B]→[B,L] and long-list [L,L]→[L,L,L] each consume exactly
  // one fresh id (the unmatched new node).
  let old_cross = to_proj_node(
    Branch("root", [Leaf("a"), Branch("b", [])]),
    Ref(0),
  )
  let new_cross = to_proj_node(
    Branch("root", [Branch("b", []), Leaf("x")]),
    Ref(500),
  )
  let counter_cross = Ref(1000)
  let _ = reconcile(old_cross, new_cross, counter_cross)
  inspect(counter_cross.val, content="1001")
  let old_long = to_proj_node(Branch("root", [Leaf("a"), Leaf("b")]), Ref(0))
  let new_long = to_proj_node(
    Branch("root", [Leaf("x"), Leaf("y"), Leaf("z")]),
    Ref(500),
  )
  let counter_long = Ref(1000)
  let _ = reconcile(old_long, new_long, counter_long)
  inspect(counter_long.val, content="1001")
}

///|
test "reconcile: fully-matched fallback consumes no fresh ids" {
  // old [L,B,L] → new [L,L]: unequal lengths force the LCS fallback, every
  // new node is matched (old[0]→new[0], old[2]→new[1]), old[1] is deleted,
  // and the counter is untouched. (Equal-length same-kind lists take the
  // positional fast path and cannot pin the fallback.)
  let old_node = to_proj_node(
    Branch("root", [Leaf("a"), Branch("b", []), Leaf("c")]),
    Ref(0),
  )
  let new_node = to_proj_node(Branch("root", [Leaf("x"), Leaf("y")]), Ref(500))
  let counter = Ref(1000)
  let result = reconcile(old_node, new_node, counter)
  inspect(
    result.children[0].node_id == old_node.children[0].node_id,
    content="true",
  )
  inspect(
    result.children[1].node_id == old_node.children[2].node_id,
    content="true",
  )
  inspect(counter.val, content="1000")
}

///|
test "reconcile: exact-key freshening consumes counter exactly for unmatched new nodes" {
  // old [L,B] → new [B,L] via exact key: the B↔B diagonal carries the
  // fingerprint bonus (old "b" vs new "b" have equal payloads), so exact-key
  // matches old B → new B and freshens the new L — exactly 1 consumed.
  // (Plain reconcile drops the old B instead; see the crossing-tie test.)
  let old_node = to_proj_node(
    Branch("root", [Leaf("a"), Branch("b", [])]),
    Ref(0),
  )
  let new_node = to_proj_node(
    Branch("root", [Branch("b", []), Leaf("x")]),
    Ref(500),
  )
  let counter = Ref(1000)
  let result = reconcile_with_exact_key(
    old_node, new_node, counter, exact_test_key,
  )
  inspect(
    result.children[0].node_id == old_node.children[1].node_id,
    content="true",
  )
  inspect(result.children[1].node_id, content="1000")
  inspect(counter.val, content="1001")
}

///|
test "reconcile: two fresh subtrees allocate ids in sibling order, post-order within" {
  // Two unmatched new subtrees: ids are allocated in new-index sibling order,
  // post-order inside each subtree (child before parent). This pins
  // allocation order, not just counter deltas.
  let old_node = to_proj_node(Branch("root", []), Ref(0))
  let new_node = to_proj_node(
    Branch("root", [Branch("s1", [Leaf("a")]), Branch("s2", [])]),
    Ref(500),
  )
  let counter = Ref(1000)
  let result = reconcile(old_node, new_node, counter)
  // subtree s1: Leaf gets 1000, Branch gets 1001; subtree s2: Branch gets 1002
  inspect(result.children[0].children[0].node_id, content="1000")
  inspect(result.children[0].node_id, content="1001")
  inspect(result.children[1].node_id, content="1002")
  inspect(counter.val, content="1003")
}
