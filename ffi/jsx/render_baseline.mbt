///|
/// The origin of a successful render and the kind currently being planned.
priv enum RenderKind {
  Source
  Candidate
} derive(Debug, Eq)

///|
/// Application cap below the signed 32-bit edge. Planning rejects the next
/// render at this revision before any dry-run or DOM work can begin.
const MAX_SESSION_REVISION : Int = 2147483646

///|
/// The logical state committed only after a successful DOM application.
priv struct SessionBaseline {
  mounted_origin : RenderKind
  dirty : Bool
  revision : Int
}

///|
fn SessionBaseline::SessionBaseline(
  mounted_origin~ : RenderKind,
  dirty~ : Bool,
  revision~ : Int,
) -> SessionBaseline {
  { mounted_origin, dirty, revision }
}

///|
fn SessionBaseline::initial() -> SessionBaseline {
  SessionBaseline(mounted_origin=Source, dirty=false, revision=0)
}

///|
/// Evidence that the baseline admitted one render before imperative work.
priv struct RenderPermit {
  baseline : SessionBaseline
}

///|
fn RenderPermit::RenderPermit(baseline~ : SessionBaseline) -> RenderPermit {
  { baseline, }
}

///|
/// A render decision derived before dry-run or DOM effects occur.
priv struct RenderPlan {
  baseline : SessionBaseline
  kind : RenderKind
  must_remount : Bool
}

///|
fn RenderPlan::RenderPlan(
  baseline~ : SessionBaseline,
  kind~ : RenderKind,
  must_remount~ : Bool,
) -> RenderPlan {
  { baseline, kind, must_remount }
}

///|
priv enum RenderOutcome {
  Success
  DryRunFail
  DomFail
  ProjectionFail
} derive(Debug)

///|
priv enum SessionBaselineEffect {
  NoEffect
  RestoreCommittedSource
}

///|
priv enum RenderPlanningError {
  RevisionExhausted
}

///|
fn begin_render(
  baseline : SessionBaseline,
) -> Result[RenderPermit, RenderPlanningError] {
  guard baseline.revision < MAX_SESSION_REVISION else {
    return Err(RevisionExhausted)
  }
  Ok(RenderPermit(baseline~))
}

///|
fn plan_render(
  permit : RenderPermit,
  kind : RenderKind,
  structural_transition : Bool,
) -> RenderPlan {
  let baseline = permit.baseline
  RenderPlan(
    baseline~,
    kind~,
    must_remount=kind == Candidate ||
      baseline.mounted_origin == Candidate ||
      baseline.dirty ||
      structural_transition,
  )
}

///|
fn finish_render(
  plan : RenderPlan,
  outcome : RenderOutcome,
) -> (SessionBaseline, SessionBaselineEffect) {
  let baseline = plan.baseline
  let failure_effect = match plan.kind {
    Source => RestoreCommittedSource
    Candidate => NoEffect
  }
  match outcome {
    Success =>
      (
        SessionBaseline(
          mounted_origin=plan.kind,
          dirty=false,
          revision=baseline.revision + 1,
        ),
        NoEffect,
      )
    DryRunFail | DomFail =>
      (
        SessionBaseline(
          mounted_origin=baseline.mounted_origin,
          dirty=true,
          revision=baseline.revision,
        ),
        failure_effect,
      )
    ProjectionFail => (baseline, failure_effect)
  }
}
