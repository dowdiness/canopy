// ViewUpdater: Computes incremental view patches by diffing ViewNode trees.

///|
pub struct ViewUpdateState {
  mut previous : @protocol.ViewNode?
  mut had_errors : Bool

  fn new() -> ViewUpdateState
} derive(Show)

///|
pub fn ViewUpdateState::new() -> ViewUpdateState {
  { previous: None, had_errors: false }
}

///|
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
/// Lambda-specific: returns ViewNode tree with eval annotations.
pub fn SyncEditor::get_view_tree_with_eval(
  self : SyncEditor[@ast.Term],
) -> @protocol.ViewNode? {
  match self.get_proj_node() {
    Some(proj_node) => {
      let source_map = self.get_source_map()
      let annotations = self.get_eval_annotations()
      Some(@protocol.proj_to_view_node(proj_node, source_map, annotations~))
    }
    None => None
  }
}

///|
/// Lambda-specific: compute view patches with eval annotations.
pub fn compute_view_patches_with_eval(
  state : ViewUpdateState,
  editor : SyncEditor[@ast.Term],
) -> Array[@protocol.ViewPatch] {
  let patches : Array[@protocol.ViewPatch] = []
  let current = editor.get_view_tree_with_eval()
  match (state.previous, current) {
    (None, None) => patches.push(@protocol.ViewPatch::FullTree(root=None))
    (None, Some(curr)) =>
      patches.push(@protocol.ViewPatch::FullTree(root=Some(curr)))
    (Some(_), None) => patches.push(@protocol.ViewPatch::FullTree(root=None))
    (Some(prev), Some(curr)) => diff_view_nodes(prev, curr, patches)
  }
  let errors = editor.get_errors()
  if errors.length() > 0 {
    let diagnostics : Array[@protocol.Diagnostic] = []
    for error in errors {
      diagnostics.push(
        @protocol.Diagnostic(
          from=0,
          to=0,
          severity=@protocol.SevError,
          message=error,
        ),
      )
    }
    patches.push(@protocol.ViewPatch::SetDiagnostics(diagnostics~))
    state.had_errors = true
  } else if state.had_errors {
    patches.push(@protocol.ViewPatch::SetDiagnostics(diagnostics=[]))
    state.had_errors = false
  }
  state.previous = current
  patches
}

///|
pub fn[T : @proj.Renderable] compute_view_patches(
  state : ViewUpdateState,
  editor : SyncEditor[T],
) -> Array[@protocol.ViewPatch] {
  let patches : Array[@protocol.ViewPatch] = []
  let current = editor.get_view_tree()
  match (state.previous, current) {
    (None, None) => patches.push(@protocol.ViewPatch::FullTree(root=None))
    (None, Some(curr)) =>
      patches.push(@protocol.ViewPatch::FullTree(root=Some(curr)))
    (Some(_), None) => patches.push(@protocol.ViewPatch::FullTree(root=None))
    (Some(prev), Some(curr)) => diff_view_nodes(prev, curr, patches)
  }
  let errors = editor.get_errors()
  if errors.length() > 0 {
    let diagnostics : Array[@protocol.Diagnostic] = []
    for error in errors {
      diagnostics.push(
        @protocol.Diagnostic(
          from=0,
          to=0,
          severity=@protocol.SevError,
          message=error,
        ),
      )
    }
    patches.push(@protocol.ViewPatch::SetDiagnostics(diagnostics~))
    state.had_errors = true
  } else if state.had_errors {
    patches.push(@protocol.ViewPatch::SetDiagnostics(diagnostics=[]))
    state.had_errors = false
  }
  state.previous = current
  patches
}

///|
fn diff_view_nodes(
  prev : @protocol.ViewNode,
  curr : @protocol.ViewNode,
  patches : Array[@protocol.ViewPatch],
) -> Unit {
  if prev.kind_tag != curr.kind_tag {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=curr.id, node=curr))
    return
  }
  // token_spans changes require ReplaceNode because UpdateNode doesn't carry spans
  if prev.token_spans != curr.token_spans {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=curr.id, node=curr))
    return
  }
  // annotation changes require ReplaceNode because UpdateNode doesn't carry annotations
  if prev.annotations != curr.annotations {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=curr.id, node=curr))
    return
  }
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
  let prev_len = prev.children.length()
  let curr_len = curr.children.length()
  let min_len = if prev_len < curr_len { prev_len } else { curr_len }
  for i = 0; i < min_len; i = i + 1 {
    diff_view_nodes(prev.children[i], curr.children[i], patches)
  }
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
  // Remove from end to start for stable indices
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
