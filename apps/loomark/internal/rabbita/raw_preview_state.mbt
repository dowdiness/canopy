///|
/// Bounded scheduling decision for speculative Raw Preview parsing.
#warnings("-unused_value")
priv enum RawPreviewQueueDecision {
  Dispatch(String)
  Wait
} derive(Eq, Debug)

///|
/// Pure active-plus-latest queue. The active parse may finish, while every
/// not-yet-started source is replaced by the newest browser-owned source.
#warnings("-unused_value")
priv struct RawPreviewQueueState {
  active : String?
  latest : String?
} derive(Eq, Debug)

///|
fn RawPreviewQueueState::initial() -> RawPreviewQueueState {
  { active: None, latest: None }
}

///|
fn RawPreviewQueueState::request(
  self : RawPreviewQueueState,
  source : String,
) -> (RawPreviewQueueState, RawPreviewQueueDecision) {
  match self.active {
    None =>
      (
        { active: Some(source), latest: None },
        RawPreviewQueueDecision::Dispatch(source),
      )
    Some(active) if active == source =>
      ({ ..self, latest: None }, RawPreviewQueueDecision::Wait)
    Some(_) => ({ ..self, latest: Some(source) }, RawPreviewQueueDecision::Wait)
  }
}

///|
fn RawPreviewQueueState::complete(
  self : RawPreviewQueueState,
  source : String,
) -> (RawPreviewQueueState, RawPreviewQueueDecision) {
  guard self.active == Some(source) else {
    return (self, RawPreviewQueueDecision::Wait)
  }
  match self.latest {
    None => (RawPreviewQueueState::initial(), RawPreviewQueueDecision::Wait)
    Some(latest) =>
      (
        { active: Some(latest), latest: None },
        RawPreviewQueueDecision::Dispatch(latest),
      )
  }
}
