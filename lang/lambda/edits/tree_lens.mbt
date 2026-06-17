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
} derive(Debug)

///|
pub impl Show for TreeEditOp with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Map a language-specific TreeEditOp to the generic op type
/// that projection/TreeEditorState understands.
pub fn TreeEditOp::to_generic(self : TreeEditOp) -> @core.GenericTreeOp {
  match self {
    Select(node_id~) => Select(node_id~)
    SelectRange(start~, end~) => SelectRange(start~, end~)
    StartEdit(node_id~) => StartEdit(node_id~)
    CommitEdit(node_id~, new_value~) => CommitEdit(node_id~, new_value~)
    CancelEdit => CancelEdit
    Delete(node_id~) => Delete(node_id~)
    WrapInLambda(node_id~, ..) => StructuralEditKeepSelected(node_id~)
    WrapInApp(node_id~) => StructuralEditKeepSelected(node_id~)
    InsertChild(parent~, index~, ..) => InsertChild(parent~, index~)
    StartDrag(node_id~) => StartDrag(node_id~)
    DragOver(target~, position~) => DragOver(target~, position~)
    Drop(source~, target~, position~) => Drop(source~, target~, position~)
    Collapse(node_id~) => Collapse(node_id~)
    Expand(node_id~) => Expand(node_id~)
    Unwrap(node_id~, ..)
    | SwapChildren(node_id~)
    | WrapInIf(node_id~)
    | WrapInBop(node_id~, ..)
    | ChangeOperator(node_id~, ..)
    | ExtractToLet(node_id~, ..)
    | InlineDefinition(node_id~)
    | Rename(node_id~, ..) => StructuralEdit(node_id~)
    DeleteBinding(binding_node_id~) => StructuralEdit(node_id=binding_node_id)
    InlineAllUsages(binding_node_id~) => StructuralEdit(node_id=binding_node_id)
    DuplicateBinding(binding_node_id~) =>
      StructuralEdit(node_id=binding_node_id)
    MoveBindingUp(binding_node_id~) => StructuralEdit(node_id=binding_node_id)
    MoveBindingDown(binding_node_id~) => StructuralEdit(node_id=binding_node_id)
    AddBinding(module_node_id~) => StructuralEdit(node_id=module_node_id)
  }
}

///|
/// Map this `TreeEditOp` to an identity hint for the reparse reconciler.
///
/// `get_node` lets `Unwrap` look up the k-th child of the wrapper (needed to
/// name the kept child). Returns `Opaque` whenever the hint cannot be derived
/// (no node found, out-of-bounds child, ambiguous ops). `Opaque` degrades to
/// standard LCS reconciliation — never produces wrong identity (T3).
///
/// Note: ops that don't call `apply_span_edits` (`Select`, `Drop`, etc.) are
/// never wired to a hint push, so their return value here is unused.
pub fn TreeEditOp::to_identity_transform(
  self : TreeEditOp,
  get_node : (@core.NodeId) -> @core.ProjNode[@ast.Term]?,
) -> @core.IdentityTransform {
  match self {
    // Wrap ops: prev node becomes a child of a new wrapper.
    // ExtractToLet is excluded: it moves N to a new location (def RHS) and
    // replaces N's site with a Var reference, which is not a structural Wrap.
    // Degrading to Opaque (T3) lets LCS handle the resulting topology change.
    WrapInLambda(node_id=n, ..)
    | WrapInApp(node_id=n)
    | WrapInIf(node_id=n)
    | WrapInBop(node_id=n, ..) => @core.IdentityTransform::Wrap(inner=n)

    // Unwrap: wrapper removed, keep the k-th child's id
    Unwrap(node_id=wrapper_id, keep_child_index=k) =>
      match get_node(wrapper_id) {
        Some(wrapper) =>
          match wrapper.children.get(k) {
            Some(kept) =>
              @core.IdentityTransform::Unwrap(
                wrapper=wrapper_id,
                keep=kept.id(),
              )
            None => @core.IdentityTransform::Opaque
          }
        None => @core.IdentityTransform::Opaque
      }

    // Replacement / retirement ops: old identity retires.
    // ChangeOperator is excluded: it changes only the operator token while
    // keeping the same operand subtrees. Replace would call assign_fresh_ids on
    // the whole Bop subtree, losing both operand NodeIds. LCS (Opaque) matches
    // same-kind Bop→Bop and recurses into children, preserving operand identity.
    CommitEdit(node_id=n, ..) | InlineDefinition(node_id=n) =>
      @core.IdentityTransform::Replace(old=n)

    // Rename: leaf token changes, spine identity preserved for intra-expression
    // renames. For module-level binding renames the hint is harmlessly ignored:
    // module_key_match keys on the binding NAME and misses a renamed binding,
    // so assign_fresh_ids runs regardless (LCS fallback, no wrong IDs produced).
    Rename(node_id=n, ..) => @core.IdentityTransform::RenameLeaf(node=n)

    // All other ops: degrade to LCS (includes Delete, ExtractToLet,
    // ChangeOperator, module-level mutations, SwapChildren, AddBinding, etc.)
    _ => @core.IdentityTransform::Opaque
  }
}

///|
fn[T : Renderable] placeholder_text_for_kind(kind : T) -> String {
  T::placeholder(kind)
}

///|
fn insert_child_at(
  node : ProjNode[@ast.Term],
  index : Int,
  child : ProjNode[@ast.Term],
) -> ProjNode[@ast.Term] {
  let new_children : Array[ProjNode[@ast.Term]] = []
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
