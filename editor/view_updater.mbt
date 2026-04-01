// ViewUpdater: Computes incremental view patches by diffing ViewNode trees.
// Lives on SyncEditor, emits Array[ViewPatch] describing what changed.

///|
pub struct ViewUpdateState {
  mut previous : @protocol.ViewNode?

  fn new() -> ViewUpdateState
} derive(Show)

///|
pub fn ViewUpdateState::new() -> ViewUpdateState {
  { previous: None }
}

///|
/// Build the full ViewNode tree from the current projection state.
pub fn[T : @proj.Renderable] SyncEditor::get_view_tree(
  self : SyncEditor[T],
) -> @protocol.ViewNode? {
  match self.get_proj_node() {
    Some(proj_node) => {
      let source_map = self.get_source_map()
      Some(@protocol.proj_to_view_node(proj_node, source_map))
    }
    None => None
  }
}

///|
/// Compute view patches by diffing previous ViewNode tree against current.
/// Updates the state's previous tree to the current tree after diffing.
pub fn[T : @proj.Renderable] compute_view_patches(
  state : ViewUpdateState,
  editor : SyncEditor[T],
) -> Array[@protocol.ViewPatch] {
  let patches : Array[@protocol.ViewPatch] = []
  let current = editor.get_view_tree()
  match (state.previous, current) {
    (None, None) =>
      // No tree before, no tree now — emit FullTree(None)
      patches.push(@protocol.ViewPatch::FullTree(root=None))
    (None, Some(curr)) =>
      // First time — emit full tree
      patches.push(@protocol.ViewPatch::FullTree(root=Some(curr)))
    (Some(_), None) =>
      // Tree was removed — emit FullTree(None)
      patches.push(@protocol.ViewPatch::FullTree(root=None))
    (Some(prev), Some(curr)) =>
      // Diff the two trees
      diff_view_nodes(prev, curr, patches)
  }
  // Emit diagnostics from current errors
  let errors = editor.get_errors()
  if errors.length() > 0 {
    let diagnostics : Array[@protocol.Diagnostic] = []
    for error in errors {
      // Errors are strings without position info — use 0..0 range
      diagnostics.push(
        @protocol.Diagnostic(from=0, to=0, severity="error", message=error),
      )
    }
    patches.push(@protocol.ViewPatch::SetDiagnostics(diagnostics~))
  } else {
    // Always emit diagnostics to clear previous ones
    patches.push(@protocol.ViewPatch::SetDiagnostics(diagnostics=[]))
  }
  // Store current tree as new previous
  state.previous = current
  patches
}

///|
/// Diff two ViewNode trees, emitting patches to transform prev into curr.
fn diff_view_nodes(
  prev : @protocol.ViewNode,
  curr : @protocol.ViewNode,
  patches : Array[@protocol.ViewPatch],
) -> Unit {
  // If kind changed, replace the whole node
  if prev.kind_tag != curr.kind_tag {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=curr.id, node=curr))
    return
  }
  // Check for property changes (label, css_class, text)
  if prev.label != curr.label ||
    prev.css_class != curr.css_class ||
    prev.text != curr.text {
    patches.push(
      @protocol.ViewPatch::UpdateNode(
        node_id=curr.id,
        label=curr.label,
        css_class=curr.css_class,
        text=curr.text,
      ),
    )
  }
  // Diff children
  let prev_len = prev.children.length()
  let curr_len = curr.children.length()
  let min_len = if prev_len < curr_len { prev_len } else { curr_len }
  // Recursively diff shared children
  for i = 0; i < min_len; i = i + 1 {
    diff_view_nodes(prev.children[i], curr.children[i], patches)
  }
  // Handle added children
  if curr_len > prev_len {
    for i = prev_len; i < curr_len; i = i + 1 {
      patches.push(
        @protocol.ViewPatch::InsertChild(
          parent_id=curr.id,
          index=i,
          child=curr.children[i],
        ),
      )
    }
  }
  // Handle removed children (remove from end to start for stable indices)
  if prev_len > curr_len {
    for i = prev_len - 1; i >= curr_len; i = i - 1 {
      patches.push(
        @protocol.ViewPatch::RemoveChild(
          parent_id=curr.id,
          index=i,
          child_id=prev.children[i].id,
        ),
      )
    }
  }
}
