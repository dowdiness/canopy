// AST reconciliation: preserve ProjNode identities across reparses.

///|
fn emit_trace(
  trace_ref : Ref[Array[ReconcileTraceEvent]]?,
  event : ReconcileTraceEvent,
) -> Unit {
  match trace_ref {
    Some(r) => r.val.push(event)
    None => ()
  }
}

///|
/// Generic reconciliation: Preserve node IDs where possible when AST changes.
pub fn[T : TreeNode + Renderable] reconcile(
  old : ProjNode[T],
  new : ProjNode[T],
  counter : Ref[Int],
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
) -> ProjNode[T] {
  reconcile_hinted(old, new, counter, {}, trace_ref~)
}

///|
/// Reconcile with a caller-provided exact-key preference for sibling LCS.
/// The key describes a node's own payload; child structure is fingerprinted by
/// the reconciler. Exact keys only break ties between same-kind matches: they
/// cannot reduce the number of matched children, and content edits still fall
/// back to `TreeNode::same_kind`.
pub fn[T : TreeNode + Renderable] reconcile_with_exact_key(
  old : ProjNode[T],
  new : ProjNode[T],
  counter : Ref[Int],
  exact_key : (T) -> String,
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
) -> ProjNode[T] {
  let interner : Map[String, Int] = {}
  let next_fingerprint = Ref(0)
  let old_fingerprints = exact_fingerprint_map(
    old, exact_key, interner, next_fingerprint,
  )
  let new_fingerprints = exact_fingerprint_map(
    new, exact_key, interner, next_fingerprint,
  )
  reconcile_exact(
    old,
    new,
    counter,
    old_fingerprints,
    new_fingerprints,
    trace_ref~,
  )
}

///|
/// Reconciliation with structural-edit hints. Behaves identically to `reconcile`
/// when `hints` is empty. A `Wrap` / `Unwrap` hint (keyed by the previous node's
/// id) lets identity survive a constructor change at a position that positional
/// LCS reconciliation alone would lose — see
/// docs/architecture/grove-and-structural-identity.md.
pub fn[T : TreeNode + Renderable] reconcile_hinted(
  old : ProjNode[T],
  new : ProjNode[T],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
) -> ProjNode[T] {
  // A structural hint keyed by `old.id()` (wrap / unwrap) takes precedence and
  // may apply even when the new wrapper is the SAME kind as the wrapped node —
  // e.g. wrapping an `App` inside another `App`. Checked before the same-kind
  // branch so identity lands on the wrapped node, not the new wrapper. Skipped
  // entirely when there are no hints, keeping the per-keystroke path free of
  // extra lookups.
  let hinted = if hints.is_empty() {
    NoStructuralHint
  } else {
    structural_pair(old, new, counter, hints, trace_ref~)
  }
  match hinted {
    Applied(node) => node
    // A wrap/unwrap hint targeted this node but could not be located — degrade
    // to fresh ids rather than leaving the preserved id on the new wrapper.
    Unlocatable => assign_fresh_ids(new, counter)
    NoStructuralHint =>
      if T::same_kind(old.kind, new.kind) {
        let reconciled_children = reconcile_children(
          old.children,
          new.children,
          counter,
          hints,
          old.node_id,
          trace_ref~,
        )
        ProjNode(new.kind, new.start, new.end, old.node_id, reconciled_children)
      } else {
        assign_fresh_ids(new, counter)
      }
  }
}

///|
fn[T : TreeNode + Renderable] reconcile_children(
  old_children : Array[ProjNode[T]],
  new_children : Array[ProjNode[T]],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
  parent_id : NodeId,
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
) -> Array[ProjNode[T]] {
  let old_len = old_children.length()
  let new_len = new_children.length()
  // Old children carrying a wrap/unwrap/replace/move hint are excluded from
  // ordinary LCS matching: their identity is decided by the hint logic, so they
  // must not be consumed by a same-kind match against the wrong new sibling
  // first. Rename / insert / delete / opaque hints stay matchable (LCS already
  // preserves those). Computed only when hints are present.
  let excluded_old : Array[Bool] = if hints.is_empty() {
    []
  } else {
    Array::makei(old_len, oi => lcs_excluded(hints, old_children[oi].id()))
  }
  let lcs_match = fn(oi : Int, nj : Int) -> Bool {
    T::same_kind(old_children[oi].kind, new_children[nj].kind) &&
    (excluded_old.length() == 0 || excluded_old[oi] == false)
  }
  // Each row must be a fresh array — use makei (called per row), not
  // Array::make(.., Array::make(..)) which would share one inner array
  // reference across all rows and corrupt the DP.
  let dp = Array::makei(old_len + 1, _ => Array::make(new_len + 1, 0))
  for i = 1; i <= old_len; i = i + 1 {
    for j = 1; j <= new_len; j = j + 1 {
      if lcs_match(i - 1, j - 1) {
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
    if lcs_match(i - 1, j - 1) {
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
  // How many LCS-unmatched new children each unmatched old child's hint pairs
  // with. Identity is carried only for an unambiguous 1:1 pairing, so an old
  // node whose wrapped subtree could land in more than one new sibling is
  // rejected (symmetric to the multiple-old-claiming-one-new case).
  let old_pair_counts : Map[NodeId, Int] = if hints.is_empty() {
    {}
  } else {
    hint_pair_counts(
      old_children, new_children, old_matched, new_matched, hints,
    )
  }
  let result = [
    for k in 0..<new_len => {
      if new_matched[k] >= 0 {
        let reconciled = reconcile_hinted(
          old_children[new_matched[k]],
          new_children[k],
          counter,
          hints,
          trace_ref~,
        )
        emit_trace(
          trace_ref,
          Matched(
            parent_id,
            new_matched[k],
            k,
            reconciled.id(),
            T::kind_tag(reconciled.kind),
          ),
        )
        reconciled
      } else if hints.is_empty() {
        let fresh = assign_fresh_ids(new_children[k], counter)
        emit_trace(
          trace_ref,
          Inserted(parent_id, k, fresh.id(), T::kind_tag(fresh.kind)),
        )
        fresh
      } else {
        match
          try_unmatched_hint_pair(
            new_children[k],
            old_children,
            old_matched,
            old_pair_counts,
            consumed,
            counter,
            hints,
            trace_ref~,
          ) {
          Some(node) => {
            emit_trace(
              trace_ref,
              Matched(parent_id, -1, k, node.id(), T::kind_tag(node.kind)),
            )
            node
          }
          None => {
            let fresh = assign_fresh_ids(new_children[k], counter)
            emit_trace(
              trace_ref,
              Inserted(parent_id, k, fresh.id(), T::kind_tag(fresh.kind)),
            )
            fresh
          }
        }
      }
    }
  ]
  for oi = 0; oi < old_len; oi = oi + 1 {
    if old_matched[oi] < 0 {
      emit_trace(
        trace_ref,
        Deleted(
          parent_id,
          oi,
          old_children[oi].id(),
          T::kind_tag(old_children[oi].kind),
        ),
      )
    }
  }
  result
}

///|
/// Build position-independent fingerprints once for one projection tree.
fn[T] exact_fingerprint_map(
  root : ProjNode[T],
  exact_key : (T) -> String,
  interner : Map[String, Int],
  next_fingerprint : Ref[Int],
) -> Map[NodeId, Int] {
  let result : Map[NodeId, Int] = {}
  let _ = root.fold(fn(node, children : Array[Int]) -> Int {
    let key = exact_key(node.kind)
    let signature = key.length().to_string() +
      ":" +
      key +
      "|" +
      children.length().to_string() +
      ":" +
      children.map(id => id.to_string()).join(",")
    let fingerprint = match interner.get(signature) {
      Some(id) => id
      None => {
        let id = next_fingerprint.val
        next_fingerprint.val += 1
        interner[signature] = id
        id
      }
    }
    result[node.id()] = fingerprint
    fingerprint
  })
  result
}

///|
/// Child reconciliation for `reconcile_with_exact_key`.
///
/// This path intentionally has no structural-edit hints: the JSX projection
/// uses it for ordinary streaming updates, while the default/hinted path above
/// retains the framework's historical LCS tie-breaking contract.
fn[T : TreeNode + Renderable] reconcile_children_exact(
  old_children : Array[ProjNode[T]],
  new_children : Array[ProjNode[T]],
  counter : Ref[Int],
  old_fingerprints : Map[NodeId, Int],
  new_fingerprints : Map[NodeId, Int],
  parent_id : NodeId,
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
) -> Array[ProjNode[T]] {
  let old_len = old_children.length()
  let new_len = new_children.length()
  let match_base_score = old_len.min(new_len) + 1
  let match_score = fn(oi : Int, nj : Int) -> Int {
    if !T::same_kind(old_children[oi].kind, new_children[nj].kind) {
      0
    } else if old_fingerprints[old_children[oi].id()] ==
      new_fingerprints[new_children[nj].id()] {
      match_base_score + 1
    } else {
      match_base_score
    }
  }
  let dp = Array::makei(old_len + 1, _ => Array::make(new_len + 1, 0))
  for i = 1; i <= old_len; i = i + 1 {
    for j = 1; j <= new_len; j = j + 1 {
      let diagonal = dp[i - 1][j - 1] + match_score(i - 1, j - 1)
      dp[i][j] = @cmp.maximum(
        @cmp.maximum(dp[i - 1][j], dp[i][j - 1]),
        diagonal,
      )
    }
  }
  let old_matched = Array::make(old_len, -1)
  let new_matched = Array::make(new_len, -1)
  let mut i = old_len
  let mut j = new_len
  while i > 0 && j > 0 {
    let score = match_score(i - 1, j - 1)
    if score > 0 && dp[i][j] == dp[i - 1][j - 1] + score {
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
  let result = [
    for k in 0..<new_len => {
      if new_matched[k] >= 0 {
        let reconciled = reconcile_exact(
          old_children[new_matched[k]],
          new_children[k],
          counter,
          old_fingerprints,
          new_fingerprints,
          trace_ref~,
        )
        emit_trace(
          trace_ref,
          Matched(
            parent_id,
            new_matched[k],
            k,
            reconciled.id(),
            T::kind_tag(reconciled.kind),
          ),
        )
        reconciled
      } else {
        let fresh = assign_fresh_ids(new_children[k], counter)
        emit_trace(
          trace_ref,
          Inserted(parent_id, k, fresh.id(), T::kind_tag(fresh.kind)),
        )
        fresh
      }
    }
  ]
  for oi = 0; oi < old_len; oi = oi + 1 {
    if old_matched[oi] < 0 {
      emit_trace(
        trace_ref,
        Deleted(
          parent_id,
          oi,
          old_children[oi].id(),
          T::kind_tag(old_children[oi].kind),
        ),
      )
    }
  }
  result
}

///|
fn[T : TreeNode + Renderable] reconcile_exact(
  old : ProjNode[T],
  new : ProjNode[T],
  counter : Ref[Int],
  old_fingerprints : Map[NodeId, Int],
  new_fingerprints : Map[NodeId, Int],
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
) -> ProjNode[T] {
  if T::same_kind(old.kind, new.kind) {
    let reconciled_children = reconcile_children_exact(
      old.children,
      new.children,
      counter,
      old_fingerprints,
      new_fingerprints,
      old.node_id,
      trace_ref~,
    )
    ProjNode(new.kind, new.start, new.end, old.node_id, reconciled_children)
  } else {
    assign_fresh_ids(new, counter)
  }
}

///|
/// Outcome of consulting structural hints for one node.
priv enum HintResult[T] {
  /// No wrap/unwrap hint targets this node — reconcile normally.
  NoStructuralHint
  /// A hint applied; carries the reconciled node.
  Applied(ProjNode[T])
  /// A hint targets this node but its subtree could not be located
  /// unambiguously — the caller must degrade to fresh ids (invariant T3).
  Unlocatable
}

///|
/// Consult the structural hint keyed by `old.id()`. A `Wrap`/`Unwrap` hint is
/// authoritative: it either applies or forces a degrade-to-fresh. It never
/// silently falls through to same-kind reconciliation (which would leave the
/// preserved id on the new wrapper).
fn[T : TreeNode + Renderable] structural_pair(
  old : ProjNode[T],
  new : ProjNode[T],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
) -> HintResult[T] {
  match hints.get(old.id()) {
    Some(Wrap(_)) =>
      match apply_wrap(old, new, counter, hints, trace_ref~) {
        Some(node) => {
          emit_trace(
            trace_ref,
            Wrapped(old.id(), node.id(), T::kind_tag(node.kind)),
          )
          Applied(node)
        }
        None => Unlocatable
      }
    Some(Unwrap(keep~, ..)) =>
      match apply_unwrap(old, new, counter, hints, keep, trace_ref~) {
        Some(node) => {
          emit_trace(
            trace_ref,
            Unwrapped(old.id(), node.id(), T::kind_tag(old.kind)),
          )
          Applied(node)
        }
        None => Unlocatable
      }
    // Replace retires the old identity; Move's identity is editor-owned
    // (move_node) and not reconcilable here. Both freshen the node at this
    // position rather than preserving `old.node_id`.
    Some(Replace(_)) | Some(Move(_)) => Applied(assign_fresh_ids(new, counter))
    _ => NoStructuralHint
  }
}

///|
/// Whether an old child's hint means "do not let ordinary LCS assign this
/// identity". Wrap/Unwrap/Replace/Move are handled by the hint logic; rename /
/// insert / delete / opaque (and no hint) are left to LCS, which already honors
/// them.
fn lcs_excluded(hints : Map[NodeId, IdentityTransform], id : NodeId) -> Bool {
  match hints.get(id) {
    Some(RenameLeaf(_))
    | Some(InsertSubtree(..))
    | Some(DeleteSubtree(_))
    | Some(Opaque)
    | None => false
    Some(_) => true
  }
}

///|
/// For an LCS-unmatched `new_child`, find a still-unmatched, unconsumed prev
/// child whose `Wrap`/`Unwrap` hint pairs with it, and carry identity.
fn[T : TreeNode + Renderable] try_unmatched_hint_pair(
  new_child : ProjNode[T],
  old_children : Array[ProjNode[T]],
  old_matched : Array[Int],
  old_pair_counts : Map[NodeId, Int],
  consumed : Map[NodeId, Bool],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
) -> ProjNode[T]? {
  let candidates = [
    for idx, o in old_children if old_matched[idx] < 0 &&
    consumed.get(o.id()) is None &&
    old_pair_counts.get(o.id()) is Some(1) &&
    hint_pairs(o, new_child, hints) => o
  ]
  // Carry identity only for an unambiguous singleton candidate; 0 or >1
  // candidates (multiple old siblings claiming the same new child) degrade to
  // fresh ids rather than assigning identity by sibling iteration order. The
  // `old_pair_counts is Some(1)` filter rejects the mirror case — one old node
  // that could pair with several new siblings.
  match candidates {
    [o] => {
      consumed[o.id()] = true
      match structural_pair(o, new_child, counter, hints, trace_ref~) {
        Applied(node) => Some(node)
        _ => None
      }
    }
    _ => None
  }
}

///|
/// For each LCS-unmatched old child carrying a wrap/unwrap hint, how many
/// LCS-unmatched new children that hint pairs with. A count other than 1 means
/// the wrapped subtree cannot be located in exactly one new sibling, so identity
/// must degrade to fresh rather than be assigned by sibling order.
fn[T : TreeNode] hint_pair_counts(
  old_children : Array[ProjNode[T]],
  new_children : Array[ProjNode[T]],
  old_matched : Array[Int],
  new_matched : Array[Int],
  hints : Map[NodeId, IdentityTransform],
) -> Map[NodeId, Int] {
  let counts : Map[NodeId, Int] = {}
  for oi, o in old_children {
    if old_matched[oi] < 0 {
      let cnt = [
        for k, n in new_children if new_matched[k] < 0 &&
        hint_pairs(o, n, hints) => n
      ].length()
      if cnt > 0 {
        counts[o.id()] = cnt
      }
    }
  }
  counts
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
fn[T : TreeNode + Renderable] apply_wrap(
  old : ProjNode[T],
  wrapper : ProjNode[T],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
) -> ProjNode[T]? {
  let targets = [
    for idx, c in wrapper.children if T::same_kind(c.kind, old.kind) => idx
  ]
  match targets {
    [target] => {
      let new_children = [
        for idx, c in wrapper.children => {
          if idx == target {
            // `c` is same_kind as `old` by selection — carry `old`'s identity
            // directly and reconcile their children. Routing through
            // reconcile_hinted here would re-apply `old`'s own wrap hint and
            // push the id one level too deep.
            ProjNode(
              c.kind,
              c.start,
              c.end,
              old.node_id,
              reconcile_children(
                old.children,
                c.children,
                counter,
                hints,
                old.node_id,
                trace_ref~,
              ),
            )
          } else {
            assign_fresh_ids(c, counter)
          }
        }
      ]
      Some(
        ProjNode(
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
fn[T : TreeNode + Renderable] apply_unwrap(
  wrapper : ProjNode[T],
  new : ProjNode[T],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
  keep : NodeId,
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
) -> ProjNode[T]? {
  match find_child(wrapper, keep) {
    Some(k) => Some(reconcile_hinted(k, new, counter, hints, trace_ref~))
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
