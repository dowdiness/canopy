///|
/// The native Raw frontier that can be ahead of the committed document.
///
/// This is the functional core of the browser-input race: DOM snapshots move
/// from an active delivery into a deferred snapshot, then back to pending at
/// the newly accepted document frontier. Scheduler commands and DOM effects
/// remain in RawInputCoordinator as the imperative shell.
priv struct RawInputFrontierState {
  deferred_before_input : DeferredRawInputCapture?
  deferred : DeferredRawInput?
  deferred_composition : DeferredRawInput?
  in_flight : RawInputDelivery?
}

///|
priv struct RawInputDelivery {
  token : Int
  source : String
}

///|
fn RawInputFrontierState::initial() -> RawInputFrontierState {
  {
    deferred_before_input: None,
    deferred: None,
    deferred_composition: None,
    in_flight: None,
  }
}

///|
priv enum RawInputFrontierEvent {
  CaptureDeferredBeforeInput(DeferredRawInputCapture)
  StoreDeferred(DeferredRawInput)
  BeginDeferredComposition(DeferredRawInput)
  UpdateDeferredComposition(DeferredRawInput)
  ClearDeferredCapture
  ClearDeferred
  ClearDeferredComposition
  BeginDelivery(RawInputDelivery)
  FinishDelivery(Int)
  DiscardDelivery(Int)
  Cancel
}

///|
/// Pure transition function for the browser-visible Raw frontier.
fn reduce_raw_input_frontier(
  state : RawInputFrontierState,
  event : RawInputFrontierEvent,
) -> RawInputFrontierState {
  match event {
    RawInputFrontierEvent::CaptureDeferredBeforeInput(capture) =>
      if (state.in_flight is Some(_) || state.deferred is Some(_)) &&
        state.deferred_composition is None {
        { ..state, deferred_before_input: Some(capture) }
      } else {
        state
      }
    RawInputFrontierEvent::StoreDeferred(deferred) =>
      if state.in_flight is Some(_) &&
        state.deferred_before_input is Some(_) &&
        state.deferred_composition is None {
        { ..state, deferred_before_input: None, deferred: Some(deferred) }
      } else {
        state
      }
    RawInputFrontierEvent::BeginDeferredComposition(composition) =>
      if state.in_flight is Some(_) && state.deferred_composition is None {
        {
          ..state,
          deferred: None,
          deferred_before_input: None,
          deferred_composition: Some(composition),
        }
      } else {
        state
      }
    RawInputFrontierEvent::UpdateDeferredComposition(composition) =>
      if state.deferred_composition is Some(_) {
        { ..state, deferred_composition: Some(composition) }
      } else {
        state
      }
    RawInputFrontierEvent::ClearDeferredCapture =>
      { ..state, deferred_before_input: None }
    RawInputFrontierEvent::ClearDeferred =>
      { ..state, deferred_before_input: None, deferred: None }
    RawInputFrontierEvent::ClearDeferredComposition =>
      { ..state, deferred_composition: None }
    RawInputFrontierEvent::BeginDelivery(delivery) =>
      if state.in_flight is None {
        { ..state, in_flight: Some(delivery) }
      } else {
        state
      }
    RawInputFrontierEvent::FinishDelivery(token) =>
      match state.in_flight {
        Some(delivery) if delivery.token == token =>
          { ..state, in_flight: None }
        _ => state
      }
    RawInputFrontierEvent::DiscardDelivery(token) =>
      match state.in_flight {
        Some(delivery) if delivery.token == token =>
          {
            deferred_before_input: None,
            deferred: None,
            deferred_composition: None,
            in_flight: None,
          }
        _ => state
      }
    RawInputFrontierEvent::Cancel =>
      {
        deferred_before_input: None,
        deferred: None,
        deferred_composition: None,
        in_flight: None,
      }
  }
}
