// AST reconciliation: preserve ProjNode identities across reparses.

///|
using @loomcore {trait TreeNode}

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
  let dp : Array[Array[Int]] = []
  for i = 0; i <= old_len; i = i + 1 {
    let row : Array[Int] = []
    for j = 0; j <= new_len; j = j + 1 {
      row.push(0)
    }
    dp.push(row)
  }
  for i = 1; i <= old_len; i = i + 1 {
    for j = 1; j <= new_len; j = j + 1 {
      if T::same_kind(old_children[i - 1].kind, new_children[j - 1].kind) {
        dp[i][j] = dp[i - 1][j - 1] + 1
      } else {
        dp[i][j] = @cmp.maximum(dp[i - 1][j], dp[i][j - 1])
      }
    }
  }

  let old_matched : Array[Int] = []
  let new_matched : Array[Int] = []
  for i = 0; i < old_len; i = i + 1 {
    old_matched.push(-1)
  }
  for j = 0; j < new_len; j = j + 1 {
    new_matched.push(-1)
  }
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

  let result : Array[ProjNode[T]] = []
  for j = 0; j < new_len; j = j + 1 {
    if new_matched[j] >= 0 {
      result.push(
        reconcile(old_children[new_matched[j]], new_children[j], counter),
      )
    } else {
      result.push(assign_fresh_ids(new_children[j], counter))
    }
  }
  result
}
