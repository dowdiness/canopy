// Local duplicate of `diff_view_nodes` from `editor/view_updater.mbt:77`.
// The editor-pkg helper is private; this Markdown FFI accessor cannot import
// it. Duplicated byte-for-byte — when WS3+ migrates a second view-patch
// accessor (e.g. JSON), promote the helper to a shared package and remove
// this copy. Tracked as a §9 followup in the WS2 design spec.

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
