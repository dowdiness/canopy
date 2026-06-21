///| Markdown-specific reconciliation for explicit block-move provenance.

///|
/// Generic `@core.reconcile_hinted` intentionally treats `Move` as
/// editor-owned and freshens the node at the old position. Markdown block moves
/// are source-text edits, so this package consumes `IdentityTransform::Move`
/// only when an explicit structural edit supplied it and the moved block has a
/// unique exact sibling match after reparsing.

///|
fn build_markdown_hints_map(
  hints : Array[@core.IdentityTransform],
) -> Map[@core.NodeId, @core.IdentityTransform] {
  let result : Map[@core.NodeId, @core.IdentityTransform] = {}
  for hint in hints {
    match hint {
      @core.IdentityTransform::Opaque => return {}
      @core.IdentityTransform::Wrap(inner=id) => result[id] = hint
      @core.IdentityTransform::Unwrap(wrapper=id, ..) => result[id] = hint
      @core.IdentityTransform::Move(subtree=id) => result[id] = hint
      @core.IdentityTransform::Replace(old=id) => result[id] = hint
      @core.IdentityTransform::RenameLeaf(node=id) => result[id] = hint
      @core.IdentityTransform::InsertSubtree(parent=id, ..) => result[id] = hint
      @core.IdentityTransform::DeleteSubtree(node=id) => result[id] = hint
    }
  }
  result
}

///|
fn reconcile_markdown_projection_hinted(
  old : @core.ProjNode[@markdown.Block],
  new_ : @core.ProjNode[@markdown.Block],
  counter : Ref[Int],
  hints : Map[@core.NodeId, @core.IdentityTransform],
) -> @core.ProjNode[@markdown.Block] {
  if hints.is_empty() || !has_move_hint(hints) {
    return @core.reconcile_hinted(old, new_, counter, hints)
  }
  if @loomcore.TreeNode::same_kind(old.kind, new_.kind) &&
    is_block_container(new_.kind) {
    return @core.ProjNode::new(
      new_.kind,
      new_.start,
      new_.end,
      old.node_id,
      reconcile_markdown_children_hinted(
        old.children,
        new_.children,
        counter,
        hints,
      ),
    )
  }
  @core.reconcile_hinted(old, new_, counter, hints)
}

///|
fn has_move_hint(hints : Map[@core.NodeId, @core.IdentityTransform]) -> Bool {
  hints.values().any(hint => hint is @core.IdentityTransform::Move(_))
}

///|
fn is_block_container(block : @markdown.Block) -> Bool {
  block is Document(_) ||
  block is UnorderedList(_) ||
  block is OrderedList(_, _)
}

///|
fn reconcile_markdown_children_hinted(
  old_children : Array[@core.ProjNode[@markdown.Block]],
  new_children : Array[@core.ProjNode[@markdown.Block]],
  counter : Ref[Int],
  hints : Map[@core.NodeId, @core.IdentityTransform],
) -> Array[@core.ProjNode[@markdown.Block]] {
  let old_len = old_children.length()
  let new_len = new_children.length()
  let excluded_old = Array::makei(old_len, i => {
    is_move_source(hints, old_children[i].id())
  })
  let exact_match = (oi, nj) => {
    markdown_child_match(old_children[oi].kind, new_children[nj].kind) &&
    !excluded_old[oi]
  }
  // Dynamic-programming table and backtracking arrays are algorithm state for
  // occurrence-stable LCS. Mutation is local to the matcher and mirrors
  // `@core.reconcile_children`.
  let dp = Array::makei(old_len + 1, _ => Array::make(new_len + 1, 0))
  for i = 1; i <= old_len; i = i + 1 {
    for j = 1; j <= new_len; j = j + 1 {
      if exact_match(i - 1, j - 1) {
        dp[i][j] = dp[i - 1][j - 1] + 1
      } else {
        dp[i][j] = @cmp.maximum(dp[i - 1][j], dp[i][j - 1])
      }
    }
  }
  let old_matched = Array::make(old_len, -1)
  let new_matched = Array::make(new_len, -1)
  let mut i = old_len
  let mut j = new_len
  while i > 0 && j > 0 {
    if exact_match(i - 1, j - 1) {
      old_matched[i - 1] = j - 1
      new_matched[j - 1] = i - 1
      i = i - 1
      j = j - 1
    } else if dp[i - 1][j] >= dp[i][j - 1] {
      i = i - 1
    } else {
      j = j - 1
    }
  }
  // Consumption marker: a previous moved node may be paired at most once.
  let consumed : Map[@core.NodeId, Bool] = {}
  let old_pair_counts = markdown_move_pair_counts(
    old_children, new_children, old_matched, new_matched, hints,
  )
  [
    for k in 0..<new_len => {
      if new_matched[k] >= 0 {
        reconcile_markdown_projection_hinted(
          old_children[new_matched[k]],
          new_children[k],
          counter,
          hints,
        )
      } else {
        match
          markdown_move_pair(
            new_children[k],
            old_children,
            old_matched,
            old_pair_counts,
            consumed,
            counter,
            hints,
          ) {
          Some(node) => node
          None => @core.assign_fresh_ids(new_children[k], counter)
        }
      }
    }
  ]
}

///|
fn markdown_child_match(old : @markdown.Block, new_ : @markdown.Block) -> Bool {
  match (old, new_) {
    (OrderedListItem(old_inlines, _), OrderedListItem(new_inlines, _)) =>
      old_inlines == new_inlines
    _ if is_block_container(old) || is_block_container(new_) =>
      @loomcore.TreeNode::same_kind(old, new_)
    _ => old == new_
  }
}

///|
fn is_move_source(
  hints : Map[@core.NodeId, @core.IdentityTransform],
  id : @core.NodeId,
) -> Bool {
  hints.get(id) is Some(@core.IdentityTransform::Move(_))
}

///|
fn markdown_move_pair_counts(
  old_children : Array[@core.ProjNode[@markdown.Block]],
  new_children : Array[@core.ProjNode[@markdown.Block]],
  old_matched : Array[Int],
  new_matched : Array[Int],
  hints : Map[@core.NodeId, @core.IdentityTransform],
) -> Map[@core.NodeId, Int] {
  let counts : Map[@core.NodeId, Int] = {}
  for oi, old_child in old_children {
    if old_matched[oi] < 0 && is_move_source(hints, old_child.id()) {
      let count = [
        for ni, new_child in new_children if new_matched[ni] < 0 &&
        markdown_child_match(old_child.kind, new_child.kind) => new_child
      ].length()
      if count > 0 {
        counts[old_child.id()] = count
      }
    }
  }
  counts
}

///|
fn markdown_move_pair(
  new_child : @core.ProjNode[@markdown.Block],
  old_children : Array[@core.ProjNode[@markdown.Block]],
  old_matched : Array[Int],
  old_pair_counts : Map[@core.NodeId, Int],
  consumed : Map[@core.NodeId, Bool],
  counter : Ref[Int],
  hints : Map[@core.NodeId, @core.IdentityTransform],
) -> @core.ProjNode[@markdown.Block]? {
  let candidates = [
    for idx, old_child in old_children if old_matched[idx] < 0 &&
    consumed.get(old_child.id()) is None &&
    old_pair_counts.get(old_child.id()) is Some(1) &&
    is_move_source(hints, old_child.id()) &&
    markdown_child_match(old_child.kind, new_child.kind) => old_child
  ]
  match candidates {
    [old_child] => {
      consumed[old_child.id()] = true
      Some(
        @core.ProjNode::new(
          new_child.kind,
          new_child.start,
          new_child.end,
          old_child.node_id,
          reconcile_markdown_children_hinted(
            old_child.children,
            new_child.children,
            counter,
            hints,
          ),
        ),
      )
    }
    _ => None
  }
}
