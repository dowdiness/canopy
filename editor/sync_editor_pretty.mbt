// Pretty-printer integration for SyncEditor.
// Produces ViewNode trees from the Pretty trait, enabling syntax-highlighted
// formatted display through the ViewPatch → Adapter pipeline.

///|
/// Returns the pretty-printed ViewNode tree.
/// If capabilities.pretty_post_process is set, it post-processes the layout
/// (e.g. to inject eval annotations).
pub fn[T : @pretty.Pretty] SyncEditor::get_pretty_view(
  self : SyncEditor[T],
) -> @protocol.ViewNode {
  let tree = match self.get_tree() {
    Some(t) => t
    None => return @protocol.layout_to_view_tree(@pretty.text(""), width=80)
  }
  let layout = @pretty.Pretty::to_layout(tree)
  let final_layout = match self.capabilities.pretty_post_process {
    Some(post) => post(layout)
    None => layout
  }
  @protocol.layout_to_view_tree(final_layout, width=80)
}

///|
/// Compute incremental pretty-view patches.
/// Uses a separate ViewUpdateState from the structural view.
pub fn[T : @pretty.Pretty] compute_pretty_patches(
  state : ViewUpdateState,
  editor : SyncEditor[T],
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
