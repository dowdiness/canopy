///|
test "RoseNode leaf and internal construction" {
  let leaf = RoseNode::new(data=1)
  inspect(leaf.data, content="1")
  inspect(leaf.children.length(), content="0")
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  inspect(tree.children.length(), content="3")
  inspect(tree.children[1].data, content="2")
}

///|
test "from_root creates zipper at root" {
  let tree = RoseNode::new(data="hello")
  let z = RoseZipper::from_root(tree)
  inspect(z.focus.data, content="hello")
  inspect(z.depth, content="0")
}

///|
test "go_down to first child" {
  let tree = RoseNode::new(data="root", children=[
    RoseNode::new(data="a"),
    RoseNode::new(data="b"),
    RoseNode::new(data="c"),
  ])
  let z = RoseZipper::from_root(tree)
  let z1 = z.go_down().unwrap()
  inspect(z1.focus.data, content="a")
  inspect(z1.depth, content="1")
}

///|
test "go_down with index" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=10),
    RoseNode::new(data=20),
    RoseNode::new(data=30),
  ])
  let z = RoseZipper::from_root(tree)
  let z2 = z.go_down(index=2).unwrap()
  inspect(z2.focus.data, content="30")
}

///|
test "go_down boundary: leaf returns None" {
  let z = RoseZipper::from_root(RoseNode::new(data=1))
  inspect(z.go_down(), content="None")
}

///|
test "go_down boundary: negative index returns None" {
  let tree = RoseNode::new(data=0, children=[RoseNode::new(data=1)])
  let z = RoseZipper::from_root(tree)
  inspect(z.go_down(index=-1), content="None")
}

///|
test "go_down boundary: out of bounds returns None" {
  let tree = RoseNode::new(data=0, children=[RoseNode::new(data=1)])
  let z = RoseZipper::from_root(tree)
  inspect(z.go_down(index=5), content="None")
}

///|
test "go_up from child returns parent" {
  let tree = RoseNode::new(data="root", children=[
    RoseNode::new(data="a"),
    RoseNode::new(data="b"),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap()
  let z2 = z.go_up().unwrap()
  inspect(z2.focus.data, content="root")
  inspect(z2.depth, content="0")
}

///|
test "go_up at root returns None" {
  let z = RoseZipper::from_root(RoseNode::new(data=42))
  inspect(z.go_up(), content="None")
}

///|
test "go_down then go_up round-trip preserves tree" {
  let tree = RoseNode::new(data=1, children=[
    RoseNode::new(data=2, children=[RoseNode::new(data=5)]),
    RoseNode::new(data=3),
    RoseNode::new(data=4),
  ])
  let z = RoseZipper::from_root(tree)
  let z2 = z.go_down().unwrap().go_up().unwrap()
  assert_eq(z2.focus, tree)
}

///|
test "go_right traverses siblings" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap()
  inspect(z.focus.data, content="1")
  let z2 = z.go_right().unwrap()
  inspect(z2.focus.data, content="2")
  let z3 = z2.go_right().unwrap()
  inspect(z3.focus.data, content="3")
  inspect(z3.go_right(), content="None")
}

///|
test "go_left traverses siblings backward" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down(index=2).unwrap()
  inspect(z.focus.data, content="3")
  let z2 = z.go_left().unwrap()
  inspect(z2.focus.data, content="2")
  let z3 = z2.go_left().unwrap()
  inspect(z3.focus.data, content="1")
  inspect(z3.go_left(), content="None")
}

///|
test "go_left at first child returns None" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap()
  inspect(z.go_left(), content="None")
}

///|
test "go_left and go_right at root return None" {
  let tree = RoseNode::new(data=0, children=[RoseNode::new(data=1)])
  let z = RoseZipper::from_root(tree)
  inspect(z.go_left(), content="None")
  inspect(z.go_right(), content="None")
}

///|
test "go_right then go_left round-trip" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap()
  let z2 = z.go_right().unwrap().go_left().unwrap()
  inspect(z2.focus.data, content="1")
}

///|
test "lateral then up preserves tree" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
    RoseNode::new(data=3),
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
  let tree = RoseNode::new(data=1, children=[
    RoseNode::new(data=2, children=[RoseNode::new(data=5)]),
    RoseNode::new(data=3),
    RoseNode::new(data=4),
  ])
  assert_eq(RoseZipper::from_root(tree).to_tree(), tree)
}

///|
test "to_tree from deep position reconstructs full tree" {
  let tree = RoseNode::new(data=1, children=[
    RoseNode::new(data=2, children=[RoseNode::new(data=5)]),
    RoseNode::new(data=3),
    RoseNode::new(data=4),
  ])
  let z = RoseZipper::from_root(tree).go_down().unwrap().go_down().unwrap()
  inspect(z.focus.data, content="5")
  assert_eq(z.to_tree(), tree)
}

///|
test "replace changes focused subtree" {
  let tree = RoseNode::new(data=1, children=[
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down(index=1).unwrap()
  let z2 = z.replace(RoseNode::new(data=99))
  inspect(z2.focus.data, content="99")
  let rebuilt = z2.to_tree()
  inspect(rebuilt.children[1].data, content="99")
  // original focus unchanged (persistence)
  inspect(z.focus.data, content="3")
}

///|
test "modify transforms focused subtree" {
  let tree = RoseNode::new(data=1, children=[
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  let z = RoseZipper::from_root(tree).go_down(index=1).unwrap()
  let z2 = z.modify(fn(n) {
    RoseNode::new(data=n.data * 10, children=n.children)
  })
  inspect(z2.focus.data, content="30")
  // verify modify propagates through to_tree
  let rebuilt = z2.to_tree()
  inspect(rebuilt.children[1].data, content="30")
  inspect(rebuilt.children[0].data, content="2")
}

///|
test "replace at root" {
  let tree = RoseNode::new(data=1)
  let z = RoseZipper::from_root(tree)
  let z2 = z.replace(RoseNode::new(data=99))
  inspect(z2.focus.data, content="99")
  assert_eq(z2.to_tree(), RoseNode::new(data=99))
}

///|
test "modify at root" {
  let tree = RoseNode::new(data=5, children=[RoseNode::new(data=10)])
  let z = RoseZipper::from_root(tree)
  let z2 = z.modify(fn(n) {
    RoseNode::new(data=n.data * 2, children=n.children)
  })
  let rebuilt = z2.to_tree()
  inspect(rebuilt.data, content="10")
  inspect(rebuilt.children[0].data, content="10")
}

///|
test "depth tracks navigation depth" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1, children=[RoseNode::new(data=2)]),
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
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
    RoseNode::new(data=3),
  ])
  let z = RoseZipper::from_root(tree)
  inspect(z.child_index(), content="None")
  let z1 = z.go_down().unwrap()
  inspect(z1.child_index(), content="Some(0)")
  let z2 = z1.go_right().unwrap()
  inspect(z2.child_index(), content="Some(1)")
  let z3 = z2.go_right().unwrap()
  inspect(z3.child_index(), content="Some(2)")
}

///|
test "is_root and is_leaf" {
  let tree = RoseNode::new(data=0, children=[RoseNode::new(data=1)])
  let z = RoseZipper::from_root(tree)
  inspect(z.is_root(), content="true")
  inspect(z.is_leaf(), content="false")
  let z1 = z.go_down().unwrap()
  inspect(z1.is_root(), content="false")
  inspect(z1.is_leaf(), content="true")
}

///|
test "num_children" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
  ])
  let z = RoseZipper::from_root(tree)
  inspect(z.num_children(), content="2")
  let z1 = z.go_down().unwrap()
  inspect(z1.num_children(), content="0")
}

///|
test "to_path returns child indices from root" {
  let tree = RoseNode::new(data="r", children=[
    RoseNode::new(data="a", children=[
      RoseNode::new(data="x"),
      RoseNode::new(data="y"),
    ]),
    RoseNode::new(data="b"),
  ])
  let z = RoseZipper::from_root(tree)
    .go_down()
    .unwrap()
    .go_down(index=1)
    .unwrap()
  inspect(z.focus.data, content="y")
  inspect(z.to_path(), content="[0, 1]")
}

///|
test "to_path at root is empty" {
  let z = RoseZipper::from_root(RoseNode::new(data=1))
  inspect(z.to_path(), content="[]")
}

///|
test "focus_at navigates to position" {
  let tree = RoseNode::new(data="r", children=[
    RoseNode::new(data="a", children=[
      RoseNode::new(data="x"),
      RoseNode::new(data="y"),
    ]),
    RoseNode::new(data="b"),
  ])
  let z = RoseZipper::focus_at(tree, [0, 1]).unwrap()
  inspect(z.focus.data, content="y")
  inspect(z.depth(), content="2")
}

///|
test "focus_at with empty path stays at root" {
  let tree = RoseNode::new(data=1)
  let z = RoseZipper::focus_at(tree, []).unwrap()
  inspect(z.focus.data, content="1")
  inspect(z.is_root(), content="true")
}

///|
test "focus_at returns None on invalid path" {
  let tree = RoseNode::new(data=0, children=[RoseNode::new(data=1)])
  inspect(RoseZipper::focus_at(tree, [0, 5]), content="None")
  inspect(RoseZipper::focus_at(tree, [3]), content="None")
  inspect(RoseZipper::focus_at(tree, [-1]), content="None")
}

///|
test "to_path and focus_at round-trip" {
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1, children=[
      RoseNode::new(data=3),
      RoseNode::new(data=4),
    ]),
    RoseNode::new(data=2),
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
  let tree = RoseNode::new(data=0, children=[
    RoseNode::new(data=1),
    RoseNode::new(data=2),
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
  inspect(z1.child_index(), content="Some(0)")
  // z2 at sibling
  inspect(z2.focus.data, content="2")
  inspect(z2.child_index(), content="Some(1)")
}
