// AST reconciliation: preserve ProjNode identities across reparses.

///|
/// Generic reconciliation: Preserve node IDs where possible when AST changes.
pub fn[T : TreeNode] reconcile(
  old : ProjNode[T],
  new : ProjNode[T],
  counter : Ref[Int],
) -> ProjNode[T] {
  reconcile_hinted(old, new, counter, {})
}

///|
/// Reconciliation with structural-edit hints. Behaves identically to `reconcile`
/// when `hints` is empty. A `Wrap` / `Unwrap` hint (keyed by the previous node's
/// id) lets identity survive a constructor change at a position that positional
/// LCS reconciliation alone would lose — see
/// docs/architecture/grove-and-structural-identity.md.
pub fn[T : TreeNode] reconcile_hinted(
  old : ProjNode[T],
  new : ProjNode[T],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
) -> ProjNode[T] {
  // A structural hint keyed by `old.id()` (wrap / unwrap) takes precedence and
  // may apply even when the new wrapper is the SAME kind as the wrapped node —
  // e.g. wrapping an `App` inside another `App`. Checked before the same-kind
  // branch so identity lands on the wrapped node, not the new wrapper. Skipped
  // entirely when there are no hints, keeping the per-keystroke path free of
  // extra lookups.
  let hinted = if hints.is_empty() {
    None
  } else {
    structural_pair(old, new, counter, hints)
  }
  match hinted {
    Some(node) => node
    None =>
      if T::same_kind(old.kind, new.kind) {
        let reconciled_children = reconcile_children(
          old.children,
          new.children,
          counter,
          hints,
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
}

///|
fn[T : TreeNode] reconcile_children(
  old_children : Array[ProjNode[T]],
  new_children : Array[ProjNode[T]],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
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

  // Injectivity ledger for hint-based pairing of LCS-unmatched children
  // (a consumed prev-id is paired at most once). Mutation justified as a
  // consumption marker (moonbit-base.md Control Flow).
  let consumed : Map[NodeId, Bool] = {}
  [
    for k in 0..<new_len => {
      if new_matched[k] >= 0 {
        reconcile_hinted(
          old_children[new_matched[k]],
          new_children[k],
          counter,
          hints,
        )
      } else if hints.is_empty() {
        assign_fresh_ids(new_children[k], counter)
      } else {
        match
          try_unmatched_hint_pair(
            new_children[k],
            old_children,
            old_matched,
            consumed,
            counter,
            hints,
          ) {
          Some(node) => node
          None => assign_fresh_ids(new_children[k], counter)
        }
      }
    }
  ]
}

///|
/// Apply a structural hint keyed by `old.id()` to carry identity across a
/// constructor change. Returns `None` when no hint applies or the prev subtree
/// cannot be located unambiguously in `new` (degrade to fresh ids — invariant T3).
fn[T : TreeNode] structural_pair(
  old : ProjNode[T],
  new : ProjNode[T],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
) -> ProjNode[T]? {
  match hints.get(old.id()) {
    Some(Wrap(_)) => apply_wrap(old, new, counter, hints)
    Some(Unwrap(keep~, ..)) => apply_unwrap(old, new, counter, hints, keep)
    _ => None
  }
}

///|
/// For an LCS-unmatched `new_child`, find a still-unmatched, unconsumed prev
/// child whose `Wrap`/`Unwrap` hint pairs with it, and carry identity.
fn[T : TreeNode] try_unmatched_hint_pair(
  new_child : ProjNode[T],
  old_children : Array[ProjNode[T]],
  old_matched : Array[Int],
  consumed : Map[NodeId, Bool],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
) -> ProjNode[T]? {
  let candidates = [
    for idx, o in old_children if old_matched[idx] < 0 &&
    consumed.get(o.id()) is None &&
    hint_pairs(o, new_child, hints) => o
  ]
  // Carry identity only for an unambiguous singleton candidate; 0 or >1
  // candidates (multiple old siblings claiming the same new child) degrade to
  // fresh ids rather than assigning identity by sibling iteration order.
  match candidates {
    [o] => {
      consumed[o.id()] = true
      structural_pair(o, new_child, counter, hints)
    }
    _ => None
  }
}

///|
/// Pure predicate: does `old`'s hint pair with `new_child` (without side effects)?
fn[T : TreeNode] hint_pairs(
  old : ProjNode[T],
  new_child : ProjNode[T],
  hints : Map[NodeId, IdentityTransform],
) -> Bool {
  match hints.get(old.id()) {
    Some(Wrap(_)) => count_same_kind_children(new_child, old) == 1
    Some(Unwrap(keep~, ..)) =>
      match find_child(old, keep) {
        Some(k) => T::same_kind(new_child.kind, k.kind)
        None => false
      }
    _ => false
  }
}

///|
/// Wrap: `wrapper` introduces a level over the prev subtree `old`. Carry `old`'s
/// identity into the unique same-kind child; the wrapper itself is fresh.
fn[T : TreeNode] apply_wrap(
  old : ProjNode[T],
  wrapper : ProjNode[T],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
) -> ProjNode[T]? {
  let targets = [
    for idx, c in wrapper.children if T::same_kind(c.kind, old.kind) => idx
  ]
  match targets {
    [target] => {
      let new_children = [
        for idx, c in wrapper.children => {
          if idx == target {
            reconcile_hinted(old, c, counter, hints)
          } else {
            assign_fresh_ids(c, counter)
          }
        }
      ]
      Some(
        ProjNode::new(
          wrapper.kind,
          wrapper.start,
          wrapper.end,
          next_proj_node_id(counter),
          new_children,
        ),
      )
    }
    _ => None
  }
}

///|
/// Unwrap: the prev `wrapper` is removed and its child `keep` promoted to `new`.
/// Carry `keep`'s identity into `new`; the wrapper id retires.
fn[T : TreeNode] apply_unwrap(
  wrapper : ProjNode[T],
  new : ProjNode[T],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
  keep : NodeId,
) -> ProjNode[T]? {
  match find_child(wrapper, keep) {
    Some(k) => Some(reconcile_hinted(k, new, counter, hints))
    None => None
  }
}

///|
fn[T : TreeNode] count_same_kind_children(
  parent : ProjNode[T],
  target : ProjNode[T],
) -> Int {
  parent.children.filter(c => T::same_kind(c.kind, target.kind)).length()
}

///|
fn[T] find_child(parent : ProjNode[T], id : NodeId) -> ProjNode[T]? {
  match parent.children.filter(c => c.id() == id) {
    [c, ..] => Some(c)
    [] => None
  }
}
