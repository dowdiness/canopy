///|
/// Scalar model for the leaf-count change published by `propagate`.
pub fn splice_leaf_delta(
  start : Int,
  end_ : Int,
  inserted_count : Int,
) -> Int where {
  proof_ensure: result => leaf_delta_law(start, end_, inserted_count, result),
} {
  inserted_count - (end_ - start)
}

///|
/// Scalar model for the leaf count after replacing `[start, end_)`.
pub fn splice_new_count(
  old_count : Int,
  start : Int,
  end_ : Int,
  inserted_count : Int,
) -> Int where {
  proof_require: valid_splice(old_count, start, end_, inserted_count),
  proof_ensure: result => {
    splice_cardinality_law(old_count, start, end_, inserted_count, result)
  },
} {
  old_count - (end_ - start) + inserted_count
}

///|
/// One scalar step of `legal_chunk_sizes`.
///
/// `remaining <= 2 * min_degree` is the terminal push. Otherwise this mirrors
/// the loop's split decision and leaves another legal non-root remainder.
pub fn planned_group_size(
  remaining : Int,
  min_degree : Int,
) -> Int where {
  proof_require: valid_group_state(remaining, min_degree),
  proof_ensure: result => grouping_step_law(remaining, min_degree, result),
} {
  let max_degree = 2 * min_degree
  if remaining <= max_degree {
    remaining
  } else if remaining - max_degree < min_degree {
    remaining / 2
  } else {
    max_degree
  }
}

///|
/// Sum every scalar group emitted by repeated planner steps.
///
/// Strict remainder decrease proves termination; the postcondition proves that
/// all emitted group sizes sum exactly to the input child count.
pub fn planned_group_total(
  remaining : Int,
  min_degree : Int,
) -> Int where {
  proof_decrease: remaining,
  proof_require: valid_group_state(remaining, min_degree),
  proof_ensure: result => grouping_total_law(remaining, result),
} {
  if remaining <= 2 * min_degree {
    remaining
  } else {
    let group_size = planned_group_size(remaining, min_degree)
    let rest = remaining - group_size
    group_size + planned_group_total(rest, min_degree)
  }
}

///|
/// Advance the emitted-child accumulator by one planned group.
///
/// The postcondition is the induction step used to compose local grouping
/// decisions: emitted children plus remaining children stays equal to the
/// original input count, and a terminal step emits the exact total.
pub fn advance_group_sum(
  original_count : Int,
  emitted_count : Int,
  remaining : Int,
  min_degree : Int,
) -> Int where {
  proof_require: valid_group_accumulator(
    original_count, emitted_count, remaining, min_degree,
  ),
  proof_ensure: result => {
    grouping_accumulator_law(
      original_count, emitted_count, remaining, min_degree, result,
    )
  },
} {
  emitted_count + planned_group_size(remaining, min_degree)
}

///|
/// Child count of an underfull node after the range-repair merge-or-steal
/// decision. The sibling's remaining count is modeled in the postcondition.
pub fn repaired_node_count(
  underfull_count : Int,
  sibling_count : Int,
  min_degree : Int,
  target_count : Int,
) -> Int where {
  proof_require: valid_repair_state(
    underfull_count, sibling_count, min_degree, target_count,
  ),
  proof_ensure: result => {
    repair_conservation_law(
      underfull_count, sibling_count, min_degree, target_count, result,
    )
  },
  proof_ensure: result => {
    repair_occupancy_law(
      underfull_count, sibling_count, min_degree, target_count, result,
    )
  },
  proof_ensure: result => {
    repair_donor_law(
      underfull_count, sibling_count, min_degree, target_count, result,
    )
  },
} {
  let transfer = target_count - underfull_count
  if sibling_count - transfer < min_degree {
    proof_assert 0 <= underfull_count + sibling_count
    proof_assert underfull_count + sibling_count <= 2 * min_degree
    underfull_count + sibling_count
  } else {
    proof_assert sibling_count - transfer >= min_degree
    proof_assert min_degree <= target_count
    proof_assert target_count <= 2 * min_degree
    target_count
  }
}

///|
/// Preserve the full child total around one reactive repair step.
///
/// `unaffected_count` is the count outside the participating sibling pair.
/// Repeated loop steps may choose a new pair and decomposition, while each step
/// preserves the same global total independently of merge versus steal.
pub fn repair_total_with_unaffected(
  unaffected_count : Int,
  underfull_count : Int,
  sibling_count : Int,
  min_degree : Int,
  target_count : Int,
) -> Int where {
  proof_require: unaffected_count >= 0,
  proof_require: valid_repair_state(
    underfull_count, sibling_count, min_degree, target_count,
  ),
  proof_ensure: result => {
    repair_total_with_unaffected_law(
      unaffected_count, underfull_count, sibling_count, result,
    )
  },
} {
  let transfer = target_count - underfull_count
  if sibling_count - transfer < min_degree {
    unaffected_count + underfull_count + sibling_count
  } else {
    unaffected_count + target_count + (sibling_count - transfer)
  }
}

///|
/// Exact acceptance predicate used by `checked_span_add` before addition.
/// The literal is the mathematical model of `@int.MAX_VALUE` (2^31 - 1).
pub fn span_add_accepted(
  total : Int,
  span : Int,
) -> Bool where {
  proof_ensure: result => checked_add_law(total, span, result),
} {
  total >= 0 && span >= 0 && total <= 2147483647 - span
}

///|
/// Scalar root-publication projection. Recursive root collapse remains covered
/// by executable BTree properties; this proves only the published leaf-count
/// contract.
pub fn project_root_present(
  leaf_count : Int,
) -> Bool where {
  proof_require: leaf_count >= 0,
  proof_ensure: result => root_lifecycle_law(leaf_count, result),
} {
  leaf_count > 0
}
