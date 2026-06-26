///|
/// Request intent fed into the internal provider-planning graph.
priv struct ProviderPlanningIntent {
  target : CognitionKey
  options : ProviderOptionProvenance
  snapshot : ProviderPlanningSnapshot
} derive(Eq)

///|
fn ProviderPlanningIntent::ProviderPlanningIntent(
  target~ : CognitionKey,
  options~ : ProviderOptionProvenance,
  snapshot~ : ProviderPlanningSnapshot,
) -> ProviderPlanningIntent {
  { target, options, snapshot }
}

///|
/// Graph snapshot observed while planning one provider request.
priv struct ProviderPlanningSnapshot {
  context : Array[ContextItem]
  source_revisions : Array[ProviderSourceSnapshot]
  dependencies : Array[CognitionKey]
} derive(Eq)

///|
fn ProviderPlanningSnapshot::ProviderPlanningSnapshot(
  context~ : Array[ContextItem],
  source_revisions~ : Array[ProviderSourceSnapshot],
  dependencies~ : Array[CognitionKey],
) -> ProviderPlanningSnapshot {
  {
    context: context.copy(),
    source_revisions: source_revisions.copy(),
    dependencies: dependencies.copy(),
  }
}

///|
/// User cancellation input recorded for one planned request.
priv struct ProviderCancellationRecord {
  request_id : ProviderRequestId
  cancelled_at_ms : Int
  driver_acknowledged : Bool
} derive(Eq)

///|
fn ProviderCancellationRecord::ProviderCancellationRecord(
  request_id~ : ProviderRequestId,
  cancelled_at_ms~ : Int,
) -> ProviderCancellationRecord {
  { request_id, cancelled_at_ms, driver_acknowledged: false }
}

///|
fn ProviderCancellationRecord::acknowledge_driver(
  self : ProviderCancellationRecord,
) -> ProviderCancellationRecord {
  {
    request_id: self.request_id,
    cancelled_at_ms: self.cancelled_at_ms,
    driver_acknowledged: true,
  }
}

///|
/// Driver start input recorded for the current in-flight attempt.
priv struct ProviderStartRecord {
  request_id : ProviderRequestId
  started_at_ms : Int
} derive(Eq)

///|
fn ProviderStartRecord::ProviderStartRecord(
  request_id~ : ProviderRequestId,
  started_at_ms~ : Int,
) -> ProviderStartRecord {
  { request_id, started_at_ms }
}

///|
/// Completion/error input recorded for one planned request.
priv struct ProviderCompletionRecord {
  completion : ProviderResultDescriptor
  completed_at_ms : Int
} derive(Eq)

///|
fn ProviderCompletionRecord::ProviderCompletionRecord(
  completion~ : ProviderResultDescriptor,
  completed_at_ms~ : Int,
) -> ProviderCompletionRecord {
  { completion, completed_at_ms }
}

///|
/// Internal status state for one planned provider request.
priv struct ProviderRequestState {
  request : ProviderRequestDescriptor
  start : ProviderStartRecord?
  cancellation : ProviderCancellationRecord?
  completion : ProviderCompletionRecord?
} derive(Eq)

///|
fn ProviderRequestState::ProviderRequestState(
  request~ : ProviderRequestDescriptor,
  start~ : ProviderStartRecord?,
  cancellation~ : ProviderCancellationRecord?,
  completion~ : ProviderCompletionRecord?,
) -> ProviderRequestState {
  { request, start, cancellation, completion }
}

///|
fn ProviderRequestState::pending(
  request : ProviderRequestDescriptor,
) -> ProviderRequestState {
  ProviderRequestState::ProviderRequestState(
    request~,
    start=None,
    cancellation=None,
    completion=None,
  )
}

///|
fn ProviderRequestState::with_start(
  self : ProviderRequestState,
  start : ProviderStartRecord,
) -> ProviderRequestState {
  ProviderRequestState::ProviderRequestState(
    request=self.request,
    start=Some(start),
    cancellation=self.cancellation,
    completion=self.completion,
  )
}

///|
fn ProviderRequestState::with_cancellation(
  self : ProviderRequestState,
  cancellation : ProviderCancellationRecord,
) -> ProviderRequestState {
  ProviderRequestState::ProviderRequestState(
    request=self.request,
    start=self.start,
    cancellation=Some(cancellation),
    completion=self.completion,
  )
}

///|
fn ProviderRequestState::with_cancellation_acknowledged(
  self : ProviderRequestState,
) -> ProviderRequestState {
  match self.cancellation {
    Some(cancellation) =>
      ProviderRequestState::ProviderRequestState(
        request=self.request,
        start=self.start,
        cancellation=Some(cancellation.acknowledge_driver()),
        completion=self.completion,
      )
    None => self
  }
}

///|
fn ProviderRequestState::with_completion(
  self : ProviderRequestState,
  completion : ProviderCompletionRecord,
) -> ProviderRequestState {
  ProviderRequestState::ProviderRequestState(
    request=self.request,
    start=None,
    cancellation=self.cancellation,
    completion=Some(completion),
  )
}

///|
fn ProviderRequestState::status(
  self : ProviderRequestState,
) -> ProviderRequestStatus {
  provider_status_for_records(self.request, self.cancellation, self.completion)
}

///|
fn ProviderRequestState::driver_action(
  self : ProviderRequestState,
  now_ms : Int,
) -> ProviderDriverAction {
  provider_next_driver_action_for_records(
    self.request,
    self.start,
    self.cancellation,
    self.completion,
    now_ms,
  )
}

///|
/// Deterministic next action for a provider driver to interpret outside `@incr`.
priv enum ProviderDriverAction {
  NoDriverAction
  StartProviderRequest(ProviderRequestDescriptor)
  CancelProviderRequest(ProviderRequestId)
  WaitProviderRetry(ProviderRequestId, Int)
  RetryProviderRequest(ProviderRequestDescriptor)
} derive(Eq)

///|
/// Internal `@incr` cells for provider planning/status state.
priv struct ProviderPlanningGraph {
  runtime : @incr.Runtime
  scope : @incr.Scope
  intent : @incr.Input[ProviderPlanningIntent?]
  request_states : @incr.Input[Array[ProviderRequestState]]
  fake_time_ms : @incr.Input[Int]
  dependency_fingerprint_cell_id : @incr.CellId
  request_cell_id : @incr.CellId
  status_cell_id : @incr.CellId
  retry_classification_cell_id : @incr.CellId
  next_driver_action_cell_id : @incr.CellId
  dependency_fingerprint_watch : @incr.Watch[ProviderDependencyFingerprint?]
  request_watch : @incr.Watch[ProviderRequestDescriptor?]
  status_watch : @incr.Watch[ProviderStatusDescriptor?]
  retry_classification_watch : @incr.Watch[ProviderRetryClassification?]
  next_driver_action_watch : @incr.Watch[ProviderDriverAction]
}

///|
fn ProviderPlanningGraph::ProviderPlanningGraph(
  runtime : @incr.Runtime,
) -> ProviderPlanningGraph {
  let scope = @incr.Scope::new(runtime)
  let intent : @incr.Input[ProviderPlanningIntent?] = scope.input(
    None,
    label="cognition_provider_request_intent",
  )
  let request_states : @incr.Input[Array[ProviderRequestState]] = scope.input(
    [],
    label="cognition_provider_request_states",
  )
  let fake_time_ms = scope.input(0, label="cognition_provider_fake_time_ms")
  let dependency_fingerprint_cell = scope.derived(
    fn() {
      match intent.get() {
        Some(intent) =>
          Some(
            provider_dependency_fingerprint_for_snapshots(
              intent.snapshot.dependencies,
              intent.snapshot.source_revisions,
            ),
          )
        None => None
      }
    },
    label="cognition_provider_dependency_fingerprint",
  )
  let request_cell = scope.derived(
    fn() {
      match (intent.get(), dependency_fingerprint_cell.get_or_abort()) {
        (Some(intent), Some(dependency_fingerprint)) =>
          Some(
            ProviderRequestDescriptor::new(
              id=provider_request_id_for(
                intent.target,
                intent.options,
                dependency_fingerprint,
              ),
              target=intent.target,
              options=intent.options,
              context=intent.snapshot.context,
              source_revisions=intent.snapshot.source_revisions,
              dependencies=intent.snapshot.dependencies,
              dependency_fingerprint~,
            ),
          )
        _ => None
      }
    },
    label="cognition_provider_request_descriptor",
  )
  let status_cell = request_cell.map_eq(
    request => {
      match request {
        Some(request) => {
          let state = provider_state_for_request(request_states.get(), request).unwrap_or(
            ProviderRequestState::pending(request),
          )
          Some(
            ProviderStatusDescriptor::new(
              request_id=request.id(),
              target=request.target(),
              status=state.status(),
            ),
          )
        }
        None => None
      }
    },
    label="cognition_provider_status",
  )
  let retry_classification_cell = status_cell.map_eq(
    status => {
      match status {
        Some(status) =>
          match status.status() {
            ProviderRequestStatus::Failed(error) =>
              Some(error.retry_classification())
            _ => None
          }
        None => None
      }
    },
    label="cognition_provider_retry_classification",
  )
  // Register mapped cells for deterministic scope disposal — replacing
  // scope.derived (which auto-registers) with map_eq would otherwise leave
  // status_cell/retry_classification_cell unregistered, creating a contract
  // gap vs original code. Disposal determinism, not GC rooting.
  scope.add_cell_ids([status_cell.id(), retry_classification_cell.id()])
  let next_driver_action_cell = scope.derived(
    fn() {
      provider_next_driver_action_for_states(
        request_states.get(),
        fake_time_ms.get(),
      )
    },
    label="cognition_provider_next_driver_action",
  )
  let graph = {
    runtime,
    scope,
    intent,
    request_states,
    fake_time_ms,
    dependency_fingerprint_cell_id: dependency_fingerprint_cell.id(),
    request_cell_id: request_cell.id(),
    status_cell_id: status_cell.id(),
    retry_classification_cell_id: retry_classification_cell.id(),
    next_driver_action_cell_id: next_driver_action_cell.id(),
    dependency_fingerprint_watch: scope.add_watch(
      dependency_fingerprint_cell.watch(),
    ),
    request_watch: scope.add_watch(request_cell.watch()),
    status_watch: scope.add_watch(status_cell.watch()),
    retry_classification_watch: scope.add_watch(
      retry_classification_cell.watch(),
    ),
    next_driver_action_watch: scope.add_watch(next_driver_action_cell.watch()),
  }
  let _ = graph.watched_cells_are_rooted()
  graph
}

///|
fn ProviderPlanningGraph::plan_request(
  self : ProviderPlanningGraph,
  target~ : CognitionKey,
  options~ : ProviderOptionProvenance,
  context~ : Array[ContextItem],
  source_revisions~ : Array[ProviderSourceSnapshot],
  dependencies~ : Array[CognitionKey],
) -> ProviderRequestDescriptor {
  self.intent.set(
    Some(
      ProviderPlanningIntent::ProviderPlanningIntent(
        target~,
        options~,
        snapshot=ProviderPlanningSnapshot::ProviderPlanningSnapshot(
          context~,
          source_revisions~,
          dependencies~,
        ),
      ),
    ),
  )
  let request = self.current_request_or_abort()
  self.request_states.set(
    provider_request_states_ensure(self.request_states.peek(), request),
  )
  request
}

///|
fn ProviderPlanningGraph::clear_events(self : ProviderPlanningGraph) -> Unit {
  match self.current_request() {
    Some(request) =>
      self.request_states.set(
        provider_request_states_upsert(
          self.request_states.peek(),
          ProviderRequestState::pending(request),
        ),
      )
    None => ()
  }
}

///|
fn ProviderPlanningGraph::record_cancellation(
  self : ProviderPlanningGraph,
  request : ProviderRequestDescriptor,
) -> Unit {
  let cancellation = ProviderCancellationRecord::ProviderCancellationRecord(
    request_id=request.id(),
    cancelled_at_ms=self.fake_time_ms.peek(),
  )
  self.request_states.set(
    provider_request_states_record_cancellation(
      self.request_states.peek(),
      request,
      cancellation,
    ),
  )
}

///|
fn ProviderPlanningGraph::acknowledge_cancellation(
  self : ProviderPlanningGraph,
  request_id : ProviderRequestId,
) -> Unit {
  self.request_states.set(
    provider_request_states_acknowledge_cancellation(
      self.request_states.peek(),
      request_id,
    ),
  )
}

///|
fn ProviderPlanningGraph::acknowledge_start(
  self : ProviderPlanningGraph,
  request_id : ProviderRequestId,
) -> Unit {
  let start = ProviderStartRecord::ProviderStartRecord(
    request_id~,
    started_at_ms=self.fake_time_ms.peek(),
  )
  self.request_states.set(
    provider_request_states_acknowledge_start(
      self.request_states.peek(),
      request_id,
      start,
    ),
  )
}

///|
fn ProviderPlanningGraph::record_completion(
  self : ProviderPlanningGraph,
  request : ProviderRequestDescriptor,
  completion : ProviderResultDescriptor,
) -> Unit {
  let completion_record = ProviderCompletionRecord::ProviderCompletionRecord(
    completion~,
    completed_at_ms=self.fake_time_ms.peek(),
  )
  self.request_states.set(
    provider_request_states_record_completion(
      self.request_states.peek(),
      request,
      completion_record,
    ),
  )
}

///|
fn ProviderPlanningGraph::set_fake_time_ms(
  self : ProviderPlanningGraph,
  now_ms : Int,
) -> Unit {
  self.fake_time_ms.set(now_ms)
}

///|
fn ProviderPlanningGraph::next_driver_action_at(
  self : ProviderPlanningGraph,
  now_ms : Int,
) -> ProviderDriverAction {
  self.fake_time_ms.set(now_ms)
  self.next_driver_action()
}

///|
fn ProviderPlanningGraph::current_request(
  self : ProviderPlanningGraph,
) -> ProviderRequestDescriptor? {
  self.ensure_scope_live()
  self.request_watch.read_or_abort()
}

///|
fn ProviderPlanningGraph::current_request_or_abort(
  self : ProviderPlanningGraph,
) -> ProviderRequestDescriptor {
  match self.current_request() {
    Some(request) => request
    None => abort("provider planning graph produced no request")
  }
}

///|
fn ProviderPlanningGraph::dependency_fingerprint(
  self : ProviderPlanningGraph,
) -> ProviderDependencyFingerprint? {
  self.ensure_scope_live()
  self.dependency_fingerprint_watch.read_or_abort()
}

///|
fn ProviderPlanningGraph::status(
  self : ProviderPlanningGraph,
) -> ProviderStatusDescriptor? {
  self.ensure_scope_live()
  self.status_watch.read_or_abort()
}

///|
fn ProviderPlanningGraph::retry_classification(
  self : ProviderPlanningGraph,
) -> ProviderRetryClassification? {
  self.ensure_scope_live()
  self.retry_classification_watch.read_or_abort()
}

///|
fn ProviderPlanningGraph::next_driver_action(
  self : ProviderPlanningGraph,
) -> ProviderDriverAction {
  self.ensure_scope_live()
  self.next_driver_action_watch.read_or_abort()
}

///|
fn ProviderPlanningGraph::watched_cells_are_rooted(
  self : ProviderPlanningGraph,
) -> Bool {
  self.runtime.gc_root_count(self.dependency_fingerprint_cell_id) > 0 &&
  self.runtime.gc_root_count(self.request_cell_id) > 0 &&
  self.runtime.gc_root_count(self.status_cell_id) > 0 &&
  self.runtime.gc_root_count(self.retry_classification_cell_id) > 0 &&
  self.runtime.gc_root_count(self.next_driver_action_cell_id) > 0
}

///|
fn ProviderPlanningGraph::ensure_scope_live(
  self : ProviderPlanningGraph,
) -> Unit {
  guard !self.scope.is_disposed() else {
    abort("provider planning graph scope is disposed")
  }
}

///|
fn provider_request_states_ensure(
  states : Array[ProviderRequestState],
  request : ProviderRequestDescriptor,
) -> Array[ProviderRequestState] {
  if provider_state_for_request(states, request) is Some(_) {
    states.copy()
  } else {
    let next = states.copy()
    next.push(ProviderRequestState::pending(request))
    next
  }
}

///|
fn provider_request_states_upsert(
  states : Array[ProviderRequestState],
  state : ProviderRequestState,
) -> Array[ProviderRequestState] {
  let next : Array[ProviderRequestState] = []
  let mut replaced = false
  for existing in states {
    if existing.request.id() == state.request.id() {
      next.push(state)
      replaced = true
    } else {
      next.push(existing)
    }
  }
  if !replaced {
    next.push(state)
  }
  next
}

///|
fn provider_request_states_record_cancellation(
  states : Array[ProviderRequestState],
  request : ProviderRequestDescriptor,
  cancellation : ProviderCancellationRecord,
) -> Array[ProviderRequestState] {
  match provider_state_for_request(states, request) {
    Some(state) =>
      provider_request_states_upsert(
        states,
        state.with_cancellation(cancellation),
      )
    None => states.copy()
  }
}

///|
fn provider_request_states_record_completion(
  states : Array[ProviderRequestState],
  request : ProviderRequestDescriptor,
  completion : ProviderCompletionRecord,
) -> Array[ProviderRequestState] {
  match provider_state_for_request(states, request) {
    Some(state) =>
      provider_request_states_upsert(states, state.with_completion(completion))
    None => states.copy()
  }
}

///|
fn provider_request_states_acknowledge_cancellation(
  states : Array[ProviderRequestState],
  request_id : ProviderRequestId,
) -> Array[ProviderRequestState] {
  let next : Array[ProviderRequestState] = []
  for state in states {
    if state.request.id() == request_id {
      next.push(state.with_cancellation_acknowledged())
    } else {
      next.push(state)
    }
  }
  next
}

///|
fn provider_request_states_acknowledge_start(
  states : Array[ProviderRequestState],
  request_id : ProviderRequestId,
  start : ProviderStartRecord,
) -> Array[ProviderRequestState] {
  let next : Array[ProviderRequestState] = []
  for state in states {
    if state.request.id() == request_id {
      next.push(state.with_start(start))
    } else {
      next.push(state)
    }
  }
  next
}

///|
fn provider_state_for_request(
  states : Array[ProviderRequestState],
  request : ProviderRequestDescriptor,
) -> ProviderRequestState? {
  for state in states {
    if state.request.id() == request.id() {
      return Some(state)
    }
  }
  None
}

///|
fn provider_next_driver_action_for_states(
  states : Array[ProviderRequestState],
  now_ms : Int,
) -> ProviderDriverAction {
  let mut cancellation_action : ProviderDriverAction? = None
  let mut pending_start_action : ProviderDriverAction? = None
  let mut retry_action : ProviderDriverAction? = None
  let mut delayed_action : ProviderDriverAction? = None
  for state in states {
    let action = state.driver_action(now_ms)
    match action {
      ProviderDriverAction::CancelProviderRequest(request_id) =>
        if cancellation_action is None {
          cancellation_action = Some(
            ProviderDriverAction::CancelProviderRequest(request_id),
          )
        }
      _ =>
        if !provider_request_is_superseded_by_later_target(
            states,
            state.request,
          ) {
          match action {
            ProviderDriverAction::NoDriverAction => ()
            ProviderDriverAction::WaitProviderRetry(request_id, ready_at_ms) =>
              match delayed_action {
                Some(
                  ProviderDriverAction::WaitProviderRetry(
                    _,
                    current_ready_at_ms
                  )
                ) =>
                  if current_ready_at_ms > ready_at_ms {
                    delayed_action = Some(
                      ProviderDriverAction::WaitProviderRetry(
                        request_id, ready_at_ms,
                      ),
                    )
                  }
                _ =>
                  delayed_action = Some(
                    ProviderDriverAction::WaitProviderRetry(
                      request_id, ready_at_ms,
                    ),
                  )
              }
            ProviderDriverAction::CancelProviderRequest(_) => ()
            ProviderDriverAction::StartProviderRequest(request) =>
              if pending_start_action is None {
                pending_start_action = Some(
                  ProviderDriverAction::StartProviderRequest(request),
                )
              }
            ProviderDriverAction::RetryProviderRequest(request) =>
              if retry_action is None {
                retry_action = Some(
                  ProviderDriverAction::RetryProviderRequest(request),
                )
              }
          }
        }
    }
  }
  match cancellation_action {
    Some(action) => action
    None =>
      match pending_start_action {
        Some(action) => action
        None =>
          match retry_action {
            Some(action) => action
            None =>
              delayed_action.unwrap_or(ProviderDriverAction::NoDriverAction)
          }
      }
  }
}

///|
fn provider_request_is_superseded_by_later_target(
  states : Array[ProviderRequestState],
  request : ProviderRequestDescriptor,
) -> Bool {
  let mut seen_request = false
  for state in states {
    if state.request.id() == request.id() {
      seen_request = true
    } else if seen_request && state.request.target() == request.target() {
      return true
    }
  }
  false
}

///|
fn provider_status_for_records(
  request : ProviderRequestDescriptor,
  cancellation : ProviderCancellationRecord?,
  completion : ProviderCompletionRecord?,
) -> ProviderRequestStatus {
  if provider_cancellation_wins(request, cancellation, completion) {
    ProviderRequestStatus::Failed(ProviderError::Cancelled)
  } else {
    match completion {
      Some(record) if provider_completion_matches_request(request, record) =>
        record.completion.status()
      _ => ProviderRequestStatus::Pending
    }
  }
}

///|
fn provider_next_driver_action_for_records(
  request : ProviderRequestDescriptor,
  start : ProviderStartRecord?,
  cancellation : ProviderCancellationRecord?,
  completion : ProviderCompletionRecord?,
  now_ms : Int,
) -> ProviderDriverAction {
  if provider_cancellation_wins(request, cancellation, completion) {
    match cancellation {
      Some(record) if !record.driver_acknowledged =>
        ProviderDriverAction::CancelProviderRequest(request.id())
      _ => ProviderDriverAction::NoDriverAction
    }
  } else if provider_start_matches_request(request, start) {
    ProviderDriverAction::NoDriverAction
  } else {
    match completion {
      Some(record) if provider_completion_matches_request(request, record) =>
        match record.completion.status() {
          ProviderRequestStatus::Failed(error) =>
            provider_retry_driver_action(
              request,
              error,
              record.completed_at_ms,
              now_ms,
            )
          _ => ProviderDriverAction::NoDriverAction
        }
      _ => ProviderDriverAction::StartProviderRequest(request)
    }
  }
}

///|
fn provider_start_matches_request(
  request : ProviderRequestDescriptor,
  start : ProviderStartRecord?,
) -> Bool {
  match start {
    Some(record) => record.request_id == request.id()
    None => false
  }
}

///|
fn provider_retry_driver_action(
  request : ProviderRequestDescriptor,
  error : ProviderError,
  completed_at_ms : Int,
  now_ms : Int,
) -> ProviderDriverAction {
  match error.retry_classification() {
    ProviderRetryClassification::RetryableLater(retry_after_ms~) => {
      let ready_at_ms = completed_at_ms + retry_after_ms.unwrap_or(0)
      if now_ms >= ready_at_ms {
        ProviderDriverAction::RetryProviderRequest(request)
      } else {
        ProviderDriverAction::WaitProviderRetry(request.id(), ready_at_ms)
      }
    }
    _ => ProviderDriverAction::NoDriverAction
  }
}

///|
fn provider_cancellation_wins(
  request : ProviderRequestDescriptor,
  cancellation : ProviderCancellationRecord?,
  completion : ProviderCompletionRecord?,
) -> Bool {
  match cancellation {
    Some(record) if provider_cancellation_matches_request(request, record) =>
      match completion {
        Some(completion) if provider_completion_matches_request(
            request, completion,
          ) => record.cancelled_at_ms <= completion.completed_at_ms
        _ => true
      }
    _ => false
  }
}

///|
fn provider_cancellation_matches_request(
  request : ProviderRequestDescriptor,
  cancellation : ProviderCancellationRecord,
) -> Bool {
  cancellation.request_id == request.id()
}

///|
fn provider_completion_matches_request(
  request : ProviderRequestDescriptor,
  completion : ProviderCompletionRecord,
) -> Bool {
  completion.completion.request_id() == request.id()
}
