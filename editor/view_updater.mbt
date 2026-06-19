// ViewUpdater: Computes incremental view patches by diffing ViewNode trees.

///|
pub struct ViewUpdateState {
  mut previous : @protocol.ViewNode?
  mut previous_decorations : Array[@protocol.Decoration]?
  mut had_errors : Bool
} derive(Debug)

///|
pub fn ViewUpdateState::ViewUpdateState() -> ViewUpdateState {
  { previous: None, previous_decorations: None, had_errors: false }
}

///|
pub fn ViewUpdateState::set_previous(
  self : ViewUpdateState,
  value : @protocol.ViewNode?,
) -> Unit {
  self.previous = value
}

///|
pub fn ViewUpdateState::set_had_errors(
  self : ViewUpdateState,
  value : Bool,
) -> Unit {
  self.had_errors = value
}

///|
pub fn[T : @loom_core.Renderable] SyncEditor::get_view_tree(
  self : SyncEditor[T],
) -> @protocol.ViewNode? {
  match self.get_proj_node() {
    Some(proj_node) => {
      let source_map = self.get_source_map()
      let source_text = Some(self.get_text())
      let annotations = match self.capabilities.get_annotations {
        Some(get_ann) => get_ann()
        None => {}
      }
      match self.capabilities.to_view_node {
        Some(convert) =>
          Some(convert(proj_node, source_map, annotations, source_text))
        None =>
          Some(
            @protocol.proj_to_view_node(
              proj_node,
              source_map,
              source_text~,
              annotations~,
            ),
          )
      }
    }
    None => None
  }
}

///|
pub fn[T : @loom_core.Renderable] compute_view_patches(
  state : ViewUpdateState,
  editor : SyncEditor[T],
) -> Array[@protocol.ViewPatch] {
  let patches : Array[@protocol.ViewPatch] = []
  let current = editor.get_view_tree()
  let current_decorations = match editor.capabilities.get_decorations {
    Some(get_decos) => get_decos()
    None => []
  }
  match (state.previous, current) {
    (None, None) => patches.push(@protocol.ViewPatch::FullTree(root=None))
    (None, Some(curr)) =>
      patches.push(@protocol.ViewPatch::FullTree(root=Some(curr)))
    (Some(_), None) => patches.push(@protocol.ViewPatch::FullTree(root=None))
    (Some(prev), Some(curr)) => diff_view_nodes(prev, curr, patches)
  }
  match state.previous_decorations {
    Some(prev) if prev == current_decorations => ()
    _ =>
      if !current_decorations.is_empty() ||
        state.previous_decorations is Some(_) {
        patches.push(
          @protocol.ViewPatch::SetDecorations(decorations=current_decorations),
        )
      }
  }
  state.previous_decorations = Some(current_decorations)
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
  // If node identity changed at this position (e.g., a new block was inserted
  // shifting siblings), emit ReplaceNode so the frontend gets the correct ID.
  if prev.id != curr.id {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=prev.id, node=curr))
    return
  }
  if prev.kind_tag != curr.kind_tag {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=prev.id, node=curr))
    return
  }
  // token_spans changes require ReplaceNode because UpdateNode doesn't carry spans
  if prev.token_spans != curr.token_spans {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=prev.id, node=curr))
    return
  }
  // annotation changes require ReplaceNode because UpdateNode doesn't carry annotations
  if prev.annotations != curr.annotations {
    patches.push(@protocol.ViewPatch::ReplaceNode(node_id=prev.id, node=curr))
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
  for i in 0..<min_len {
    diff_view_nodes(prev.children[i], curr.children[i], patches)
  }
  if curr_len > prev_len {
    for i in prev_len..<curr_len {
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
