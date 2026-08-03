///| Deterministic Promise/Abort transport shell for browser lifecycle tests.

///|
/// The driver owns transport handles and one cognition lifecycle. Candidate
/// validation, dry-run, DOM application, and revision mutation remain in the
/// existing replay/session boundary.
extern "js" fn async_transport_deferred(
  signal : @js_async.AbortSignal,
) -> @js.Any =
  #|(signal) => {
  #|  let resolveNative;
  #|  let rejectNative;
  #|  const promise = new Promise((resolve, reject) => {
  #|    resolveNative = resolve;
  #|    rejectNative = reject;
  #|  });
  #|  if (signal && typeof signal.addEventListener === 'function') {
  #|    signal.addEventListener('abort', () => {
  #|      rejectNative(new Error('AbortError'));
  #|    });
  #|  }
  #|  return { promise, resolve: resolveNative, reject: rejectNative };
  #|}

///|
extern "js" fn async_transport_resolve(
  deferred : @js.Any,
  payload : String,
) -> Unit =
  #|(deferred, payload) => { deferred.resolve(payload); }

///|
extern "js" fn async_transport_is_same(left : @js.Any, right : @js.Any) -> Bool =
  #|(left, right) => left === right

///|
extern "js" fn async_provider_resolve(
  provider : @js.Any,
  payload : String,
) -> Unit =
  #|(provider, payload) => {
  #|  provider.resolve(JSON.stringify({
  #|    kind: 'resolved',
  #|    payload,
  #|  }));
  #|}

///|
extern "js" fn async_provider_reject(
  provider : @js.Any,
  code : String,
  message : String,
) -> Unit =
  #|(provider, code, message) => {
  #|  provider.reject(new Error(JSON.stringify({
  #|    kind: 'provider_rejected',
  #|    code,
  #|    reason: message,
  #|  })));
  #|}

///|
priv enum AsyncPendingKind {
  Chunk(payload~ : String)
  Final
  Failure(code~ : String, message~ : String)
}

///|

///|
priv enum AsyncPendingStatus {
  Open
  Settled
  Aborted
}

///|

///|
priv struct AsyncPending {
  generation_id : @cognition.GenerativeUiGenerationId
  base_revision : @cognition.GenerativeUiRevision
  sequence : Int
  kind : AsyncPendingKind
  deferred : @js.Any
  promise : @js_async.Promise[String]
  controller : @js_async.AbortController
  mut status : AsyncPendingStatus
}

///|
fn AsyncPending::AsyncPending(
  generation_id : @cognition.GenerativeUiGenerationId,
  base_revision : @cognition.GenerativeUiRevision,
  sequence : Int,
  kind : AsyncPendingKind,
  deferred : @js.Any,
  promise : @js_async.Promise[String],
  controller : @js_async.AbortController,
) -> AsyncPending {
  {
    generation_id,
    base_revision,
    sequence,
    kind,
    deferred,
    promise,
    controller,
    status: AsyncPendingStatus::Open,
  }
}

///|

///|
priv enum AsyncProviderStatus {
  Open
  Resolved(payload~ : String)
  Rejected(code~ : String, message~ : String)
  Aborted
}

///|
priv struct AsyncProviderPending {
  driver_handle : Int
  generation_id : @cognition.GenerativeUiGenerationId
  base_revision : @cognition.GenerativeUiRevision
  sequence : Int
  provider : @js.Any
  promise : @js_async.Promise[String]
  provider_controller : @js_async.AbortController
  mut status : AsyncProviderStatus
}

///|
fn AsyncProviderPending::AsyncProviderPending(
  driver_handle : Int,
  generation_id : @cognition.GenerativeUiGenerationId,
  base_revision : @cognition.GenerativeUiRevision,
  sequence : Int,
  provider : @js.Any,
  promise : @js_async.Promise[String],
  provider_controller : @js_async.AbortController,
) -> AsyncProviderPending {
  {
    driver_handle,
    generation_id,
    base_revision,
    sequence,
    provider,
    promise,
    provider_controller,
    status: AsyncProviderStatus::Open,
  }
}

///|
priv struct GenerativeUiAsyncDriver {
  session_handle : Int
  lifecycle : @cognition.GenerativeUiLifecycle
  mut generation_id : @cognition.GenerativeUiGenerationId
  generation_ids : Map[Int, @cognition.GenerativeUiGenerationId]
  mut base_revision : @cognition.GenerativeUiRevision
  mut next_sequence : Int
  pending : @queue.Queue[AsyncPending]
  mut current_pending : AsyncPending?
  provider_handles : Array[Int]
  mut commit_count : Int
  mut abort_observed : Bool
  mut disposed : Bool
}

///|
fn GenerativeUiAsyncDriver::GenerativeUiAsyncDriver(
  session_handle : Int,
  lifecycle : @cognition.GenerativeUiLifecycle,
  generation_id : @cognition.GenerativeUiGenerationId,
  generation_ids : Map[Int, @cognition.GenerativeUiGenerationId],
  base_revision : @cognition.GenerativeUiRevision,
  next_sequence : Int,
  pending : @queue.Queue[AsyncPending],
  current_pending : AsyncPending?,
  provider_handles : Array[Int],
  commit_count : Int,
  abort_observed : Bool,
  disposed : Bool,
) -> GenerativeUiAsyncDriver {
  {
    session_handle,
    lifecycle,
    generation_id,
    generation_ids,
    base_revision,
    next_sequence,
    pending,
    current_pending,
    provider_handles,
    commit_count,
    abort_observed,
    disposed,
  }
}

///|
let async_driver_registry : Map[Int, GenerativeUiAsyncDriver] = Map([])

///|
let async_provider_registry : Map[Int, AsyncProviderPending] = Map([])

///|
let next_async_driver_handle : Ref[Int] = Ref(1)

///|
let next_async_provider_handle : Ref[Int] = Ref(1)

///|
fn async_transition_json(
  transition : @cognition.GenerativeUiTransition,
) -> String {
  match transition {
    @cognition.GenerativeUiTransition::Started(generation_id~) =>
      Json::object({
        "kind": Json::string("started"),
        "generation_id": Json::number(generation_id.to_int().to_double()),
      }).stringify()
    @cognition.GenerativeUiTransition::ChunkAccepted(sequence~) =>
      Json::object({
        "kind": Json::string("chunk_accepted"),
        "sequence": Json::number(sequence.to_double()),
      }).stringify()
    @cognition.GenerativeUiTransition::DuplicateChunk(sequence~) =>
      Json::object({
        "kind": Json::string("duplicate_chunk"),
        "sequence": Json::number(sequence.to_double()),
      }).stringify()
    @cognition.GenerativeUiTransition::Finalized =>
      Json::object({ "kind": Json::string("finalized") }).stringify()
    @cognition.GenerativeUiTransition::ValidationStarted =>
      Json::object({ "kind": Json::string("validation_started") }).stringify()
    @cognition.GenerativeUiTransition::DryRunStarted =>
      Json::object({ "kind": Json::string("dry_run_started") }).stringify()
    @cognition.GenerativeUiTransition::ApplyStarted =>
      Json::object({ "kind": Json::string("apply_started") }).stringify()
    @cognition.GenerativeUiTransition::Committed(revision~) =>
      Json::object({
        "kind": Json::string("committed"),
        "revision": Json::number(revision.to_int().to_double()),
      }).stringify()
    @cognition.GenerativeUiTransition::Cancelled =>
      Json::object({ "kind": Json::string("cancelled") }).stringify()
    @cognition.GenerativeUiTransition::Rejected(reason~) =>
      Json::object({
        "kind": Json::string("rejected"),
        "reason": Json::string(async_rejection_code(reason)),
      }).stringify()
    @cognition.GenerativeUiTransition::Failed(reason~) =>
      Json::object({
        "kind": Json::string("failed"),
        "reason": Json::string(async_rejection_code(reason)),
      }).stringify()
    @cognition.GenerativeUiTransition::Ignored(reason~) =>
      Json::object({
        "kind": Json::string("ignored"),
        "reason": Json::string(async_ignore_code(reason)),
      }).stringify()
  }
}

///|
fn async_error_json(code : String, message : String) -> String {
  Json::object({
    "kind": Json::string("provider_failed"),
    "code": Json::string(code),
    "reason": Json::string(message),
  }).stringify()
}

///|
fn async_aborted_json() -> String {
  Json::object({ "kind": Json::string("aborted") }).stringify()
}

///|
fn async_unexpected_provider_json(message : String) -> String {
  Json::object({
    "kind": Json::string("provider_failed"),
    "code": Json::string("unexpected_rejection"),
    "reason": Json::string(message),
  }).stringify()
}

///|
fn async_invalid_driver_json(message : String) -> String {
  Json::object({
    "kind": Json::string("driver_error"),
    "reason": Json::string(message),
  }).stringify()
}

///|
fn async_rejection_code(reason : @cognition.GenerativeUiRejection) -> String {
  match reason {
    @cognition.GenerativeUiRejection::InvalidSequence(..) => "invalid_sequence"
    @cognition.GenerativeUiRejection::SequenceGap(..) => "sequence_gap"
    @cognition.GenerativeUiRejection::ConflictingDuplicate(..) =>
      "conflicting_duplicate"
    @cognition.GenerativeUiRejection::InputLimitExceeded(..) =>
      "input_limit_exceeded"
    @cognition.GenerativeUiRejection::UnexpectedFinalPayload =>
      "unexpected_final_payload"
    @cognition.GenerativeUiRejection::BaseRevisionMismatch(..) =>
      "base_revision_mismatch"
    @cognition.GenerativeUiRejection::InvalidCandidate(..) =>
      "invalid_candidate"
    @cognition.GenerativeUiRejection::DryRunFailed(..) => "dry_run_failed"
    @cognition.GenerativeUiRejection::ApplyFailed(..) => "apply_failed"
    @cognition.GenerativeUiRejection::ApplyRevisionMismatch(..) =>
      "apply_revision_mismatch"
  }
}

///|
fn async_ignore_code(reason : @cognition.GenerativeUiIgnoreReason) -> String {
  match reason {
    @cognition.GenerativeUiIgnoreReason::StaleGeneration => "stale_generation"
    @cognition.GenerativeUiIgnoreReason::TerminalState => "terminal_state"
    @cognition.GenerativeUiIgnoreReason::EventNotAcceptedInPhase =>
      "event_not_accepted_in_phase"
    @cognition.GenerativeUiIgnoreReason::CancellationTooLate =>
      "cancellation_too_late"
  }
}

///|
fn async_new_pending(
  generation_id : @cognition.GenerativeUiGenerationId,
  base_revision : @cognition.GenerativeUiRevision,
  sequence : Int,
  kind : AsyncPendingKind,
) -> AsyncPending {
  let controller = @js_async.AbortController::new()
  let deferred = async_transport_deferred(controller.signal())
  let promise : @js_async.Promise[String] = deferred.get("promise").cast()
  AsyncPending(
    generation_id, base_revision, sequence, kind, deferred, promise, controller,
  )
}

///|

///|

///|
fn async_current_generation(
  driver : GenerativeUiAsyncDriver,
) -> @cognition.GenerativeUiGenerationId {
  driver.generation_id
}

///|
fn async_start_driver(
  session_handle : Int,
  base_revision : Int,
) -> (GenerativeUiAsyncDriver, @cognition.GenerativeUiTransition) {
  let revision = @cognition.GenerativeUiRevision::GenerativeUiRevision(
    base_revision,
  )
  let lifecycle = @cognition.GenerativeUiLifecycle::GenerativeUiLifecycle()
  let transition = lifecycle.dispatch(
    @cognition.GenerativeUiEvent::Start(base_revision=revision),
  )
  let generation_id = match transition {
    @cognition.GenerativeUiTransition::Started(generation_id~) => generation_id
    _ => abort("async lifecycle did not start")
  }
  let generation_ids : Map[Int, @cognition.GenerativeUiGenerationId] = Map([])
  generation_ids[generation_id.to_int()] = generation_id
  let driver = GenerativeUiAsyncDriver(
    session_handle,
    lifecycle,
    generation_id,
    generation_ids,
    revision,
    0,
    @queue.Queue([]),
    None,
    [],
    0,
    false,
    false,
  )
  (driver, transition)
}

///|
pub fn __jsx_async_driver_new(
  session_handle : Int,
  base_revision : Int,
) -> String {
  let (driver, transition) = async_start_driver(session_handle, base_revision)
  let handle = next_async_driver_handle.val
  next_async_driver_handle.val += 1
  async_driver_registry[handle] = driver
  let generation_id = match transition {
    @cognition.GenerativeUiTransition::Started(generation_id~) =>
      generation_id.to_int()
    _ => 0
  }
  Json::object({
    "driver_handle": Json::number(handle.to_double()),
    "generation_id": Json::number(generation_id.to_double()),
    "revision": Json::number(base_revision.to_double()),
  }).stringify()
}

///|
pub fn __jsx_async_driver_start(handle : Int) -> String {
  match async_driver_registry.get(handle) {
    Some(driver) =>
      Json::object({
        "kind": Json::string("started"),
        "generation_id": Json::number(driver.generation_id.to_int().to_double()),
      }).stringify()
    None => async_invalid_driver_json("async driver handle is unavailable")
  }
}

///|
pub fn __jsx_async_driver_queue_chunk(
  handle : Int,
  generation_id : Int,
  base_revision : Int,
  sequence : Int,
  payload : String,
) -> Unit {
  match async_driver_registry.get(handle) {
    Some(driver) => {
      guard driver.generation_ids.get(generation_id) is Some(id) else { return }
      let pending = async_new_pending(
        id,
        @cognition.GenerativeUiRevision::GenerativeUiRevision(base_revision),
        sequence,
        AsyncPendingKind::Chunk(payload~),
      )
      driver.pending.push(pending)
      if generation_id == driver.generation_id.to_int() &&
        sequence >= driver.next_sequence {
        driver.next_sequence = sequence + 1
      }
    }
    None => ()
  }
}

///|
pub fn __jsx_async_driver_queue_final(
  handle : Int,
  generation_id : Int,
  base_revision : Int,
  sequence : Int,
) -> Unit {
  match async_driver_registry.get(handle) {
    Some(driver) => {
      guard driver.generation_ids.get(generation_id) is Some(id) else { return }
      let pending = async_new_pending(
        id,
        @cognition.GenerativeUiRevision::GenerativeUiRevision(base_revision),
        sequence,
        AsyncPendingKind::Final,
      )
      driver.pending.push(pending)
    }
    None => ()
  }
}

///|
pub fn __jsx_async_driver_queue_failure(
  handle : Int,
  generation_id : Int,
  base_revision : Int,
  sequence : Int,
  code : String,
  message : String,
) -> Unit {
  match async_driver_registry.get(handle) {
    Some(driver) => {
      guard driver.generation_ids.get(generation_id) is Some(id) else { return }
      let pending = async_new_pending(
        id,
        @cognition.GenerativeUiRevision::GenerativeUiRevision(base_revision),
        sequence,
        AsyncPendingKind::Failure(code~, message~),
      )
      driver.pending.push(pending)
    }
    None => ()
  }
}

///|
fn async_take_pending(driver : GenerativeUiAsyncDriver) -> AsyncPending? {
  driver.pending.pop()
}

///|
fn async_cancel_generation(
  driver : GenerativeUiAsyncDriver,
  generation_id : @cognition.GenerativeUiGenerationId,
  base_revision : @cognition.GenerativeUiRevision,
  sequence : Int,
) -> Unit {
  let input = @cognition.GenerativeUiInput::cancel(
    generation_id~,
    base_revision~,
    sequence~,
  )
  let _ = driver.lifecycle.dispatch(@cognition.GenerativeUiEvent::Input(input))
}

///|
fn async_dispatch_pending(
  driver : GenerativeUiAsyncDriver,
  pending : AsyncPending,
) -> String {
  guard !driver.disposed else {
    return async_invalid_driver_json("async driver is disposed")
  }
  match pending.kind {
    AsyncPendingKind::Chunk(payload~) => {
      let input = @cognition.GenerativeUiInput::chunk(
        generation_id=pending.generation_id,
        base_revision=pending.base_revision,
        sequence=pending.sequence,
        payload~,
      )
      async_transition_json(
        driver.lifecycle.dispatch(@cognition.GenerativeUiEvent::Input(input)),
      )
    }
    AsyncPendingKind::Final => {
      let input = @cognition.GenerativeUiInput::finalize(
        generation_id=pending.generation_id,
        base_revision=pending.base_revision,
        sequence=pending.sequence,
      )
      async_transition_json(
        driver.lifecycle.dispatch(@cognition.GenerativeUiEvent::Input(input)),
      )
    }
    AsyncPendingKind::Failure(code~, message~) => {
      async_cancel_generation(
        driver,
        pending.generation_id,
        pending.base_revision,
        pending.sequence,
      )
      async_error_json(code, message)
    }
  }
}

///|
fn async_clear_current_if_same(
  driver : GenerativeUiAsyncDriver,
  pending : AsyncPending,
) -> Unit {
  match driver.current_pending {
    Some(current) =>
      if async_transport_is_same(current.deferred, pending.deferred) {
        driver.current_pending = None
      }
    None => ()
  }
}

///|
pub fn __jsx_async_driver_wait_next(handle : Int) -> @js_async.Promise[String] {
  match async_driver_registry.get(handle) {
    None =>
      @js_async.Promise::from_async(fn() {
        async_invalid_driver_json("async driver handle is unavailable")
      })
    Some(driver) => {
      guard driver.current_pending is None else {
        return @js_async.Promise::from_async(fn() {
          async_invalid_driver_json("async driver wait already pending")
        })
      }
      guard async_take_pending(driver) is Some(pending) else {
        return @js_async.Promise::from_async(fn() {
          async_invalid_driver_json("async driver queue is empty")
        })
      }
      driver.current_pending = Some(pending)
      @js_async.Promise::from_async(async fn() {
        let _raw = pending.promise.wait(abort_controller=pending.controller)
        let result = async_dispatch_pending(driver, pending)
        async_clear_current_if_same(driver, pending)
        result
      })
    }
  }
}

///|
fn async_resolve_current(driver : GenerativeUiAsyncDriver) -> Unit {
  match driver.current_pending {
    Some(pending) =>
      match pending.status {
        AsyncPendingStatus::Open => {
          pending.status = AsyncPendingStatus::Settled
          async_transport_resolve(pending.deferred, "ready")
        }
        AsyncPendingStatus::Settled => ()
        AsyncPendingStatus::Aborted => ()
      }
    None => ()
  }
}

///|
pub fn __jsx_async_driver_resolve_current(handle : Int) -> Unit {
  match async_driver_registry.get(handle) {
    Some(driver) => async_resolve_current(driver)
    None => ()
  }
}

///|
pub fn __jsx_async_driver_resolve_next(
  handle : Int,
) -> @js_async.Promise[String] {
  match async_driver_registry.get(handle) {
    None =>
      @js_async.Promise::from_async(fn() {
        async_invalid_driver_json("async driver handle is unavailable")
      })
    Some(driver) => {
      guard driver.current_pending is None else {
        return @js_async.Promise::from_async(fn() {
          async_invalid_driver_json("async driver wait already pending")
        })
      }
      guard async_take_pending(driver) is Some(pending) else {
        return @js_async.Promise::from_async(fn() {
          async_invalid_driver_json("async driver queue is empty")
        })
      }
      driver.current_pending = Some(pending)
      pending.status = AsyncPendingStatus::Settled
      async_transport_resolve(pending.deferred, "ready")
      @js_async.Promise::from_async(async fn() {
        let _raw = pending.promise.wait(abort_controller=pending.controller)
        let result = async_dispatch_pending(driver, pending)
        async_clear_current_if_same(driver, pending)
        result
      })
    }
  }
}

///|
fn async_abort_current(driver : GenerativeUiAsyncDriver) -> Bool {
  match driver.current_pending {
    Some(pending) =>
      match pending.status {
        AsyncPendingStatus::Open => {
          pending.status = AsyncPendingStatus::Aborted
          driver.current_pending = None
          pending.controller.abort()

          true
        }
        AsyncPendingStatus::Settled => {
          driver.current_pending = None
          false
        }
        AsyncPendingStatus::Aborted => {
          driver.current_pending = None
          false
        }
      }
    None => false
  }
}

///|
pub fn __jsx_async_driver_cancel(handle : Int) -> String {
  match async_driver_registry.get(handle) {
    None => async_invalid_driver_json("async driver handle is unavailable")
    Some(driver) => {
      let input = @cognition.GenerativeUiInput::cancel(
        generation_id=async_current_generation(driver),
        base_revision=driver.base_revision,
        sequence=driver.next_sequence,
      )
      let transition = driver.lifecycle.dispatch(
        @cognition.GenerativeUiEvent::Input(input),
      )
      if async_abort_current(driver) {
        driver.abort_observed = true
      }
      async_transition_json(transition)
    }
  }
}

///|
pub fn __jsx_async_driver_restart(handle : Int, base_revision : Int) -> String {
  match async_driver_registry.get(handle) {
    None => async_invalid_driver_json("async driver handle is unavailable")
    Some(driver) => {
      let revision = @cognition.GenerativeUiRevision::GenerativeUiRevision(
        base_revision,
      )
      if async_abort_current(driver) {
        driver.abort_observed = true
      }
      let transition = driver.lifecycle.restart(revision)
      match transition {
        @cognition.GenerativeUiTransition::Started(generation_id~) => {
          driver.generation_id = generation_id
          driver.generation_ids[generation_id.to_int()] = generation_id
          driver.base_revision = revision
          driver.current_pending = None
          driver.next_sequence = 0
          Json::object({
            "kind": Json::string("started"),
            "generation_id": Json::number(generation_id.to_int().to_double()),
          }).stringify()
        }
        other => async_transition_json(other)
      }
    }
  }
}

///|
pub fn __jsx_async_driver_commit(
  handle : Int,
  capabilities_json : String,
) -> String {
  match async_driver_registry.get(handle) {
    None => async_invalid_driver_json("async driver handle is unavailable")
    Some(driver) => {
      let session = match session_registry.get(driver.session_handle) {
        Some(session) => session
        None =>
          return async_invalid_driver_json("JSX session handle is unavailable")
      }
      let result = commit_candidate_with_lifecycle(
        session,
        driver.session_handle,
        driver.base_revision,
        driver.lifecycle,
        driver.generation_id,
        capabilities_json,
      )
      let parsed = @json.parse(result) catch {
        _ => return async_invalid_driver_json("session returned invalid JSON")
      }
      let session_result : SessionResultJson = @json.from_json(parsed) catch {
        _ =>
          return async_invalid_driver_json(
            "session returned invalid JSON shape",
          )
      }
      if session_result.success {
        driver.commit_count += 1
      }
      result
    }
  }
}

///|
pub fn __jsx_async_driver_stats(handle : Int) -> String {
  match async_driver_registry.get(handle) {
    None => async_invalid_driver_json("async driver handle is unavailable")
    Some(driver) =>
      Json::object({
        "abort_observed": Json::boolean(driver.abort_observed),
        "commit_count": Json::number(driver.commit_count.to_double()),
      }).stringify()
  }
}

///|
pub fn __jsx_async_driver_dispose(handle : Int) -> Unit {
  match async_driver_registry.get(handle) {
    Some(driver) => {
      driver.disposed = true
      let _ = async_abort_current(driver)
      for provider_handle in driver.provider_handles {
        match async_provider_registry.get(provider_handle) {
          Some(provider) =>
            match provider.status {
              AsyncProviderStatus::Open => {
                provider.status = AsyncProviderStatus::Aborted
                provider.provider_controller.abort()
              }
              _ => ()
            }
          None => ()
        }
        async_provider_registry.remove(provider_handle)
      }
      async_driver_registry.remove(handle)
    }
    None => ()
  }
}

///|
fn async_provider_outcome(
  driver : GenerativeUiAsyncDriver,
  pending : AsyncProviderPending,
) -> String {
  match pending.status {
    AsyncProviderStatus::Resolved(payload~) => {
      let input = @cognition.GenerativeUiInput::chunk(
        generation_id=pending.generation_id,
        base_revision=pending.base_revision,
        sequence=pending.sequence,
        payload~,
      )
      async_transition_json(
        driver.lifecycle.dispatch(@cognition.GenerativeUiEvent::Input(input)),
      )
    }
    AsyncProviderStatus::Rejected(..) =>
      async_unexpected_provider_json(
        "provider rejection bypassed Promise::wait catch",
      )
    AsyncProviderStatus::Aborted => async_aborted_json()
    AsyncProviderStatus::Open =>
      async_unexpected_provider_json("provider outcome was not settled")
  }
}

///|
pub fn __jsx_async_driver_provider_new(
  driver_handle : Int,
  generation_id : Int,
  base_revision : Int,
  sequence : Int,
) -> String {
  match async_driver_registry.get(driver_handle) {
    None => async_invalid_driver_json("async driver handle is unavailable")
    Some(driver) => {
      guard driver.generation_ids.get(generation_id) is Some(id) else {
        return async_invalid_driver_json("async generation is unavailable")
      }
      let provider_controller = @js_async.AbortController::new()
      let provider = async_transport_deferred(provider_controller.signal())
      let promise : @js_async.Promise[String] = provider.get("promise").cast()
      let handle = next_async_provider_handle.val
      next_async_provider_handle.val += 1
      async_provider_registry[handle] = AsyncProviderPending(
        driver_handle,
        id,
        @cognition.GenerativeUiRevision::GenerativeUiRevision(base_revision),
        sequence,
        provider,
        promise,
        provider_controller,
      )
      driver.provider_handles.push(handle)
      Json::object({ "provider_handle": Json::number(handle.to_double()) }).stringify()
    }
  }
}

///|
pub fn __jsx_async_driver_provider_wait(
  provider_handle : Int,
) -> @js_async.Promise[String] {
  match async_provider_registry.get(provider_handle) {
    None =>
      @js_async.Promise::from_async(fn() {
        async_invalid_driver_json("provider handle is unavailable")
      })
    Some(pending) =>
      @js_async.Promise::from_async(async fn() {
        let _raw = pending.promise.wait(
          abort_controller=pending.provider_controller,
        ) catch {
          _ =>
            match pending.status {
              AsyncProviderStatus::Aborted => return async_aborted_json()
              AsyncProviderStatus::Rejected(code~, message~) => {
                match async_driver_registry.get(pending.driver_handle) {
                  Some(driver) =>
                    async_cancel_generation(
                      driver,
                      pending.generation_id,
                      pending.base_revision,
                      pending.sequence,
                    )
                  None => ()
                }
                return async_error_json(code, message)
              }
              _ =>
                return async_unexpected_provider_json(
                  "provider promise rejected",
                )
            }
        }
        match async_driver_registry.get(pending.driver_handle) {
          Some(driver) => async_provider_outcome(driver, pending)
          None =>
            async_invalid_driver_json("async driver handle is unavailable")
        }
      })
  }
}

///|
pub fn __jsx_async_driver_provider_resolve(
  provider_handle : Int,
  payload : String,
) -> Unit {
  match async_provider_registry.get(provider_handle) {
    Some(pending) =>
      match pending.status {
        AsyncProviderStatus::Open => {
          pending.status = AsyncProviderStatus::Resolved(payload~)
          async_provider_resolve(pending.provider, payload)
        }
        _ => ()
      }
    None => ()
  }
}

///|
pub fn __jsx_async_driver_provider_reject(
  provider_handle : Int,
  code : String,
  message : String,
) -> Unit {
  match async_provider_registry.get(provider_handle) {
    Some(pending) =>
      match pending.status {
        AsyncProviderStatus::Open => {
          pending.status = AsyncProviderStatus::Rejected(code~, message~)
          async_provider_reject(pending.provider, code, message)
        }
        _ => ()
      }
    None => ()
  }
}

///|
pub fn __jsx_async_driver_provider_abort(provider_handle : Int) -> Unit {
  match async_provider_registry.get(provider_handle) {
    Some(pending) =>
      match pending.status {
        AsyncProviderStatus::Open => {
          pending.status = AsyncProviderStatus::Aborted
          pending.provider_controller.abort()
          match async_driver_registry.get(pending.driver_handle) {
            Some(driver) => driver.abort_observed = true
            None => ()
          }
        }
        _ => ()
      }
    None => ()
  }
}
