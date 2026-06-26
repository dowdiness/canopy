// ProjNode[T]: Generic projection node parameterized by AST type T.
// Preserves node IDs and positions needed for projectional editing.

///|
/// Generic projection node parameterized by AST type T.
/// `kind : T` holds the AST node, `children : Array[ProjNode[T]]` holds child projections.
/// `start` and `end` are UTF-16 code-unit source offsets, interpreted as a
/// half-open range `[start, end)`. They are not eg-walker item-space positions
/// and not ProseMirror tree positions.
pub struct ProjNode[T] {
  node_id : Int
  kind : T
  children : Array[ProjNode[T]]
  start : Int
  end : Int
} derive(Debug, Eq)

///|
/// Non-recursive carrier for the `fold` algebra: the scalar fields of a
/// ProjNode without the `children` array. By passing this instead of
/// `ProjNode[T]`, the algebra cannot bypass the fold by accessing the
/// original recursive structure.
pub struct FoldNode[T] {
  kind : T
  node_id : Int
  start : Int
  end : Int
} derive(Debug, Eq)

///|
fn[T] FoldNode::FoldNode(
  kind : T,
  node_id : Int,
  start : Int,
  end : Int,
) -> FoldNode[T] {
  { kind, node_id, start, end }
}

///|
pub fn[T] FoldNode::id(self : FoldNode[T]) -> NodeId {
  NodeId(self.node_id)
}

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
pub fn[T] ProjNode::ProjNode(
  kind : T,
  start : Int,
  end : Int,
  node_id : Int,
  children : Array[ProjNode[T]],
) -> ProjNode[T] {
  { node_id, kind, children, start, end }
}

///|
pub fn[T, U] ProjNode::map(
  self : ProjNode[T],
  f : (T) -> U raise?,
) -> ProjNode[U] raise? {
  ProjNode(
    f(self.kind),
    self.start,
    self.end,
    self.node_id,
    self.children.map(child => child.map(f)),
  )
}

///|
/// Construct a childless ProjNode spanning a syntax node, assigning a fresh id.
/// Projection builders should prefer this for syntax leaves instead of manually
/// pairing `next_proj_node_id` with `ProjNode(...)` at each call site.
pub fn[T] ProjNode::leaf(
  kind : T,
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[T] {
  ProjNode(kind, node.start(), node.end(), next_proj_node_id(counter), [])
}

///|
/// Construct a ProjNode with explicit UTF-16 source span and children,
/// assigning a fresh id. Use this for projection branches whose identity is
/// fresh for this build; call `ProjNode(...)` directly when preserving or
/// reusing a known node id.
pub fn[T] ProjNode::branch(
  kind : T,
  start : Int,
  end : Int,
  children : Array[ProjNode[T]],
  counter : Ref[Int],
) -> ProjNode[T] {
  ProjNode(kind, start, end, next_proj_node_id(counter), children)
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
/// Bottom-up fold (catamorphism) over a ProjNode tree.
///
/// Rebuilds or aggregates the tree: `f` receives a `FoldNode[T]` — the
/// scalar fields of the current node (`kind`, `start`, `end`, `node_id`)
/// — combined with the already-folded results of its children. Since
/// `FoldNode[T]` has no `children` field, the algebra cannot bypass the
/// fold by recursing manually.
///
/// **What fold is for:** aggregate/rebuild operations where the result
/// for a node depends on the results of its children — counting, summing,
/// renaming, collecting text, reconstructing with modified fields.
///
/// **What fold is not for:** searches that short-circuit (use
/// `get_node_in_tree`), lookups that need the full `ProjNode` value
/// (use `collect_registry`), or traversals where insertion order matters.
///
/// Uses an explicit stack for stack safety on deep trees.
pub fn[T, U] ProjNode::fold(
  self : ProjNode[T],
  f : (FoldNode[T], Array[U]) -> U,
) -> U {
  // Post-order iterative fold. Each frame tracks (node, children_processed_count).
  let stack : Array[(ProjNode[T], Int)] = [(self, 0)]
  let results : Array[U] = []

  while stack.length() > 0 {
    let (node, done) = stack[stack.length() - 1]
    if done < node.children.length() {
      // Advance the frame counter and push the next child
      let top = stack.length() - 1
      stack[top] = (node, done + 1)
      stack.push((node.children[done], 0))
    } else {
      // All children processed — fold this node
      let _ = stack.pop()
      let n = node.children.length()
      let child_results : Array[U] = []
      for i in 0..<n {
        child_results.push(results[results.length() - n + i])
      }
      for _ in 0..<n {
        let _ = results.pop()
      }
      results.push(
        f(
          FoldNode(node.kind, node.node_id, node.start, node.end),
          child_results,
        ),
      )
    }
  }

  results[0]
}

///|
/// Build a NodeId → ProjNode lookup by walking the tree (pre-order).
/// Pre-order traversal ensures parent is inserted before children,
/// matching the original recursive implementation.
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
/// Uses early-exit recursion (short-circuits on first match) — fold is not
/// appropriate for search since it must visit every node.
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
  node.fold((n, children) => {
    ProjNode::branch(n.kind, n.start, n.end, children, counter)
  })
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
