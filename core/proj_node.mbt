// ProjNode[T]: Generic projection node parameterized by AST type T.
// Preserves node IDs and positions needed for projectional editing.

///|
/// Generic projection node parameterized by AST type T.
/// `kind : T` holds the AST node, `children : Array[ProjNode[T]]` holds child projections.
pub struct ProjNode[T] {
  node_id : Int
  kind : T
  children : Array[ProjNode[T]]
  start : Int
  end : Int
} derive(Debug, Eq)

///|
/// Short structural label for inspector + debug traces:
/// `"#<node_id> <kind_tag> [<start>..<end>]"`. Depth-1 only — children
/// are not recursed. The kind tag comes from `Renderable::kind_tag` so
/// it stays a short variant name regardless of how `T` chooses to
/// implement its own `Show`. See docs/plans/2026-05-16-show-unification.md.
pub impl[T : @loomcore.Renderable] Show for ProjNode[T] with fn output(
  self,
  logger,
) {
  let tag = @loomcore.Renderable::kind_tag(self.kind)
  logger.write_string(
    "\{self.id().short()} \{tag} [\{self.start}..\{self.end}]",
  )
}

///|
pub fn[T] ProjNode::new(
  kind : T,
  start : Int,
  end : Int,
  node_id : Int,
  children : Array[ProjNode[T]],
) -> ProjNode[T] {
  { node_id, kind, children, start, end }
}

///|
pub fn[T] ProjNode::id(self : ProjNode[T]) -> NodeId {
  NodeId(self.node_id)
}

///|
/// Allocate a fresh projection node ID from a shared counter.
/// Public for cross-package use by language-specific projection builders.
pub fn next_proj_node_id(counter : Ref[Int]) -> Int {
  let id = counter.val
  counter.val = counter.val + 1
  id
}

///|
/// Build a NodeId → ProjNode lookup by walking the tree.
pub fn[T] collect_registry(
  node : ProjNode[T],
  reg : Map[NodeId, ProjNode[T]],
) -> Unit {
  reg[node.id()] = node
  for child in node.children {
    collect_registry(child, reg)
  }
}

///|
/// Find a node in a ProjNode tree by its NodeId.
pub fn[T] get_node_in_tree(
  root : ProjNode[T],
  target_id : NodeId,
) -> ProjNode[T]? {
  if root.id() == target_id {
    Some(root)
  } else {
    for child in root.children {
      match get_node_in_tree(child, target_id) {
        Some(found) => return Some(found)
        None => continue
      }
    }
    None
  }
}

///|
/// Assign fresh IDs to a ProjNode subtree (post-order: children before parent).
/// Public for cross-package use by reconciliation.
pub fn[T] assign_fresh_ids(
  node : ProjNode[T],
  counter : Ref[Int],
) -> ProjNode[T] {
  let new_children : Array[ProjNode[T]] = [
    for child in node.children => assign_fresh_ids(child, counter)
  ]
  let new_id = next_proj_node_id(counter)
  ProjNode::new(node.kind, node.start, node.end, new_id, new_children)
}

///|
pub impl[T : ToJson] ToJson for ProjNode[T] with fn to_json(self) {
  let children_json : Array[Json] = self.children.map(c => c.to_json())
  {
    "node_id": self.node_id,
    "kind": self.kind.to_json(),
    "children": children_json,
    "start": self.start,
    "end": self.end,
  }
}
