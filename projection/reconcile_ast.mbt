// AST reconciliation: preserve ProjNode identities across reparses.

///|
/// AST reconciliation: Preserve node IDs where possible when AST changes.
pub fn reconcile_ast(
  old : ProjNode,
  new : ProjNode,
  counter : Ref[Int],
) -> ProjNode {
  match (old.kind, new.kind) {
    (Int(a), Int(b)) =>
      if a == b {
        old
      } else {
        ProjNode::new(new.kind, new.start, new.end, old.node_id, [])
      }
    (Var(a), Var(b)) =>
      if a == b {
        old
      } else {
        ProjNode::new(new.kind, new.start, new.end, old.node_id, [])
      }
    (Lam(param_old, _), Lam(param_new, _)) => {
      let _ = (param_old, param_new)
      let old_body = if old.children.length() > 0 {
        Some(old.children[0])
      } else {
        None
      }
      let new_body = if new.children.length() > 0 {
        Some(new.children[0])
      } else {
        None
      }
      let reconciled_body : Array[ProjNode] = match (old_body, new_body) {
        (Some(o), Some(n)) => [reconcile_ast(o, n, counter)]
        (None, Some(n)) => [assign_fresh_ids(n, counter)]
        (Some(_), None) => []
        (None, None) => []
      }
      let reconciled_body_kind = rebuild_kind(new.kind, reconciled_body)
      ProjNode::new(
        reconciled_body_kind,
        new.start,
        new.end,
        old.node_id,
        reconciled_body,
      )
    }
    (App(_, _), App(_, _)) => {
      let reconciled_children = reconcile_children(
        old.children,
        new.children,
        counter,
      )
      ProjNode::new(
        rebuild_kind(new.kind, reconciled_children),
        new.start,
        new.end,
        old.node_id,
        reconciled_children,
      )
    }
    (Bop(_, _, _), Bop(_, _, _)) => {
      let reconciled_children = reconcile_children(
        old.children,
        new.children,
        counter,
      )
      ProjNode::new(
        rebuild_kind(new.kind, reconciled_children),
        new.start,
        new.end,
        old.node_id,
        reconciled_children,
      )
    }
    (If(_, _, _), If(_, _, _)) => {
      let reconciled_children = reconcile_children(
        old.children,
        new.children,
        counter,
      )
      ProjNode::new(
        rebuild_kind(new.kind, reconciled_children),
        new.start,
        new.end,
        old.node_id,
        reconciled_children,
      )
    }
    (Let(_, _, _), Let(_, _, _)) => {
      let reconciled_children = reconcile_children(
        old.children,
        new.children,
        counter,
      )
      ProjNode::new(
        rebuild_kind(new.kind, reconciled_children),
        new.start,
        new.end,
        old.node_id,
        reconciled_children,
      )
    }
    _ => assign_fresh_ids(new, counter)
  }
}

///|
/// Reconcile arrays of children using LCS matching on node kinds.
fn reconcile_children(
  old_children : Array[ProjNode],
  new_children : Array[ProjNode],
  counter : Ref[Int],
) -> Array[ProjNode] {
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
      if same_kind_tag(old_children[i - 1].kind, new_children[j - 1].kind) {
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
    if same_kind_tag(old_children[i - 1].kind, new_children[j - 1].kind) {
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

  let result : Array[ProjNode] = []
  for j = 0; j < new_len; j = j + 1 {
    if new_matched[j] >= 0 {
      result.push(
        reconcile_ast(old_children[new_matched[j]], new_children[j], counter),
      )
    } else {
      result.push(assign_fresh_ids(new_children[j], counter))
    }
  }
  result
}

///|
fn assign_fresh_ids(node : ProjNode, counter : Ref[Int]) -> ProjNode {
  let new_id = next_proj_node_id(counter)
  let new_children : Array[ProjNode] = []
  for child in node.children {
    new_children.push(assign_fresh_ids(child, counter))
  }
  ProjNode::new(node.kind, node.start, node.end, new_id, new_children)
}
