// Whitebox tests for ProjNode tree navigation (proj_zipper.mbt).

// Helper: build a ProjNode[Int] tree with predictable NodeIds.
// The Int payload is the same as the node_id for simplicity.

///|
fn make_node(id : Int, children : Array[ProjNode[Int]]) -> ProjNode[Int] {
  ProjNode::new(id, 0, 0, id, children)
}

// Test tree:
//       0
//      / \
//     1   2
//    /|   |
//   3 4   5

///|
fn test_tree() -> ProjNode[Int] {
  make_node(0, [
    make_node(1, [make_node(3, []), make_node(4, [])]),
    make_node(2, [make_node(5, [])]),
  ])
}

// --- find_path_to ---

///|
test "find_path_to: root" {
  let tree = test_tree()
  inspect(find_path_to(tree, NodeId(0)), content="Some([])")
}

///|
test "find_path_to: first child" {
  let tree = test_tree()
  inspect(find_path_to(tree, NodeId(1)), content="Some([0])")
}

///|
test "find_path_to: second child" {
  let tree = test_tree()
  inspect(find_path_to(tree, NodeId(2)), content="Some([1])")
}

///|
test "find_path_to: grandchild" {
  let tree = test_tree()
  inspect(find_path_to(tree, NodeId(4)), content="Some([0, 1])")
}

///|
test "find_path_to: not found" {
  let tree = test_tree()
  inspect(find_path_to(tree, NodeId(99)), content="None")
}

// --- navigate_proj: Up ---

///|
test "navigate Up from root returns None" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(0), Up, tree), content="None")
}

///|
test "navigate Up from child returns parent" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(1), Up, tree), content="Some(NodeId(0))")
}

///|
test "navigate Up from grandchild returns parent" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(4), Up, tree), content="Some(NodeId(1))")
}

///|
test "navigate Up from deep node" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(5), Up, tree), content="Some(NodeId(2))")
}

// --- navigate_proj: Down ---

///|
test "navigate Down from root goes to first child" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(0), Down, tree), content="Some(NodeId(1))")
}

///|
test "navigate Down from internal node" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(2), Down, tree), content="Some(NodeId(5))")
}

///|
test "navigate Down from leaf returns None" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(3), Down, tree), content="None")
}

///|
test "navigate Down from leaf (right subtree)" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(5), Down, tree), content="None")
}

// --- navigate_proj: Left ---

///|
test "navigate Left from first sibling returns None" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(1), Left, tree), content="None")
}

///|
test "navigate Left from second sibling returns first" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(2), Left, tree), content="Some(NodeId(1))")
}

///|
test "navigate Left among grandchildren" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(4), Left, tree), content="Some(NodeId(3))")
}

///|
test "navigate Left from root returns None" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(0), Left, tree), content="None")
}

// --- navigate_proj: Right ---

///|
test "navigate Right from first sibling returns second" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(1), Right, tree), content="Some(NodeId(2))")
}

///|
test "navigate Right from last sibling returns None" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(2), Right, tree), content="None")
}

///|
test "navigate Right among grandchildren" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(3), Right, tree), content="Some(NodeId(4))")
}

///|
test "navigate Right from root returns None" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(0), Right, tree), content="None")
}

// --- navigate_proj: missing cursor ---

///|
test "navigate with unknown cursor returns None" {
  let tree = test_tree()
  inspect(navigate_proj(NodeId(99), Down, tree), content="None")
}

// --- navigate_proj: single-node tree ---

///|
test "single node: all directions return None" {
  let tree = make_node(0, [])
  inspect(navigate_proj(NodeId(0), Up, tree), content="None")
  inspect(navigate_proj(NodeId(0), Down, tree), content="None")
  inspect(navigate_proj(NodeId(0), Left, tree), content="None")
  inspect(navigate_proj(NodeId(0), Right, tree), content="None")
}

// --- navigate_proj: wide tree (many siblings) ---

///|
test "wide tree: navigate Left/Right across 4 siblings" {
  let tree = make_node(0, [
    make_node(1, []),
    make_node(2, []),
    make_node(3, []),
    make_node(4, []),
  ])
  inspect(navigate_proj(NodeId(1), Right, tree), content="Some(NodeId(2))")
  inspect(navigate_proj(NodeId(2), Right, tree), content="Some(NodeId(3))")
  inspect(navigate_proj(NodeId(3), Right, tree), content="Some(NodeId(4))")
  inspect(navigate_proj(NodeId(4), Right, tree), content="None")
  inspect(navigate_proj(NodeId(4), Left, tree), content="Some(NodeId(3))")
  inspect(navigate_proj(NodeId(1), Left, tree), content="None")
}
