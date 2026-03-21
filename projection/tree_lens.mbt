// Tree editing operations over pure ProjNode trees.

///|
/// Tree edit operations for the interactive tree editor
pub(all) enum TreeEditOp {
  // Selection
  Select(node_id~ : NodeId)
  SelectRange(start~ : NodeId, end~ : NodeId)

  // Inline editing
  StartEdit(node_id~ : NodeId)
  CommitEdit(node_id~ : NodeId, new_value~ : String)
  CancelEdit

  // Structural operations
  Delete(node_id~ : NodeId)
  WrapInLambda(node_id~ : NodeId, var_name~ : String)
  WrapInApp(node_id~ : NodeId)
  InsertChild(parent~ : NodeId, index~ : Int, kind~ : @ast.Term)

  // Drag and drop
  StartDrag(node_id~ : NodeId)
  DragOver(target~ : NodeId, position~ : DropPosition)
  Drop(source~ : NodeId, target~ : NodeId, position~ : DropPosition)

  // Navigation
  Collapse(node_id~ : NodeId)
  Expand(node_id~ : NodeId)

  // New structural actions
  Unwrap(node_id~ : NodeId, keep_child_index~ : Int)
  SwapChildren(node_id~ : NodeId)
  WrapInIf(node_id~ : NodeId)
  WrapInBop(node_id~ : NodeId, op~ : @ast.Bop)
  ChangeOperator(node_id~ : NodeId, new_op~ : @ast.Bop)

  // Module-level binding actions
  DeleteBinding(binding_node_id~ : NodeId)
  DuplicateBinding(binding_node_id~ : NodeId)
  MoveBindingUp(binding_node_id~ : NodeId)
  MoveBindingDown(binding_node_id~ : NodeId)
  AddBinding(module_node_id~ : NodeId)

  // Extract to let
  ExtractToLet(node_id~ : NodeId, var_name~ : String)

  // Inline
  InlineDefinition(node_id~ : NodeId)
  InlineAllUsages(binding_node_id~ : NodeId)

  // Rename
  Rename(node_id~ : NodeId, new_name~ : String)
} derive(Show)

///|
fn placeholder_text_for_kind(kind : @ast.Term) -> String {
  match kind {
    @ast.Term::Int(_) => "0"
    @ast.Term::Var(_) => "a"
    @ast.Term::Lam(_, _) => "λx.x"
    @ast.Term::App(_, _) => "f x"
    @ast.Term::Bop(_, _, _) => "0 + 0"
    @ast.Term::If(_, _, _) => "if 0 then 0 else 0"
    @ast.Term::Module(_, _) => "let x = 0\nx"
    @ast.Term::Unit => "()"
    @ast.Term::Unbound(_) => "a"
    @ast.Term::Error(_) => "a"
  }
}

///|
fn insert_child_at(node : ProjNode, index : Int, child : ProjNode) -> ProjNode {
  let new_children : Array[ProjNode] = []
  for i, c in node.children {
    if i == index {
      new_children.push(child)
    }
    new_children.push(c)
  }
  if index >= node.children.length() {
    new_children.push(child)
  }
  ProjNode::new(
    rebuild_kind(node.kind, new_children),
    node.start,
    node.end,
    node.node_id,
    new_children,
  )
}

///|
fn get_node_in_tree(root : ProjNode, target_id : NodeId) -> ProjNode? {
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
