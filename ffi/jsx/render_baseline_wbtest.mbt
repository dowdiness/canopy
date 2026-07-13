///|
fn baseline_after_success(
  baseline : SessionBaseline,
  kind : RenderKind,
  structural_transition : Bool,
) -> SessionBaseline {
  let plan = plan_or_abort(baseline, kind, structural_transition)
  let (next, _) = finish_render(plan, Success)
  next
}

///|
fn permit_or_abort(baseline : SessionBaseline) -> RenderPermit {
  match begin_render(baseline) {
    Ok(permit) => permit
    Err(RevisionExhausted) => abort("test unexpectedly exhausted its revision")
  }
}

///|
fn plan_or_abort(
  baseline : SessionBaseline,
  kind : RenderKind,
  structural_transition : Bool,
) -> RenderPlan {
  plan_render(permit_or_abort(baseline), kind, structural_transition)
}

///|
fn assert_no_baseline_effect(effect : SessionBaselineEffect) -> Unit raise {
  match effect {
    NoEffect => ()
    RestoreCommittedSource => fail("expected no baseline effect")
  }
}

///|
fn assert_source_restoration(effect : SessionBaselineEffect) -> Unit raise {
  match effect {
    RestoreCommittedSource => ()
    NoEffect => fail("expected committed-source restoration")
  }
}

///|
fn baseline_effect_matches(
  actual : SessionBaselineEffect,
  expected : SessionBaselineEffect,
) -> Bool {
  match (actual, expected) {
    (NoEffect, NoEffect) | (RestoreCommittedSource, RestoreCommittedSource) =>
      true
    _ => false
  }
}

///|
fn baseline_matches(
  actual : SessionBaseline,
  expected : SessionBaseline,
) -> Bool {
  actual.mounted_origin == expected.mounted_origin &&
  actual.dirty == expected.dirty &&
  actual.revision == expected.revision
}

///|
test "render baseline: initial source success preserves clean source origin" {
  let initial = SessionBaseline::initial()
  let plan = plan_or_abort(initial, Source, false)
  assert_false(plan.must_remount)
  let (next, effect) = finish_render(plan, Success)
  assert_no_baseline_effect(effect)
  assert_true(next.mounted_origin == Source)
  assert_false(next.dirty)
  assert_eq(next.revision, 1)
}

///|
test "render baseline: candidate success always remounts" {
  let initial = SessionBaseline::initial()
  let plan = plan_or_abort(initial, Candidate, false)
  assert_true(plan.must_remount)
  let (next, effect) = finish_render(plan, Success)
  assert_no_baseline_effect(effect)
  assert_true(next.mounted_origin == Candidate)
  assert_false(next.dirty)
  assert_eq(next.revision, 1)
}

///|
test "render baseline: source success following candidate remounts" {
  let candidate = baseline_after_success(
    SessionBaseline::initial(),
    Candidate,
    false,
  )
  let plan = plan_or_abort(candidate, Source, false)
  assert_true(plan.must_remount)
  let (next, effect) = finish_render(plan, Success)
  assert_no_baseline_effect(effect)
  assert_true(next.mounted_origin == Source)
  assert_false(next.dirty)
  assert_eq(next.revision, 2)
}

///|
test "render baseline: dry-run failure retains origin and marks dirty" {
  let initial = SessionBaseline::initial()
  let plan = plan_or_abort(initial, Source, false)
  let (next, effect) = finish_render(plan, DryRunFail)
  assert_source_restoration(effect)
  assert_true(next.mounted_origin == Source)
  assert_true(next.dirty)
  assert_eq(next.revision, 0)
}

///|
test "render baseline: DOM failure retains origin and marks dirty" {
  let initial = SessionBaseline::initial()
  let plan = plan_or_abort(initial, Source, false)
  let (next, effect) = finish_render(plan, DomFail)
  assert_source_restoration(effect)
  assert_true(next.mounted_origin == Source)
  assert_true(next.dirty)
  assert_eq(next.revision, 0)
}

///|
test "render baseline: candidate failures never restore source" {
  let initial = SessionBaseline::initial()
  let plan = plan_or_abort(initial, Candidate, false)
  let (after_dry_run, dry_run_effect) = finish_render(plan, DryRunFail)
  assert_no_baseline_effect(dry_run_effect)
  assert_true(after_dry_run.dirty)
  let (after_dom, dom_effect) = finish_render(plan, DomFail)
  assert_no_baseline_effect(dom_effect)
  assert_true(after_dom.dirty)
  let (after_projection, projection_effect) = finish_render(
    plan,
    ProjectionFail,
  )
  assert_no_baseline_effect(projection_effect)
  assert_true(baseline_matches(after_projection, initial))
}

///|
test "render baseline: source projection failure requests source restoration" {
  let candidate = baseline_after_success(
    SessionBaseline::initial(),
    Candidate,
    false,
  )
  let plan = plan_or_abort(candidate, Source, false)
  assert_true(plan.must_remount)
  let (next, effect) = finish_render(plan, ProjectionFail)
  assert_source_restoration(effect)
  assert_true(baseline_matches(next, candidate))
  assert_true(next.mounted_origin == Candidate)
  assert_false(next.dirty)
  assert_eq(next.revision, 1)
}

///|
test "render baseline: final permitted success reaches cap then rejects" {
  let before_cap = SessionBaseline(
    mounted_origin=Source,
    dirty=false,
    revision=MAX_SESSION_REVISION - 1,
  )
  let plan = plan_or_abort(before_cap, Source, false)
  let (exhausted, effect) = finish_render(plan, Success)
  assert_no_baseline_effect(effect)
  assert_true(exhausted.mounted_origin == Source)
  assert_false(exhausted.dirty)
  assert_eq(exhausted.revision, MAX_SESSION_REVISION)
  match begin_render(exhausted) {
    Err(RevisionExhausted) => {
      assert_true(exhausted.mounted_origin == Source)
      assert_false(exhausted.dirty)
      assert_eq(exhausted.revision, MAX_SESSION_REVISION)
    }
    Ok(_) => abort("exhausted revision unexpectedly produced a render plan")
  }
}

///|
struct BaselineEvent {
  kind : RenderKind
  structural_transition : Bool
  outcome : RenderOutcome
} derive(Debug)

///|
fn generate_baseline_event(rs : @splitmix.RandomState) -> BaselineEvent {
  let bits = rs.next_positive_int()
  let kind = if bits % 2 == 0 { Source } else { Candidate }
  let structural_transition = bits / 2 % 2 == 0
  let outcome = match bits / 4 % 4 {
    0 => Success
    1 => DryRunFail
    2 => DomFail
    _ => ProjectionFail
  }
  { kind, structural_transition, outcome }
}

///|
struct BaselineScenario {
  events : Array[BaselineEvent]
} derive(Debug)

///|
impl @quickcheck.Arbitrary for BaselineScenario with fn arbitrary(size, rs) {
  let length = if size > 12 { 12 } else { size }
  { events: [ for _ in 0..<length => generate_baseline_event(rs.split()) ] }
}

///|
impl @qc.Shrink for BaselineScenario

///|
fn prop_baseline_preserves_reachable_lifecycle_invariants(
  scenario : BaselineScenario,
) -> Bool {
  let (_, valid) = scenario.events.fold(
    init=(SessionBaseline::initial(), true),
    (state, event) => {
      let (baseline, valid) = state
      let plan = plan_or_abort(
        baseline,
        event.kind,
        event.structural_transition,
      )
      let (next, effect) = finish_render(plan, event.outcome)
      let candidate_attempt_remounts = event.kind != Candidate ||
        plan.must_remount
      let dirty_baseline_remounts = !baseline.dirty || plan.must_remount
      let source_after_candidate_remounts = baseline.mounted_origin != Candidate ||
        event.kind != Source ||
        plan.must_remount
      let expected_source_failure_effect = if event.kind == Source {
        RestoreCommittedSource
      } else {
        NoEffect
      }
      let outcome_is_consistent = match event.outcome {
        Success =>
          next.revision == baseline.revision + 1 &&
          next.mounted_origin == event.kind &&
          !next.dirty &&
          baseline_effect_matches(effect, NoEffect)
        DryRunFail | DomFail =>
          next.revision == baseline.revision &&
          next.mounted_origin == baseline.mounted_origin &&
          next.dirty &&
          baseline_effect_matches(effect, expected_source_failure_effect)
        ProjectionFail =>
          baseline_matches(next, baseline) &&
          baseline_effect_matches(effect, expected_source_failure_effect)
      }
      (
        next,
        valid &&
        candidate_attempt_remounts &&
        dirty_baseline_remounts &&
        source_after_candidate_remounts &&
        outcome_is_consistent,
      )
    },
  )
  valid
}

///|
test "property: render baseline preserves reachable lifecycle invariants" {
  @qc.quick_check_fn(prop_baseline_preserves_reachable_lifecycle_invariants)
}
