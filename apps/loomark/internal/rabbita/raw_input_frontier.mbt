///|
/// The unified semantic Raw input frontier.
///
/// The transition matrix and shell boundary are documented in
/// `docs/plans/2026-08-10-loomark-raw-input-state-reducer.md`. This state owns
/// browser-visible Raw snapshots and their ordering. It does not own DOM,
/// scheduling, clocks, telemetry, or editor effects.
priv struct RawInputState {
  pending : PendingRawInput?
  composition : PendingRawInput?
  deferred_composition_finished : Bool
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
fn RawInputState::initial() -> RawInputState {
  {
    pending: None,
    composition: None,
    deferred_composition_finished: false,
    deferred_before_input: None,
    deferred: None,
    deferred_composition: None,
    in_flight: None,
  }
}

///|
/// A reducer decision contains only data for the imperative shell to execute.
/// The shell allocates the token before dispatching `BeginPendingDelivery`;
/// the reducer decides whether that pending input can become active.
priv enum RawInputDecision {
  Noop
  StoredPending
  Deliver(Int, PendingRawInput)
}

///|
priv enum RawInputEvent {
  CaptureDeferredBeforeInput(DeferredRawInputCapture)
  StoreDeferred(DeferredRawInput)
  BeginDeferredComposition(DeferredRawInput)
  UpdateDeferredComposition(DeferredRawInput)
  ClearDeferredCapture
  ClearDeferred
  ClearDeferredComposition
  StorePending(PendingRawInput)
  BeginPendingDelivery(Int)
  BeginComposition(PendingRawInput)
  UpdateComposition(PendingRawInput)
  ClearComposition
  MarkDeferredCompositionFinished
  ClearDeferredCompositionFinished
  BeginDelivery(RawInputDelivery)
  FinishDelivery(Int)
  DiscardDelivery(Int)
  Cancel
}

///|
/// Pure transition function for semantic browser-visible Raw state.
fn reduce_raw_input(
  state : RawInputState,
  event : RawInputEvent,
) -> (RawInputState, RawInputDecision) {
  match event {
    RawInputEvent::CaptureDeferredBeforeInput(capture) =>
      if (state.in_flight is Some(_) || state.deferred is Some(_)) &&
        state.deferred_composition is None {
        (
          { ..state, deferred_before_input: Some(capture) },
          RawInputDecision::Noop,
        )
      } else {
        (state, RawInputDecision::Noop)
      }
    RawInputEvent::StoreDeferred(deferred) =>
      if state.in_flight is Some(_) &&
        state.deferred_before_input is Some(_) &&
        state.deferred_composition is None {
        (
          { ..state, deferred_before_input: None, deferred: Some(deferred) },
          RawInputDecision::Noop,
        )
      } else {
        (state, RawInputDecision::Noop)
      }
    RawInputEvent::BeginDeferredComposition(composition) =>
      if state.in_flight is Some(_) && state.deferred_composition is None {
        (
          {
            ..state,
            deferred_composition_finished: false,
            deferred: None,
            deferred_before_input: None,
            deferred_composition: Some(composition),
          },
          RawInputDecision::Noop,
        )
      } else {
        (state, RawInputDecision::Noop)
      }
    RawInputEvent::UpdateDeferredComposition(composition) =>
      if state.deferred_composition is Some(_) {
        (
          { ..state, deferred_composition: Some(composition) },
          RawInputDecision::Noop,
        )
      } else {
        (state, RawInputDecision::Noop)
      }
    RawInputEvent::ClearDeferredCapture =>
      ({ ..state, deferred_before_input: None }, RawInputDecision::Noop)
    RawInputEvent::ClearDeferred =>
      (
        { ..state, deferred_before_input: None, deferred: None },
        RawInputDecision::Noop,
      )
    RawInputEvent::ClearDeferredComposition =>
      ({ ..state, deferred_composition: None }, RawInputDecision::Noop)
    RawInputEvent::StorePending(input) =>
      if state.composition is None &&
        state.deferred_before_input is None &&
        state.deferred is None &&
        state.deferred_composition is None {
        ({ ..state, pending: Some(input) }, RawInputDecision::StoredPending)
      } else {
        (state, RawInputDecision::Noop)
      }
    RawInputEvent::BeginPendingDelivery(token) =>
      match state.pending {
        Some(input) if state.in_flight is None &&
          state.composition is None &&
          state.deferred_before_input is None &&
          state.deferred is None &&
          state.deferred_composition is None => {
          let (next, _) = reduce_raw_input(
            { ..state, pending: None },
            RawInputEvent::BeginDelivery({ token, source: input.source }),
          )
          match next.in_flight {
            Some(delivery) if delivery.token == token =>
              (next, RawInputDecision::Deliver(token, input))
            _ => (state, RawInputDecision::Noop)
          }
        }
        _ => (state, RawInputDecision::Noop)
      }
    RawInputEvent::BeginComposition(input) =>
      if state.in_flight is None &&
        state.deferred_before_input is None &&
        state.deferred is None &&
        state.deferred_composition is None {
        (
          {
            ..state,
            pending: None,
            composition: Some(input),
            deferred_composition_finished: false,
          },
          RawInputDecision::Noop,
        )
      } else {
        (state, RawInputDecision::Noop)
      }
    RawInputEvent::UpdateComposition(input) =>
      if state.composition is Some(_) {
        ({ ..state, composition: Some(input) }, RawInputDecision::Noop)
      } else {
        (state, RawInputDecision::Noop)
      }
    RawInputEvent::ClearComposition =>
      ({ ..state, composition: None }, RawInputDecision::Noop)
    RawInputEvent::MarkDeferredCompositionFinished =>
      if state.deferred_composition is Some(_) {
        (
          { ..state, deferred_composition_finished: true },
          RawInputDecision::Noop,
        )
      } else {
        (state, RawInputDecision::Noop)
      }
    RawInputEvent::ClearDeferredCompositionFinished =>
      (
        { ..state, deferred_composition_finished: false },
        RawInputDecision::Noop,
      )
    RawInputEvent::BeginDelivery(delivery) =>
      if state.in_flight is None &&
        state.pending is None &&
        state.composition is None &&
        state.deferred_before_input is None &&
        state.deferred is None &&
        state.deferred_composition is None {
        ({ ..state, in_flight: Some(delivery) }, RawInputDecision::Noop)
      } else {
        (state, RawInputDecision::Noop)
      }
    RawInputEvent::FinishDelivery(token) =>
      match state.in_flight {
        Some(delivery) if delivery.token == token => {
          let next = { ..state, in_flight: None, deferred_before_input: None }
          let next = if next.deferred_composition is None &&
            next.pending is None {
            { ..next, deferred_composition_finished: false }
          } else {
            next
          }
          (next, RawInputDecision::Noop)
        }
        _ => (state, RawInputDecision::Noop)
      }
    RawInputEvent::DiscardDelivery(token) =>
      match state.in_flight {
        Some(delivery) if delivery.token == token =>
          (RawInputState::initial(), RawInputDecision::Noop)
        _ => (state, RawInputDecision::Noop)
      }
    RawInputEvent::Cancel => (RawInputState::initial(), RawInputDecision::Noop)
  }
}
