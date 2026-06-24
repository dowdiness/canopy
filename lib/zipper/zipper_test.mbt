///|
test "RoseNode leaf and internal construction" {
  let leaf = RoseNode::RoseNode(data=1)
  inspect(leaf.data, content="1")
  inspect(leaf.children.length(), content="0")
  let tree = RoseNode::RoseNode(data=0, children=[
    RoseNode::RoseNode(data=1),
    RoseNode::RoseNode(data=2),
    RoseNode::RoseNode(data=3),
  ])
  inspect(tree.children.length(), content="3")
  inspect(tree.children[1].data, content="2")
}

///|
test "RoseNode map transforms leaf and children data" {
  let tree = RoseNode::RoseNode(data=1, children=[
    RoseNode::RoseNode(data=2),
    RoseNode::RoseNode(data=3, children=[RoseNode::RoseNode(data=4)]),
  ])
  let mapped = tree.map(x => x.to_string())
  inspect(mapped.data, content="1")
  inspect(mapped.children[0].data, content="2")
  inspect(mapped.children[1].data, content="3")
  inspect(mapped.children[1].children[0].data, content="4")
}

///|
test "RoseNode map identity preserves tree" {
  let tree = RoseNode::RoseNode(data=0, children=[
    RoseNode::RoseNode(data=1),
    RoseNode::RoseNode(data=2, children=[RoseNode::RoseNode(data=3)]),
  ])
  assert_eq(tree.map(x => x), tree)
}

///|
test "from_root creates zipper at root" {
  let tree = RoseNode::RoseNode(data="hello")
  let z = RoseZipper::from_root(tree)
  inspect(z.focus.data, content="hello")
  inspect(z.depth, content="0")
}

///|
test "go_down to first child" {
  let tree = RoseNode::RoseNode(data="root", children=[
    RoseNode::RoseNode(data="a"),
    RoseNode::RoseNode(data="b"),
    RoseNode::RoseNode(data="c"),
  ])
  let z = RoseZipper::from_root(tree)
  let z1 = z.go_down().unwrap()
  inspect(z1.focus.data, content="a")
  inspect(z1.depth, content="1")
}

///|
test "go_down with index" {
  let tree = RoseNode::RoseNode(data=0, children=[
    RoseNode::RoseNode(data=10),
    RoseNode::RoseNode(data=20),
    RoseNode::RoseNode(data=30),
  ])
  let z = RoseZipper::from_root(tree)
  let z2 = z.go_down(index=2).unwrap()
  inspect(z2.focus.data, content="30")
}

///|
test "go_down boundary: leaf returns None" {
  let z = RoseZipper::from_root(RoseNode::RoseNode(data=1))
  inspect(z.go_down() is None, content="true")
}

///|
test "go_down boundary: negative index returns None" {
  let tree = RoseNode::RoseNode(data=0, children=[RoseNode::RoseNode(data=1)])
  let z = RoseZipper::from_root(tree)
  inspect(z.go_down(index=-1) is None, content="true")
}

///|
test "go_down boundary: out of bounds returns None" {
  let tree = RoseNode::RoseNode(data=0, children=[RoseNode::RoseNode(data=1)])
  let z = RoseZipper::from_root(tree)
  inspect(z.go_down(index=5) is None, content="true")
}

///|
test "go_up from child returns parent" {
  let tree = RoseNode::RoseNode(data="root", children=[
    RoseNode::RoseNode(data="a"),
    RoseNode::RoseNode(data="b"),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap()
  let z2 = z.go_up().unwrap()
  inspect(z2.focus.data, content="root")
  inspect(z2.depth, content="0")
}

///|
test "go_up at root returns None" {
  let z = RoseZipper::from_root(RoseNode::RoseNode(data=42))
  inspect(z.go_up() is None, content="true")
}

///|
test "go_down then go_up round-trip preserves tree" {
  let tree = RoseNode::RoseNode(data=1, children=[
    RoseNode::RoseNode(data=2, children=[RoseNode::RoseNode(data=5)]),
    RoseNode::RoseNode(data=3),
    RoseNode::RoseNode(data=4),
  ])
  let z = RoseZipper::from_root(tree)
  let z2 = z.go_down().unwrap().go_up().unwrap()
  assert_eq(z2.focus, tree)
}

///|
test "go_right traverses siblings" {
  let tree = RoseNode::RoseNode(data=0, children=[
    RoseNode::RoseNode(data=1),
    RoseNode::RoseNode(data=2),
    RoseNode::RoseNode(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap()
  inspect(z.focus.data, content="1")
  let z2 = z.go_right().unwrap()
  inspect(z2.focus.data, content="2")
  let z3 = z2.go_right().unwrap()
  inspect(z3.focus.data, content="3")
  inspect(z3.go_right() is None, content="true")
}

///|
test "go_left traverses siblings backward" {
  let tree = RoseNode::RoseNode(data=0, children=[
    RoseNode::RoseNode(data=1),
    RoseNode::RoseNode(data=2),
    RoseNode::RoseNode(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down(index=2).unwrap()
  inspect(z.focus.data, content="3")
  let z2 = z.go_left().unwrap()
  inspect(z2.focus.data, content="2")
  let z3 = z2.go_left().unwrap()
  inspect(z3.focus.data, content="1")
  inspect(z3.go_left() is None, content="true")
}

///|
test "go_left at first child returns None" {
  let tree = RoseNode::RoseNode(data=0, children=[
    RoseNode::RoseNode(data=1),
    RoseNode::RoseNode(data=2),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap()
  inspect(z.go_left() is None, content="true")
}

///|
test "go_left and go_right at root return None" {
  let tree = RoseNode::RoseNode(data=0, children=[RoseNode::RoseNode(data=1)])
  let z = RoseZipper::from_root(tree)
  inspect(z.go_left() is None, content="true")
  inspect(z.go_right() is None, content="true")
}

///|
test "go_right then go_left round-trip" {
  let tree = RoseNode::RoseNode(data=0, children=[
    RoseNode::RoseNode(data=1),
    RoseNode::RoseNode(data=2),
    RoseNode::RoseNode(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap()
  let z2 = z.go_right().unwrap().go_left().unwrap()
  inspect(z2.focus.data, content="1")
}

///|
test "lateral then up preserves tree" {
  let tree = RoseNode::RoseNode(data=0, children=[
    RoseNode::RoseNode(data=1),
    RoseNode::RoseNode(data=2),
    RoseNode::RoseNode(data=3),
  ])
  let z = RoseZipper::from_root(tree)
    .go_down()
    .unwrap()
    .go_right()
    .unwrap()
    .go_up()
    .unwrap()
  assert_eq(z.focus, tree)
}

///|
test "to_tree from root is identity" {
  let tree = RoseNode::RoseNode(data=1, children=[
    RoseNode::RoseNode(data=2, children=[RoseNode::RoseNode(data=5)]),
    RoseNode::RoseNode(data=3),
    RoseNode::RoseNode(data=4),
  ])
  assert_eq(RoseZipper::from_root(tree).to_tree(), tree)
}

///|
test "to_tree from deep position reconstructs full tree" {
  let tree = RoseNode::RoseNode(data=1, children=[
    RoseNode::RoseNode(data=2, children=[RoseNode::RoseNode(data=5)]),
    RoseNode::RoseNode(data=3),
    RoseNode::RoseNode(data=4),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap().go_down().unwrap()
  inspect(z.focus.data, content="5")
  assert_eq(z.to_tree(), tree)
}

///|
test "replace changes focused subtree" {
  let tree = RoseNode::RoseNode(data=1, children=[
    RoseNode::RoseNode(data=2),
    RoseNode::RoseNode(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down(index=1).unwrap()
  let z2 = z.replace(RoseNode::RoseNode(data=99))
  inspect(z2.focus.data, content="99")
  let rebuilt = z2.to_tree()
  inspect(rebuilt.children[1].data, content="99")
  // original focus unchanged (persistence)
  inspect(z.focus.data, content="3")
}

///|
test "modify transforms focused subtree" {
  let tree = RoseNode::RoseNode(data=1, children=[
    RoseNode::RoseNode(data=2),
    RoseNode::RoseNode(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down(index=1).unwrap()
  let z2 = z.modify(fn(n) {
    RoseNode::RoseNode(data=n.data * 10, children=n.children)
  })
  inspect(z2.focus.data, content="30")
  // verify modify propagates through to_tree
  let rebuilt = z2.to_tree()
  inspect(rebuilt.children[1].data, content="30")
  inspect(rebuilt.children[0].data, content="2")
}

///|
test "replace at root" {
  let tree = RoseNode::RoseNode(data=1)
  let z = RoseZipper::from_root(tree)
  let z2 = z.replace(RoseNode::RoseNode(data=99))
  inspect(z2.focus.data, content="99")
  assert_eq(z2.to_tree(), RoseNode::RoseNode(data=99))
}

///|
test "modify at root" {
  let tree = RoseNode::RoseNode(data=5, children=[RoseNode::RoseNode(data=10)])
  let z = RoseZipper::from_root(tree)
  let z2 = z.modify(fn(n) {
    RoseNode::RoseNode(data=n.data * 2, children=n.children)
  })
  let rebuilt = z2.to_tree()
  inspect(rebuilt.data, content="10")
  inspect(rebuilt.children[0].data, content="10")
}

///|
test "depth tracks navigation depth" {
  let tree = RoseNode::RoseNode(data=0, children=[
    RoseNode::RoseNode(data=1, children=[RoseNode::RoseNode(data=2)]),
  ])
  let z = RoseZipper::from_root(tree)
  inspect(z.depth(), content="0")
  let z1 = z.go_down().unwrap()
  inspect(z1.depth(), content="1")
  let z2 = z1.go_down().unwrap()
  inspect(z2.depth(), content="2")
}

///|
test "child_index tracks position among siblings" {
  let tree = RoseNode::RoseNode(data=0, children=[
    RoseNode::RoseNode(data=1),
    RoseNode::RoseNode(data=2),
    RoseNode::RoseNode(data=3),
  ])
  let z = RoseZipper::from_root(tree)
  inspect(z.child_index() is None, content="true")
  let z1 = z.go_down().unwrap()
  @debug.debug_inspect(z1.child_index(), content="Some(0)")
  let z2 = z1.go_right().unwrap()
  @debug.debug_inspect(z2.child_index(), content="Some(1)")
  let z3 = z2.go_right().unwrap()
  @debug.debug_inspect(z3.child_index(), content="Some(2)")
}

///|
test "is_root and is_leaf" {
  let tree = RoseNode::RoseNode(data=0, children=[RoseNode::RoseNode(data=1)])
  let z = RoseZipper::from_root(tree)
  inspect(z.is_root(), content="true")
  inspect(z.is_leaf(), content="false")
  let z1 = z.go_down().unwrap()
  inspect(z1.is_root(), content="false")
  inspect(z1.is_leaf(), content="true")
}

///|
test "num_children" {
  let tree = RoseNode::RoseNode(data=0, children=[
    RoseNode::RoseNode(data=1),
    RoseNode::RoseNode(data=2),
  ])
  let z = RoseZipper::from_root(tree)
  inspect(z.num_children(), content="2")
  let z1 = z.go_down().unwrap()
  inspect(z1.num_children(), content="0")
}

///|
test "to_path returns child indices from root" {
  let tree = RoseNode::RoseNode(data="r", children=[
    RoseNode::RoseNode(data="a", children=[
      RoseNode::RoseNode(data="x"),
      RoseNode::RoseNode(data="y"),
    ]),
    RoseNode::RoseNode(data="b"),
  ])
  let z = RoseZipper::from_root(tree)
    .go_down()
    .unwrap()
    .go_down(index=1)
    .unwrap()
  inspect(z.focus.data, content="y")
  @debug.debug_inspect(z.to_path(), content="[0, 1]")
}

///|
test "to_path at root is empty" {
  let z = RoseZipper::from_root(RoseNode::RoseNode(data=1))
  @debug.debug_inspect(z.to_path(), content="[]")
}

///|
test "focus_at navigates to position" {
  let tree = RoseNode::RoseNode(data="r", children=[
    RoseNode::RoseNode(data="a", children=[
      RoseNode::RoseNode(data="x"),
      RoseNode::RoseNode(data="y"),
    ]),
    RoseNode::RoseNode(data="b"),
  ])
  let z = RoseZipper::focus_at(tree, [0, 1]).unwrap()
  inspect(z.focus.data, content="y")
  inspect(z.depth(), content="2")
}

///|
test "focus_at with empty path stays at root" {
  let tree = RoseNode::RoseNode(data=1)
  let z = RoseZipper::focus_at(tree, []).unwrap()
  inspect(z.focus.data, content="1")
  inspect(z.is_root(), content="true")
}

///|
test "focus_at returns None on invalid path" {
  let tree = RoseNode::RoseNode(data=0, children=[RoseNode::RoseNode(data=1)])
  inspect(RoseZipper::focus_at(tree, [0, 5]) is None, content="true")
  inspect(RoseZipper::focus_at(tree, [3]) is None, content="true")
  inspect(RoseZipper::focus_at(tree, [-1]) is None, content="true")
}

///|
test "to_path and focus_at round-trip" {
  let tree = RoseNode::RoseNode(data=0, children=[
    RoseNode::RoseNode(data=1, children=[
      RoseNode::RoseNode(data=3),
      RoseNode::RoseNode(data=4),
    ]),
    RoseNode::RoseNode(data=2),
  ])
  let z = RoseZipper::from_root(tree)
    .go_down()
    .unwrap()
    .go_down(index=1)
    .unwrap()
  let path = z.to_path()
  let z2 = RoseZipper::focus_at(tree, path).unwrap()
  inspect(z2.focus.data, content="4")
  assert_eq(z.focus, z2.focus)
}

///|
test "persistence: old zipper unchanged after navigation" {
  let tree = RoseNode::RoseNode(data=0, children=[
    RoseNode::RoseNode(data=1),
    RoseNode::RoseNode(data=2),
  ])
  let z = RoseZipper::from_root(tree)
  let z1 = z.go_down().unwrap()
  // z is still at root
  inspect(z.focus.data, content="0")
  inspect(z.is_root(), content="true")
  // z1 at child
  inspect(z1.focus.data, content="1")
  // navigate from z1
  let z2 = z1.go_right().unwrap()
  // z1 unchanged
  inspect(z1.focus.data, content="1")
  @debug.debug_inspect(z1.child_index(), content="Some(0)")
  // z2 at sibling
  inspect(z2.focus.data, content="2")
  @debug.debug_inspect(z2.child_index(), content="Some(1)")
}
