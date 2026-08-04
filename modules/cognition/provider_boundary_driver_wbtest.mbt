///|
priv struct ScriptedProviderResponse {
  request_id : ProviderRequestId
  result : ProviderResult
}

///|
fn ScriptedProviderResponse::ScriptedProviderResponse(
  request_id~ : ProviderRequestId,
  result~ : ProviderResult,
) -> ScriptedProviderResponse {
  { request_id, result: result.copy_result() }
}

///|
priv struct ScriptedProviderDriver {
  store : CognitionStore
  mut responses : Array[ScriptedProviderResponse]
  started : Array[ProviderRequestId]
  cancelled : Array[ProviderRequestId]
  mut now_ms : Int
  mut shutdown : Bool
}

///|
fn ScriptedProviderDriver::ScriptedProviderDriver(
  store : CognitionStore,
) -> ScriptedProviderDriver {
  {
    store,
    responses: [],
    started: [],
    cancelled: [],
    now_ms: 0,
    shutdown: false,
  }
}

///|
fn ScriptedProviderDriver::enqueue(
  self : ScriptedProviderDriver,
  request : ProviderRequestDescriptor,
  result : ProviderResult,
) -> Unit {
  self.responses.push(
    ScriptedProviderResponse::ScriptedProviderResponse(
      request_id=request.id(),
      result~,
    ),
  )
}

///|
fn ScriptedProviderDriver::shutdown(self : ScriptedProviderDriver) -> Unit {
  self.shutdown = true
}

///|
fn ScriptedProviderDriver::set_fake_time_ms(
  self : ScriptedProviderDriver,
  now_ms : Int,
) -> Unit {
  self.now_ms = now_ms
}

///|
fn ScriptedProviderDriver::step(self : ScriptedProviderDriver) -> Bool {
  if self.shutdown {
    false
  } else {
    match self.store.reactive.provider_next_driver_action_at(self.now_ms) {
      ProviderDriverAction::StartProviderRequest(request) =>
        self.complete_next_response(request)
      ProviderDriverAction::RetryProviderRequest(request) =>
        self.retry_next_response(request)
      ProviderDriverAction::CancelProviderRequest(request_id) => {
        if !self.cancelled.contains(request_id) {
          self.cancelled.push(request_id)
        }
        self.store.reactive.acknowledge_provider_cancellation(request_id)
        false
      }
      ProviderDriverAction::WaitProviderRetry(_, _) => false
      ProviderDriverAction::NoDriverAction => false
    }
  }
}

///|
fn ScriptedProviderDriver::retry_next_response(
  self : ScriptedProviderDriver,
  request : ProviderRequestDescriptor,
) -> Bool {
  let replanned = self.store.plan_provider_request(
    target=request.target(),
    options=request.options(),
  )
  self.complete_next_response(replanned)
}

///|
fn ScriptedProviderDriver::complete_next_response(
  self : ScriptedProviderDriver,
  request : ProviderRequestDescriptor,
) -> Bool {
  self.started.push(request.id())
  self.store.reactive.acknowledge_provider_start(request.id())
  match self.take_response(request.id()) {
    Some(result) => {
      let _ = self.store.complete_provider_request(
        provider_driver_completion_for_test(request, result),
      )
      true
    }
    None => false
  }
}

///|
fn ScriptedProviderDriver::take_response(
  self : ScriptedProviderDriver,
  request_id : ProviderRequestId,
) -> ProviderResult? {
  let mut selected : ProviderResult? = None
  let remaining : Array[ScriptedProviderResponse] = []
  for response in self.responses {
    if selected is None && response.request_id == request_id {
      selected = Some(response.result.copy_result())
    } else {
      remaining.push(response)
    }
  }
  self.responses = remaining
  selected
}

///|
fn provider_driver_options_for_test() -> ProviderOptionProvenance {
  ProviderOptionProvenance::new(
    task_kind="summarize",
    provider_id="scripted-provider",
    model_id="scripted-model",
    option_identity=RedactedOptionIdentity::new(
      "temperature=<redacted>;max=128",
    ),
  )
}

///|
fn provider_driver_completion_for_test(
  request : ProviderRequestDescriptor,
  result : ProviderResult,
) -> ProviderResultDescriptor {
  ProviderResultDescriptor::new(
    request_id=request.id(),
    target=request.target(),
    options=request.options(),
    source_revisions=request.source_revisions(),
    dependency_fingerprint=request.dependency_fingerprint(),
    result~,
  )
}

///|
fn provider_driver_summary_for_test(
  store : CognitionStore,
  key : CognitionKey,
) -> String raise {
  match store.get_value(key) {
    Some(Summary(summary)) => summary
    _ => fail("expected summary")
  }
}

///|
test "scripted provider driver completes planned success without network" {
  let store = CognitionStore::new()
  let driver = ScriptedProviderDriver::ScriptedProviderDriver(store)
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_driver_options_for_test(),
  )
  driver.enqueue(request, ProviderResult::Succeeded(Summary("scripted alpha")))

  inspect(driver.step(), content="true")

  inspect(
    provider_driver_summary_for_test(store, target),
    content="scripted alpha",
  )
  match store.get_provider_status(request.id()) {
    Some(status) =>
      inspect(
        status.status() == ProviderRequestStatus::Succeeded,
        content="true",
      )
    None => fail("expected provider status")
  }
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::NoDriverAction,
    content="true",
  )
}

///|
test "scripted provider driver does not duplicate in-flight start without response" {
  let store = CognitionStore::new()
  let driver = ScriptedProviderDriver::ScriptedProviderDriver(store)
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_driver_options_for_test(),
  )

  inspect(driver.step(), content="false")
  inspect(driver.started.length(), content="1")
  inspect(driver.started[0] == request.id(), content="true")
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::NoDriverAction,
    content="true",
  )
  inspect(driver.step(), content="false")
  inspect(driver.started.length(), content="1")
}

///|
test "scripted provider driver waits under fake time then retries" {
  let store = CognitionStore::new()
  let driver = ScriptedProviderDriver::ScriptedProviderDriver(store)
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_driver_options_for_test(),
  )
  driver.set_fake_time_ms(100)
  driver.enqueue(
    request,
    ProviderResult::Failed(ProviderError::RateLimited(retry_after_ms=Some(50))),
  )
  driver.enqueue(request, ProviderResult::Succeeded(Summary("retry alpha")))

  inspect(driver.step(), content="true")
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::WaitProviderRetry(request.id(), 150),
    content="true",
  )
  inspect(driver.step(), content="false")
  driver.set_fake_time_ms(149)
  inspect(driver.step(), content="false")
  driver.set_fake_time_ms(150)
  inspect(
    store.reactive.provider_next_driver_action_at(150) ==
    ProviderDriverAction::RetryProviderRequest(request),
    content="true",
  )
  inspect(driver.step(), content="true")

  inspect(
    provider_driver_summary_for_test(store, target),
    content="retry alpha",
  )
  match store.get_provider_status(request.id()) {
    Some(status) =>
      inspect(
        status.status() == ProviderRequestStatus::Succeeded,
        content="true",
      )
    None => fail("expected provider status")
  }
}

///|
test "scripted provider driver observes cancellation without completing" {
  let store = CognitionStore::new()
  let driver = ScriptedProviderDriver::ScriptedProviderDriver(store)
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_driver_options_for_test(),
  )
  driver.enqueue(
    request,
    ProviderResult::Succeeded(Summary("should not be stored")),
  )

  let _ = store.cancel_provider_request(request.id())
  inspect(driver.step(), content="false")

  inspect(driver.cancelled.contains(request.id()), content="true")
  inspect(store.get_value(target) is None, content="true")
  match store.get_provider_status(request.id()) {
    Some(status) =>
      inspect(
        status.status() ==
        ProviderRequestStatus::Failed(ProviderError::Cancelled),
        content="true",
      )
    None => fail("expected provider status")
  }
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::NoDriverAction,
    content="true",
  )
}

///|
test "scripted provider driver cancels before starting later request" {
  let store = CognitionStore::new()
  let driver = ScriptedProviderDriver::ScriptedProviderDriver(store)
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let _ = store.set_input(FileText("src/b.mbt"), Text("beta"))
  let target_b = CognitionKey::FileSummary("src/b.mbt")
  let request_a = store.plan_provider_request(
    target=FileSummary("src/a.mbt"),
    options=provider_driver_options_for_test(),
  )
  let request_b = store.plan_provider_request(
    target=target_b,
    options=provider_driver_options_for_test(),
  )
  driver.enqueue(request_b, ProviderResult::Succeeded(Summary("scripted beta")))

  let _ = store.cancel_provider_request(request_a.id())
  inspect(driver.step(), content="false")

  inspect(driver.cancelled.contains(request_a.id()), content="true")
  inspect(store.get_value(target_b) is None, content="true")
  inspect(driver.step(), content="true")
  inspect(
    provider_driver_summary_for_test(store, target_b),
    content="scripted beta",
  )
}

///|
test "scripted provider driver shutdown leaves queued completion unapplied" {
  let store = CognitionStore::new()
  let driver = ScriptedProviderDriver::ScriptedProviderDriver(store)
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_driver_options_for_test(),
  )
  driver.enqueue(
    request,
    ProviderResult::Succeeded(Summary("should not be stored")),
  )

  driver.shutdown()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha changed"))
  inspect(driver.step(), content="false")

  inspect(store.get_value(target) is None, content="true")
  match store.get_provider_status(request.id()) {
    Some(status) =>
      inspect(status.status() == ProviderRequestStatus::Pending, content="true")
    None => fail("expected provider status")
  }
}
