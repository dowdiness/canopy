// AST reconciliation: preserve ProjNode identities across reparses.
//
// One private matching engine behind the three public adapters (`reconcile`,
// `reconcile_hinted`, `reconcile_with_exact_key`): a `MatchPlan` ledger
// produced by two identity-evidence-specific producers (hinted LCS,
// exact-key fingerprint LCS) and consumed by one shared fallback realizer.
// The positional fast path stays specialized and default/hinted-only. See
// docs/decisions/2026-08-08-core-reconcile-one-engine-behind-three-adapters.md.

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
  reconcile_hinted(old, new, counter, Map([]), trace_ref~)
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
  let interner : Map[String, Int] = Map([])
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
      if @loomcore.TreeNode::same_kind(old.kind, new.kind) {
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
/// A full-length positional match is the exact LCS result when every pair at
/// the same index has the same kind. Structural hints disable this shortcut:
/// even an otherwise positional edit may require hint-specific pairing.
fn[T : TreeNode] can_reconcile_children_positionally(
  old_children : Array[ProjNode[T]],
  new_children : Array[ProjNode[T]],
  hints : Map[NodeId, IdentityTransform],
) -> Bool {
  if !hints.is_empty() || old_children.length() != new_children.length() {
    return false
  }
  // Short-circuit on the first mismatch so LCS fallback does not pay a full
  // sibling scan when the positional fast path is obviously inapplicable.
  for index in 0..<old_children.length() {
    if !@loomcore.TreeNode::same_kind(
        old_children[index].kind,
        new_children[index].kind,
      ) {
      return false
    }
  }
  true
}

///|
/// Match ledger produced by a plan producer: which old child pairs with
/// which new child. `old_to_new[oi]` is the matched new index or -1;
/// `new_to_old[nj]` is the matched old index or -1. Both engines (hinted
/// LCS and exact-key) produce this identical shape, so one fallback realizer
/// consumes either plan.
priv struct MatchPlan {
  old_to_new : Array[Int]
  new_to_old : Array[Int]
}

///|
fn MatchPlan::MatchPlan(
  old_to_new : Array[Int],
  new_to_old : Array[Int],
) -> MatchPlan {
  { old_to_new, new_to_old }
}

///|
/// Hinted match-plan producer: ordinary LCS over same-kind siblings, with
/// hinted old children excluded from matching when their hint can land. Also
/// returns the hint pair counts used by post-LCS pairing during realization.
///
/// Cost note: the exclusion scan visits every new sibling per hinted old
/// sibling, and each `hint_pairs` scans that sibling's children. The DP below
/// is already Θ(old_len × new_len), so this adds a child-count factor to a
/// term that is there anyway — not a new order of growth. The per-keystroke
/// path takes the empty-hints branch and pays none of it.
fn[T : TreeNode] plan_hinted_lcs(
  old_children : Array[ProjNode[T]],
  new_children : Array[ProjNode[T]],
  hints : Map[NodeId, IdentityTransform],
) -> (MatchPlan, Map[NodeId, Int]) {
  let old_len = old_children.length()
  let new_len = new_children.length()
  // Old children whose hint will decide their identity are excluded from
  // ordinary LCS matching, so they are not consumed by a same-kind match
  // against the wrong new sibling first. Exclusion is decided from hint
  // APPLICABILITY, not hint presence: a Wrap/Unwrap hint that can land nowhere
  // in `new_children` must not cost its node the match plain LCS would have
  // given it. Computed only when hints are present.
  let excluded_old : Array[Bool] = if hints.is_empty() {
    []
  } else {
    Array::makei(old_len, oi => {
      lcs_excluded(old_children[oi], new_children, hints)
    })
  }
  let lcs_match = fn(oi : Int, nj : Int) -> Bool {
    @loomcore.TreeNode::same_kind(old_children[oi].kind, new_children[nj].kind) &&
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
  // How many LCS-unmatched new children each unmatched old child's hint pairs
  // with. Identity is carried only for an unambiguous 1:1 pairing, so an old
  // node whose wrapped subtree could land in more than one new sibling is
  // rejected (symmetric to the multiple-old-claiming-one-new case).
  let old_pair_counts : Map[NodeId, Int] = if hints.is_empty() {
    Map([])
  } else {
    hint_pair_counts(
      old_children, new_children, old_matched, new_matched, hints,
    )
  }
  (MatchPlan(old_matched, new_matched), old_pair_counts)
}

///|
/// Shared fallback realizer: consumes a `MatchPlan` (from either producer)
/// and emits the observable sequence both engines already produce — ascending
/// new-index order, matched-child recursion before the outer `Matched`, fresh
/// allocation for unmatched new children, and the `Deleted` loop last.
///
/// `match_node` recurses into a matched pair (identity-evidence-specific:
/// hinted or exact-key). `unmatched_new` optionally resolves an LCS-unmatched
/// new child (hint pairing); `None` means fresh allocation.
fn[T : Renderable] realize_fallback(
  old_children : Array[ProjNode[T]],
  new_children : Array[ProjNode[T]],
  plan : MatchPlan,
  counter : Ref[Int],
  parent_id : NodeId,
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
  match_node : (ProjNode[T], ProjNode[T]) -> ProjNode[T],
  unmatched_new : (ProjNode[T]) -> ProjNode[T]?,
) -> Array[ProjNode[T]] {
  let old_len = old_children.length()
  let new_len = new_children.length()
  let result = [
    for k in 0..<new_len => {
      let oi = plan.new_to_old[k]
      if oi >= 0 {
        let reconciled = match_node(old_children[oi], new_children[k])
        emit_trace(
          trace_ref,
          Matched(
            parent_id,
            oi,
            k,
            reconciled.id(),
            @loomcore.Renderable::kind_tag(reconciled.kind),
          ),
        )
        reconciled
      } else {
        match unmatched_new(new_children[k]) {
          Some(node) => {
            emit_trace(
              trace_ref,
              Matched(
                parent_id,
                -1,
                k,
                node.id(),
                @loomcore.Renderable::kind_tag(node.kind),
              ),
            )
            node
          }
          None => {
            let fresh = assign_fresh_ids(new_children[k], counter)
            emit_trace(
              trace_ref,
              Inserted(
                parent_id,
                k,
                fresh.id(),
                @loomcore.Renderable::kind_tag(fresh.kind),
              ),
            )
            fresh
          }
        }
      }
    }
  ]
  for oi = 0; oi < old_len; oi = oi + 1 {
    if plan.old_to_new[oi] < 0 {
      emit_trace(
        trace_ref,
        Deleted(
          parent_id,
          oi,
          old_children[oi].id(),
          @loomcore.Renderable::kind_tag(old_children[oi].kind),
        ),
      )
    }
  }
  result
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
  let new_len = new_children.length()
  // If the sibling lists already have a full positional same-kind match, the
  // LCS optimum is the whole list. Recurse through the matched pairs directly
  // instead of allocating and filling the quadratic DP table.
  if can_reconcile_children_positionally(old_children, new_children, hints) {
    return [
      for index in 0..<new_len => {
        let reconciled = reconcile_hinted(
          old_children[index],
          new_children[index],
          counter,
          hints,
          trace_ref~,
        )
        emit_trace(
          trace_ref,
          Matched(
            parent_id,
            index,
            index,
            reconciled.id(),
            @loomcore.Renderable::kind_tag(reconciled.kind),
          ),
        )
        reconciled
      }
    ]
  }
  let (plan, pair_counts) = plan_hinted_lcs(old_children, new_children, hints)
  let unmatched_new = if hints.is_empty() {
    (_new_child : ProjNode[T]) => None
  } else {
    // Injectivity ledger for hint-based pairing of LCS-unmatched children
    // (a consumed prev-id is paired at most once). Mutation justified as a
    // consumption marker (moonbit-base.md Control Flow).
    let consumed : Map[NodeId, Bool] = Map([])
    fn(new_child : ProjNode[T]) -> ProjNode[T]? {
      try_unmatched_hint_pair(
        new_child,
        old_children,
        plan.old_to_new,
        pair_counts,
        consumed,
        counter,
        hints,
        trace_ref~,
      )
    }
  }
  let match_node = fn(
    old_child : ProjNode[T],
    new_child : ProjNode[T],
  ) -> ProjNode[T] {
    reconcile_hinted(old_child, new_child, counter, hints, trace_ref~)
  }
  realize_fallback(
    old_children,
    new_children,
    plan,
    counter,
    parent_id,
    trace_ref~,
    match_node,
    unmatched_new,
  )
}

///|
/// Build position-independent fingerprints once for one projection tree.
fn[T] exact_fingerprint_map(
  root : ProjNode[T],
  exact_key : (T) -> String,
  interner : Map[String, Int],
  next_fingerprint : Ref[Int],
) -> Map[NodeId, Int] {
  let result : Map[NodeId, Int] = Map([])
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
/// Exact-key match-plan producer: weighted suffix DP + front reconstruction.
/// The fingerprint bonus rewards equal payloads; reconstruction from the
/// front with the earliest feasible diagonal keeps duplicate siblings'
/// prefix identities stable (pinned by the exact-key characterization tests).
fn[T : TreeNode] plan_exact_lcs(
  old_children : Array[ProjNode[T]],
  new_children : Array[ProjNode[T]],
  old_fingerprints : Map[NodeId, Int],
  new_fingerprints : Map[NodeId, Int],
) -> MatchPlan {
  let old_len = old_children.length()
  let new_len = new_children.length()
  let match_base_score = old_len.min(new_len) + 1
  let match_score = fn(oi : Int, nj : Int) -> Int {
    if !@loomcore.TreeNode::same_kind(
        old_children[oi].kind,
        new_children[nj].kind,
      ) {
      0
    } else if old_fingerprints[old_children[oi].id()] ==
      new_fingerprints[new_children[nj].id()] {
      match_base_score + 1
    } else {
      match_base_score
    }
  }
  let suffix = Array::makei(old_len + 1, _ => Array::make(new_len + 1, 0))
  let mut suffix_i = old_len
  while suffix_i > 0 {
    suffix_i -= 1
    let mut suffix_j = new_len
    while suffix_j > 0 {
      suffix_j -= 1
      let diagonal = suffix[suffix_i + 1][suffix_j + 1] +
        match_score(suffix_i, suffix_j)
      suffix[suffix_i][suffix_j] = @cmp.maximum(
        @cmp.maximum(
          suffix[suffix_i + 1][suffix_j],
          suffix[suffix_i][suffix_j + 1],
        ),
        diagonal,
      )
    }
  }
  let old_matched = Array::make(old_len, -1)
  let new_matched = Array::make(new_len, -1)
  let mut oi = 0
  let mut nj = 0
  while oi < old_len && nj < new_len {
    let score = match_score(oi, nj)
    if score > 0 && score + suffix[oi + 1][nj + 1] == suffix[oi][nj] {
      old_matched[oi] = nj
      new_matched[nj] = oi
      oi += 1
      nj += 1
    } else if suffix[oi][nj + 1] == suffix[oi][nj] {
      nj += 1
    } else {
      oi += 1
    }
  }
  MatchPlan(old_matched, new_matched)
}

///|
/// Child reconciliation for `reconcile_with_exact_key`.
///
/// This path intentionally has no structural-edit hints and NO positional
/// shortcut: the JSX projection uses it for ordinary streaming updates, and
/// its weighted suffix DP is the observable behavior. It computes the primary
/// LCS optimum, then reconstructs from the front using the earliest feasible
/// diagonal so duplicate siblings retain stable prefix identities.
fn[T : TreeNode + Renderable] reconcile_children_exact(
  old_children : Array[ProjNode[T]],
  new_children : Array[ProjNode[T]],
  counter : Ref[Int],
  old_fingerprints : Map[NodeId, Int],
  new_fingerprints : Map[NodeId, Int],
  parent_id : NodeId,
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
) -> Array[ProjNode[T]] {
  let plan = plan_exact_lcs(
    old_children, new_children, old_fingerprints, new_fingerprints,
  )
  let match_node = fn(
    old_child : ProjNode[T],
    new_child : ProjNode[T],
  ) -> ProjNode[T] {
    reconcile_exact(
      old_child,
      new_child,
      counter,
      old_fingerprints,
      new_fingerprints,
      trace_ref~,
    )
  }
  realize_fallback(
    old_children,
    new_children,
    plan,
    counter,
    parent_id,
    trace_ref~,
    match_node,
    (_new_child : ProjNode[T]) => None,
  )
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
  if @loomcore.TreeNode::same_kind(old.kind, new.kind) {
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
/// Consult the structural hint keyed by `old.id()`. A `Wrap`/`Unwrap` hint that
/// the new tree bears a trace of is authoritative: it either applies or forces a
/// degrade-to-fresh, and does not fall through to same-kind reconciliation
/// (which would leave the preserved id on the new wrapper).
///
/// A hint the new tree bears NO trace of is a different case, and falls through:
/// it is evidence about an edit that this position does not show, so letting it
/// veto ordinary matching would destroy identity plain LCS preserves. See
/// `apply_wrap` for why "no trace" and "ambiguous" must not share an outcome.
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
        Applied(node) => {
          emit_trace(
            trace_ref,
            Wrapped(
              old.id(),
              node.id(),
              @loomcore.Renderable::kind_tag(node.kind),
            ),
          )
          Applied(node)
        }
        other => other
      }
    Some(Unwrap(keep~, ..)) =>
      match apply_unwrap(old, new, counter, hints, keep, trace_ref~) {
        Applied(node) => {
          emit_trace(
            trace_ref,
            Unwrapped(
              old.id(),
              node.id(),
              @loomcore.Renderable::kind_tag(old.kind),
            ),
          )
          Applied(node)
        }
        other => other
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
/// identity".
///
/// `Replace` / `Move` are authoritative at any position — `structural_pair`
/// retires or re-owns the identity whichever new sibling they meet — so they are
/// withheld from LCS unconditionally, which also leaves match room for the other
/// old children.
///
/// `Wrap` / `Unwrap` are withheld only when the hint can actually land in some
/// new sibling. A hint whose transform the completed batch left no trace of says
/// nothing about this position, and withholding on its say-so would cost the
/// node the match plain LCS would have given it — the stale-hint defect.
///
/// Rename / insert / delete / opaque (and no hint) are left to LCS, which
/// already honors them.
fn[T : TreeNode] lcs_excluded(
  old_child : ProjNode[T],
  new_children : Array[ProjNode[T]],
  hints : Map[NodeId, IdentityTransform],
) -> Bool {
  match hints.get(old_child.id()) {
    Some(Replace(_)) | Some(Move(_)) => true
    Some(Wrap(_)) | Some(Unwrap(..)) =>
      new_children.iter().any(n => hint_pairs(old_child, n, hints))
    Some(RenameLeaf(_))
    | Some(InsertSubtree(..))
    | Some(DeleteSubtree(_))
    | Some(Opaque)
    | None => false
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
  let counts : Map[NodeId, Int] = Map([])
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
///
/// The target count is the three-way answer, and the two failures are NOT the
/// same failure:
///
/// - none: `wrapper` has no same-kind child, so it is not a wrapper OF `old` and
///   the tree carries no trace of the wrap this hint describes. The hint is
///   inert here and ordinary matching decides (`NoStructuralHint`).
/// - one: the wrapped subtree is located; carry the identity (`Applied`).
/// - several: `wrapper` may well be a wrapper of `old`, but which child holds it
///   is not decidable. Degrading to fresh ids is required here (invariant T3) —
///   falling through instead would leave `old`'s id on the wrapper itself.
///
/// That asymmetry is why inertness holds only for the none case; the scoped
/// property and its counterexamples are pinned in reconcile_hints_wbtest.mbt.
fn[T : TreeNode + Renderable] apply_wrap(
  old : ProjNode[T],
  wrapper : ProjNode[T],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
) -> HintResult[T] {
  let targets = [
    for idx, c in wrapper.children if @loomcore.TreeNode::same_kind(
      c.kind,
      old.kind,
    ) => idx
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
      Applied(
        ProjNode(
          wrapper.kind,
          wrapper.start,
          wrapper.end,
          next_proj_node_id(counter),
          new_children,
        ),
      )
    }
    [] => NoStructuralHint
    _ => Unlocatable
  }
}

///|
/// Unwrap: the prev `wrapper` is removed and its child `keep` promoted to `new`.
/// Carry `keep`'s identity into `new`; the wrapper id retires.
///
/// A `keep` this wrapper does not have is a hint about a subtree that is not
/// here: it is inert, and ordinary matching decides. That absence is Unwrap's
/// ONLY inapplicable case. In particular a `keep` whose kind differs from `new`
/// is still applied, because the recursion is what interprets the difference —
/// a nested hint on `keep` may legitimately consume it, which is how an
/// unwrap-then-wrap batch retires the old wrapper id instead of preserving it.
/// Requiring same-kind here would defeat that composition.
///
/// Unwrap has no ambiguous case — `find_child` resolves a single id — so it
/// never yields `Unlocatable`.
fn[T : TreeNode + Renderable] apply_unwrap(
  wrapper : ProjNode[T],
  new : ProjNode[T],
  counter : Ref[Int],
  hints : Map[NodeId, IdentityTransform],
  keep : NodeId,
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
) -> HintResult[T] {
  match find_child(wrapper, keep) {
    Some(k) => Applied(reconcile_hinted(k, new, counter, hints, trace_ref~))
    None => NoStructuralHint
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
