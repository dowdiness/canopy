///|
/// Test-only generated trees for DOM patch application properties.
enum PatchTree {
  Element(tag~ : String, children~ : Array[PatchTree])
  Text(value~ : String)
  ExprSpan(raw~ : String)
} derive(Debug, Eq)

///|
struct PatchTreePair {
  old : PatchTree
  new : PatchTree
} derive(Debug)

///|
fn PatchTreePair::PatchTreePair(
  old~ : PatchTree,
  new~ : PatchTree,
) -> PatchTreePair {
  { old, new }
}

///|
impl @quickcheck.Arbitrary for PatchTreePair with fn arbitrary(size, rs) {
  let depth = if size < 1 { 1 } else if size > 4 { 4 } else { size }
  PatchTreePair(
    old=gen_patch_tree(rs.split(), depth),
    new=gen_patch_tree(rs.split(), depth),
  )
}

///|
impl @qc.Shrink for PatchTree with fn shrink(tree) {
  match tree {
    PatchTree::Element(tag~, children~) =>
      if children.is_empty() {
        Iter::empty()
      } else {
        Iter::singleton(PatchTree::Element(tag~, children=[])).concat(
          @qc.Shrink::shrink(children).map(children1 => {
            PatchTree::Element(tag~, children=children1)
          }),
        )
      }
    PatchTree::Text(value~) =>
      @qc.Shrink::shrink(value).map(value1 => PatchTree::Text(value=value1))
    PatchTree::ExprSpan(raw~) =>
      @qc.Shrink::shrink(raw).map(raw1 => PatchTree::ExprSpan(raw=raw1))
  }
}

///|
impl @qc.Shrink for PatchTreePair with fn shrink(pair) {
  let old = pair.old
  let new = pair.new
  @qc.Shrink::shrink(old)
  .map(old1 => PatchTreePair(old=old1, new~))
  .concat(@qc.Shrink::shrink(new).map(new1 => PatchTreePair(old~, new=new1)))
}

///|
fn gen_patch_tree(rs : @splitmix.RandomState, depth : Int) -> PatchTree {
  if depth <= 0 {
    gen_patch_leaf(rs)
  } else {
    let choice = rs.split().next_positive_int() % 4
    if choice == 0 {
      gen_patch_leaf(rs.split())
    } else {
      let tags = ["div", "span", "p"]
      let tag = tags[rs.split().next_positive_int() % tags.length()]
      let child_count = rs.split().next_positive_int() % 4
      let children = Array::makei(child_count, _ => {
        gen_patch_tree(rs.split(), depth - 1)
      })
      PatchTree::Element(tag~, children~)
    }
  }
}

///|
fn gen_patch_leaf(rs : @splitmix.RandomState) -> PatchTree {
  let values = ["", "a", "b", "<", ">", "{", "}", "&", "a<> {}"]
  let value = values[rs.next_positive_int() % values.length()]
  if rs.split().next_positive_int() % 2 == 0 {
    PatchTree::Text(value~)
  } else {
    PatchTree::ExprSpan(raw=value)
  }
}

///|
fn lower_patch_tree(
  tree : PatchTree,
  counter : Ref[Int],
) -> (@jsx.JsxNode, @core.ProjNode[@jsx.JsxNode]) {
  match tree {
    PatchTree::Element(tag~, children~) => {
      let lowered = children.map(child => lower_patch_tree(child, counter))
      let jsx_children = lowered.map(pair => pair.0)
      let proj_children = lowered.map(pair => pair.1)
      let kind = @jsx.JsxNode::Element(tag~, attrs=[], children=jsx_children)
      let node = @core.ProjNode::ProjNode(
        kind,
        0,
        0,
        @core.next_proj_node_id(counter),
        proj_children,
      )
      (kind, node)
    }
    PatchTree::Text(value~) => {
      let kind = @jsx.JsxNode::Text(value)
      let node = @core.ProjNode::ProjNode(
        kind,
        0,
        0,
        @core.next_proj_node_id(counter),
        [],
      )
      (kind, node)
    }
    PatchTree::ExprSpan(raw~) => {
      let kind = @jsx.JsxNode::ExprSpan(raw~)
      let node = @core.ProjNode::ProjNode(
        kind,
        0,
        0,
        @core.next_proj_node_id(counter),
        [],
      )
      (kind, node)
    }
  }
}

///|
fn lower_patch_root(
  tree : PatchTree,
  counter : Ref[Int],
) -> @core.ProjNode[@jsx.JsxNode] {
  let (kind, node) = lower_patch_tree(tree, counter)
  let root_kind = @jsx.JsxNode::Root(children=[kind])
  @core.ProjNode::ProjNode(root_kind, 0, 0, 0, [node])
}

///|
fn patch_tree_ids(root : @core.ProjNode[@jsx.JsxNode]) -> Array[Int] {
  let ids : Array[Int] = []
  for child in root.children {
    collect_patch_tree_ids(child, ids)
  }
  ids
}

///|
fn collect_patch_tree_ids(
  node : @core.ProjNode[@jsx.JsxNode],
  ids : Array[Int],
) -> Unit {
  ids.push(node.node_id)
  for child in node.children {
    collect_patch_tree_ids(child, ids)
  }
}

///|
fn patch_ids_unique_and_mounted(ids : Array[Int]) -> Bool {
  !ids.contains(0) && all_unique_patch_ids(ids)
}

///|
fn all_unique_patch_ids(ids : Array[Int]) -> Bool {
  let seen = @set.Set::Set([])
  for id in ids {
    if !seen.add_and_check(id) {
      return false
    }
  }
  true
}

///|
fn prop_generated_patch_model_equivalence(pair : PatchTreePair) -> Bool {
  let old = lower_patch_root(pair.old, Ref(1))
  let new_raw = lower_patch_root(pair.new, Ref(100_000))
  if !patch_ids_unique_and_mounted(patch_tree_ids(old)) {
    return false
  }
  if !patch_ids_unique_and_mounted(patch_tree_ids(new_raw)) {
    return false
  }

  let (old_first_patches, old_mounted) = reconcile(old, [])
  let old_model = match DryRunModel::empty().apply(old_first_patches) {
    Ok(model) => model
    Err(_) => return false
  }
  let new = reconcile_jsx_projection(old, new_raw, Ref(1_000_000), None)
  let (incremental_patches, incremental_ids) = reconcile(new, old_mounted)
  let (fresh_patches, fresh_ids) = reconcile(new, [])
  let incremental_model = match old_model.apply(incremental_patches) {
    Ok(model) => model
    Err(_) => return false
  }
  let fresh_model = match DryRunModel::empty().apply(fresh_patches) {
    Ok(model) => model
    Err(_) => return false
  }
  patch_ids_unique_and_mounted(incremental_ids) &&
  patch_ids_unique_and_mounted(fresh_ids) &&
  incremental_ids == fresh_ids &&
  incremental_model.shape() == fresh_model.shape()
}

///|
test "property: generated patch application matches fresh render" {
  @qc.quick_check_fn(prop_generated_patch_model_equivalence)
}

///|
fn corrupt_first_make_index(patches : Array[DomPatch]) -> Array[DomPatch] {
  let changed = Ref(false)
  let result : Array[DomPatch] = []
  for patch in patches {
    match patch {
      MakeElement(parent_id, node_id, tag, attrs, index) if !changed.val => {
        changed.val = true
        result.push(
          MakeElement(
            parent_id,
            node_id,
            tag,
            attrs,
            if index == 0 {
              1
            } else {
              0
            },
          ),
        )
      }
      MakeText(parent_id, node_id, value, index) if !changed.val => {
        changed.val = true
        result.push(
          MakeText(parent_id, node_id, value, if index == 0 { 1 } else { 0 }),
        )
      }
      MakeExprSpan(parent_id, node_id, raw, index) if !changed.val => {
        changed.val = true
        result.push(
          MakeExprSpan(parent_id, node_id, raw, if index == 0 { 1 } else { 0 }),
        )
      }
      _ => result.push(patch)
    }
  }
  result
}

///|
test "property detector rejects in-bounds insertion-index corruption" {
  let old_tree = PatchTree::Element(tag="div", children=[
    PatchTree::Text(value="a"),
    PatchTree::Text(value="b"),
  ])
  let new_tree = PatchTree::Element(tag="div", children=[
    PatchTree::Text(value="a"),
    PatchTree::Text(value="new"),
    PatchTree::Text(value="b"),
  ])
  let old = lower_patch_root(old_tree, Ref(1))
  let new_raw = lower_patch_root(new_tree, Ref(100_000))
  let (old_patches, old_ids) = reconcile(old, [])
  let old_model = DryRunModel::empty().apply(old_patches).unwrap()
  let new = reconcile_jsx_projection(old, new_raw, Ref(1_000_000), None)
  let (incremental, _) = reconcile(new, old_ids)
  let (fresh, _) = reconcile(new, [])
  let expected = DryRunModel::empty().apply(fresh).unwrap()
  let corrupted = corrupt_first_make_index(incremental)
  let corrupted_model = old_model.apply(corrupted).unwrap()
  inspect(corrupted_model.shape() != expected.shape(), content="true")
}

///|
fn apply_patch_transition(
  old_tree : PatchTree,
  new_tree : PatchTree,
) -> DryRunModel {
  let old = lower_patch_root(old_tree, Ref(1))
  let new_raw = lower_patch_root(new_tree, Ref(100_000))
  let (old_patches, old_ids) = reconcile(old, [])
  let old_model = DryRunModel::empty().apply(old_patches).unwrap()
  let new = reconcile_jsx_projection(old, new_raw, Ref(1_000_000), None)
  let (patches, _) = reconcile(new, old_ids)
  old_model.apply(patches).unwrap()
}

///|
test "patch transition preserves text and expression sibling ordering" {
  let result = apply_patch_transition(
    PatchTree::Element(tag="div", children=[
      PatchTree::Text(value="a"),
      PatchTree::ExprSpan(raw="x"),
      PatchTree::Text(value="b"),
    ]),
    PatchTree::Element(tag="div", children=[
      PatchTree::Text(value="b"),
      PatchTree::Text(value="new"),
      PatchTree::ExprSpan(raw="y"),
    ]),
  )
  inspect(result.shape(), content="[E(4,div,0,[T(1,b),T(1000000,new),X(2,y)])]")
}

///|
test "patch transition handles nested removal and insertion" {
  let result = apply_patch_transition(
    PatchTree::Element(tag="div", children=[
      PatchTree::Element(tag="span", children=[PatchTree::Text(value="old")]),
    ]),
    PatchTree::Element(tag="div", children=[
      PatchTree::Element(tag="span", children=[
        PatchTree::Text(value="new"),
        PatchTree::ExprSpan(raw="value"),
      ]),
    ]),
  )
  inspect(
    result.shape(),
    content="[E(3,div,0,[E(2,span,0,[T(1,new),X(1000000,value)])])]",
  )
}

///|
test "patch transition handles mixed element text and expression siblings" {
  let result = apply_patch_transition(
    PatchTree::Element(tag="div", children=[
      PatchTree::Element(tag="span", children=[]),
      PatchTree::Text(value="old"),
      PatchTree::ExprSpan(raw="old"),
    ]),
    PatchTree::Element(tag="div", children=[
      PatchTree::Text(value="new"),
      PatchTree::Element(tag="span", children=[]),
      PatchTree::ExprSpan(raw="new"),
    ]),
  )
  inspect(
    result.shape(),
    content="[E(4,div,0,[T(1000000,new),E(1,span,0,[]),X(3,new)])]",
  )
}
