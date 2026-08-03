///|
/// Detect the action context for a selected node from a SyncEditor.
/// Thin wrapper over @lambda_edits.build_action_context that extracts
/// projection data from the editor.
pub fn detect_action_context(
  editor : @editor.SyncEditor[@ast.Term],
  node_id : @core.NodeId,
) -> @lambda_edits.ActionContext? {
  let node = match editor.get_node(node_id) {
    Some(n) => n
    None => return None
  }
  guard editor.get_proj_node() is Some(proj_root) else { return None }
  let definition_index = @lambda_proj.DefinitionIndex::from_proj_node(proj_root)
  let module_node_id = match proj_root.kind {
    @ast.Term::Module(_, _) => Some(proj_root.id())
    _ => None
  }
  Some(
    @lambda_edits.build_action_context(
      node_id~,
      kind=node.kind,
      definition_index~,
      module_node_id~,
    ),
  )
}
