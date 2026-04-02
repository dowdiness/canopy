// Pretty-printer integration for SyncEditor.
// Produces ViewNode trees from the Pretty trait, enabling syntax-highlighted
// formatted display through the ViewPatch → Adapter pipeline.

///|
/// Lambda-specific: returns the pretty-printed ViewNode tree.
/// Each line becomes a child ViewNode with text + token_spans.
pub fn SyncEditor::get_pretty_view(
  self : SyncEditor[@ast.Term],
) -> @protocol.ViewNode {
  let ast = self.get_ast()
  let layout = @pretty.Pretty::to_layout(ast)
  @protocol.layout_to_view_tree(layout, width=80)
}

///|
/// Compute incremental pretty-view patches for a lambda editor.
/// Uses a separate ViewUpdateState from the structural view.
pub fn compute_pretty_patches(
  state : ViewUpdateState,
  editor : SyncEditor[@ast.Term],
) -> Array[@protocol.ViewPatch] {
  let patches : Array[@protocol.ViewPatch] = []
  let current = editor.get_pretty_view()
  match state.previous {
    None => patches.push(@protocol.ViewPatch::FullTree(root=Some(current)))
    Some(prev) => diff_view_nodes(prev, current, patches)
  }
  state.previous = Some(current)
  patches
}
