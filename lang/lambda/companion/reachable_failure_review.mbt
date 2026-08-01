///|
/// Producer-neutral metadata supplied by the agent host for one reviewed edit.
/// `summary` describes this edit for a human; it is not a durable identity or
/// graph/revision reference.
pub(all) struct ReachableFailureAttribution {
  producer : String
  edit_id : String
  summary : String
} derive(Debug)

///|
/// A detached before/after scope-failure review for one applied Lambda edit.
/// The agent host is the consumer; this is deliberately not an audit schema.
pub struct ReachableFailureReview {
  priv attribution_value : ReachableFailureAttribution
  priv edits_value : Array[@core.SpanEdit]
  priv diff_value : @lambda_scope.FailureDiff
}

///|
pub fn ReachableFailureReview::attribution(
  self : ReachableFailureReview,
) -> ReachableFailureAttribution {
  self.attribution_value
}

///|
pub fn ReachableFailureReview::edits(
  self : ReachableFailureReview,
) -> Array[@core.SpanEdit] {
  self.edits_value.copy()
}

///|
pub fn ReachableFailureReview::diff(
  self : ReachableFailureReview,
) -> @lambda_scope.FailureDiff {
  detach_failure_diff(self.diff_value)
}

///|
/// Deterministic functional core for the review shell. It composes the scope
/// package's remapping and semantic diff exactly once, then owns detached data.
fn build_reachable_failure_review(
  attribution : ReachableFailureAttribution,
  applied_edits : Array[@core.SpanEdit],
  before : Array[@lambda_scope.ReachableFailure],
  after : Array[@lambda_scope.ReachableFailure],
) -> ReachableFailureReview {
  let failure_diff = @lambda_scope.diff(
    @lambda_scope.remap_failures(before, applied_edits),
    after,
  )
  {
    attribution_value: attribution,
    edits_value: applied_edits.copy(),
    diff_value: detach_failure_diff(failure_diff),
  }
}

///|
/// `ReachableFailure.witness` is documented upstream as shared, so report
/// ownership requires copying it even when remapping returned input values.
fn detach_failure(
  failure : @lambda_scope.ReachableFailure,
) -> @lambda_scope.ReachableFailure {
  {
    name: failure.name,
    location: failure.location,
    witness: failure.witness.copy(),
  }
}

///|
fn detach_failure_diff(
  diff : @lambda_scope.FailureDiff,
) -> @lambda_scope.FailureDiff {
  {
    newly_reachable: diff.newly_reachable.map(detach_failure),
    resolved: diff.resolved.map(detach_failure),
  }
}
