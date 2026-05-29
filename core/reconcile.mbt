// AST reconciliation: preserve ProjNode identities across reparses.

///|
/// Generic reconciliation: Preserve node IDs where possible when AST changes.
pub fn[T : TreeNode] reconcile(
  old : ProjNode[T],
  new : ProjNode[T],
  counter : Ref[Int],
) -> ProjNode[T] {
  if T::same_kind(old.kind, new.kind) {
    let reconciled_children = reconcile_children(
      old.children,
      new.children,
      counter,
    )
    ProjNode::new(
      new.kind,
      new.start,
      new.end,
      old.node_id,
      reconciled_children,
    )
  } else {
    assign_fresh_ids(new, counter)
  }
}

///|
fn[T : TreeNode] reconcile_children(
  old_children : Array[ProjNode[T]],
  new_children : Array[ProjNode[T]],
  counter : Ref[Int],
) -> Array[ProjNode[T]] {
  let old_len = old_children.length()
  let new_len = new_children.length()
  // Each row must be a fresh array — use makei (called per row), not
  // Array::make(.., Array::make(..)) which would share one inner array
  // reference across all rows and corrupt the DP.
  let dp = Array::makei(old_len + 1, _ => Array::make(new_len + 1, 0))
  for i = 1; i <= old_len; i = i + 1 {
    for j = 1; j <= new_len; j = j + 1 {
      if T::same_kind(old_children[i - 1].kind, new_children[j - 1].kind) {
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
    if T::same_kind(old_children[i - 1].kind, new_children[j - 1].kind) {
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

  [
    for j in 0..<new_len => {
      if new_matched[j] >= 0 {
        reconcile(old_children[new_matched[j]], new_children[j], counter)
      } else {
        assign_fresh_ids(new_children[j], counter)
      }
    }
  ]
}
