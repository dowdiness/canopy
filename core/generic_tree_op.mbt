// Generic tree operations for the interactive tree editor.
// Language-agnostic: projection/ uses this instead of language-specific op types.

///|
/// UI-level tree operations that projection/TreeEditorState understands.
/// Language packages map their domain-specific ops to this type via to_generic().
pub(all) enum GenericTreeOp {
  // Selection
  Select(node_id~ : NodeId)
  SelectRange(start~ : NodeId, end~ : NodeId)

  // Inline editing
  StartEdit(node_id~ : NodeId)
  CommitEdit(node_id~ : NodeId, new_value~ : String)
  CancelEdit

  // Structural (generic)
  Delete(node_id~ : NodeId)
  StructuralEdit(node_id~ : NodeId)
  StructuralEditKeepSelected(node_id~ : NodeId)
  InsertChild(parent~ : NodeId, index~ : Int)

  // Drag and drop
  StartDrag(node_id~ : NodeId)
  DragOver(target~ : NodeId, position~ : DropPosition)
  Drop(source~ : NodeId, target~ : NodeId, position~ : DropPosition)

  // Navigation
  Collapse(node_id~ : NodeId)
  Expand(node_id~ : NodeId)
} derive(Debug)

///|
pub impl Show for GenericTreeOp with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}
