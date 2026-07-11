///|
fn provider_reactive_options_for_test() -> ProviderOptionProvenance {
  ProviderOptionProvenance::new(
    task_kind="summarize",
    provider_id="mock-provider",
    model_id="mock-model",
    option_identity=RedactedOptionIdentity::new(
      "temperature=<redacted>;max=128",
    ),
  )
}

///|
fn provider_reactive_completion_for_test(
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
test "provider planning cells derive descriptor status fingerprint and start action" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_reactive_options_for_test(),
  )

  match store.reactive.provider_dependency_fingerprint() {
    Some(fingerprint) =>
      inspect(fingerprint == request.dependency_fingerprint(), content="true")
    None => fail("expected dependency fingerprint")
  }
  match store.reactive.provider_status() {
    Some(status) => {
      inspect(status.request_id() == request.id(), content="true")
      inspect(status.target() == target, content="true")
      inspect(status.status() == ProviderRequestStatus::Pending, content="true")
    }
    None => fail("expected provider status")
  }
  inspect(
    store.reactive.provider_retry_classification() is None,
    content="true",
  )
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::StartProviderRequest(request),
    content="true",
  )
}

///|
test "provider planning start acknowledgement suppresses duplicate starts" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_reactive_options_for_test(),
  )

  store.reactive.acknowledge_provider_start(request.id())

  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::NoDriverAction,
    content="true",
  )
  match store.reactive.provider_status() {
    Some(status) =>
      inspect(status.status() == ProviderRequestStatus::Pending, content="true")
    None => fail("expected pending status while request is in flight")
  }
}

///|
test "provider planning preserves start acknowledgement on pending replan" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_reactive_options_for_test(),
  )
  store.reactive.acknowledge_provider_start(request.id())

  let repeated = store.plan_provider_request(
    target~,
    options=provider_reactive_options_for_test(),
  )

  inspect(repeated.id() == request.id(), content="true")
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::NoDriverAction,
    content="true",
  )
}

///|
test "provider planning cells derive cancellation status and action" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_reactive_options_for_test(),
  )

  match store.cancel_provider_request(request.id()) {
    Some(status) =>
      inspect(
        status.status() ==
        ProviderRequestStatus::Failed(ProviderError::Cancelled),
        content="true",
      )
    None => fail("expected cancellation status")
  }

  match store.reactive.provider_status() {
    Some(status) =>
      inspect(
        status.status() ==
        ProviderRequestStatus::Failed(ProviderError::Cancelled),
        content="true",
      )
    None => fail("expected reactive cancellation status")
  }
  inspect(
    store.reactive.provider_retry_classification() ==
    Some(ProviderRetryClassification::CallerInitiated),
    content="true",
  )
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::CancelProviderRequest(request.id()),
    content="true",
  )
}

///|
test "provider planning cells use fake time for retry action" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_reactive_options_for_test(),
  )
  store.reactive.provider_planning.set_fake_time_ms(100)

  let status = store.complete_provider_request(
    provider_reactive_completion_for_test(
      request,
      ProviderResult::Failed(
        ProviderError::RateLimited(retry_after_ms=Some(250)),
      ),
    ),
  )

  inspect(
    status.status() ==
    ProviderRequestStatus::Failed(
      ProviderError::RateLimited(retry_after_ms=Some(250)),
    ),
    content="true",
  )
  inspect(
    store.reactive.provider_retry_classification() ==
    Some(ProviderRetryClassification::RetryableLater(retry_after_ms=Some(250))),
    content="true",
  )
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::WaitProviderRetry(request.id(), 350),
    content="true",
  )

  store.reactive.provider_planning.set_fake_time_ms(349)
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::WaitProviderRetry(request.id(), 350),
    content="true",
  )
  store.reactive.provider_planning.set_fake_time_ms(350)
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::RetryProviderRequest(request),
    content="true",
  )
  store.reactive.acknowledge_provider_start(request.id())
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::NoDriverAction,
    content="true",
  )
}

///|
test "provider planning preserves terminal status when replanning completed request" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let _ = store.set_input(FileText("src/b.mbt"), Text("beta"))
  let request_a = store.plan_provider_request(
    target=FileSummary("src/a.mbt"),
    options=provider_reactive_options_for_test(),
  )
  let _ = store.complete_provider_request(
    provider_reactive_completion_for_test(
      request_a,
      ProviderResult::Succeeded(Summary("alpha done")),
    ),
  )
  let request_b = store.plan_provider_request(
    target=FileSummary("src/b.mbt"),
    options=provider_reactive_options_for_test(),
  )
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::StartProviderRequest(request_b),
    content="true",
  )

  let repeated_a = store.plan_provider_request(
    target=FileSummary("src/a.mbt"),
    options=provider_reactive_options_for_test(),
  )

  inspect(repeated_a.id() == request_a.id(), content="true")
  match store.reactive.provider_status() {
    Some(status) => {
      inspect(status.request_id() == request_a.id(), content="true")
      inspect(
        status.status() == ProviderRequestStatus::Succeeded,
        content="true",
      )
    }
    None => fail("expected terminal provider status")
  }
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::StartProviderRequest(request_b),
    content="true",
  )
}

///|
test "provider planning selects oldest pending request" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let _ = store.set_input(FileText("src/b.mbt"), Text("beta"))
  let request_a = store.plan_provider_request(
    target=FileSummary("src/a.mbt"),
    options=provider_reactive_options_for_test(),
  )
  let _ = store.plan_provider_request(
    target=FileSummary("src/b.mbt"),
    options=provider_reactive_options_for_test(),
  )

  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::StartProviderRequest(request_a),
    content="true",
  )
}

///|
test "provider planning starts current pending request before stale pending start" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let stale_request = store.plan_provider_request(
    target~,
    options=provider_reactive_options_for_test(),
  )

  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha changed"))
  let current_request = store.plan_provider_request(
    target~,
    options=provider_reactive_options_for_test(),
  )
  inspect(current_request.id() != stale_request.id(), content="true")

  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::StartProviderRequest(current_request),
    content="true",
  )
}

///|
test "provider planning starts current pending request before stale ready retry" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let stale_request = store.plan_provider_request(
    target~,
    options=provider_reactive_options_for_test(),
  )
  store.reactive.provider_planning.set_fake_time_ms(100)
  let _ = store.complete_provider_request(
    provider_reactive_completion_for_test(
      stale_request,
      ProviderResult::Failed(
        ProviderError::RateLimited(retry_after_ms=Some(50)),
      ),
    ),
  )

  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha changed"))
  let current_request = store.plan_provider_request(
    target~,
    options=provider_reactive_options_for_test(),
  )
  inspect(current_request.id() != stale_request.id(), content="true")

  store.reactive.provider_planning.set_fake_time_ms(150)
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::StartProviderRequest(current_request),
    content="true",
  )
}

///|
test "provider planning waits for earliest retryable request" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let _ = store.set_input(FileText("src/b.mbt"), Text("beta"))
  let request_a = store.plan_provider_request(
    target=FileSummary("src/a.mbt"),
    options=provider_reactive_options_for_test(),
  )
  let request_b = store.plan_provider_request(
    target=FileSummary("src/b.mbt"),
    options=provider_reactive_options_for_test(),
  )
  store.reactive.provider_planning.set_fake_time_ms(0)
  let _ = store.complete_provider_request(
    provider_reactive_completion_for_test(
      request_a,
      ProviderResult::Failed(
        ProviderError::RateLimited(retry_after_ms=Some(1000)),
      ),
    ),
  )
  let _ = store.complete_provider_request(
    provider_reactive_completion_for_test(
      request_b,
      ProviderResult::Failed(
        ProviderError::RateLimited(retry_after_ms=Some(100)),
      ),
    ),
  )

  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::WaitProviderRetry(request_b.id(), 100),
    content="true",
  )
}

///|
test "provider planning ignores late completion for non-current request" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let _ = store.set_input(FileText("src/b.mbt"), Text("beta"))
  let request_a = store.plan_provider_request(
    target=FileSummary("src/a.mbt"),
    options=provider_reactive_options_for_test(),
  )
  let request_b = store.plan_provider_request(
    target=FileSummary("src/b.mbt"),
    options=provider_reactive_options_for_test(),
  )

  let _ = store.complete_provider_request(
    provider_reactive_completion_for_test(
      request_a,
      ProviderResult::Succeeded(Summary("late alpha")),
    ),
  )

  match store.reactive.provider_status() {
    Some(status) => {
      inspect(status.request_id() == request_b.id(), content="true")
      inspect(status.status() == ProviderRequestStatus::Pending, content="true")
    }
    None => fail("expected current provider status")
  }
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::StartProviderRequest(request_b),
    content="true",
  )
}

///|
test "provider planning prioritizes cancellation for non-current request" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let _ = store.set_input(FileText("src/b.mbt"), Text("beta"))
  let request_a = store.plan_provider_request(
    target=FileSummary("src/a.mbt"),
    options=provider_reactive_options_for_test(),
  )
  let request_b = store.plan_provider_request(
    target=FileSummary("src/b.mbt"),
    options=provider_reactive_options_for_test(),
  )

  let _ = store.cancel_provider_request(request_a.id())

  match store.reactive.provider_status() {
    Some(status) => {
      inspect(status.request_id() == request_b.id(), content="true")
      inspect(status.status() == ProviderRequestStatus::Pending, content="true")
    }
    None => fail("expected current provider status")
  }
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::CancelProviderRequest(request_a.id()),
    content="true",
  )
  store.reactive.acknowledge_provider_cancellation(request_a.id())
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::StartProviderRequest(request_b),
    content="true",
  )
}

///|
test "provider planning watches keep pending request cells alive across gc" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_reactive_options_for_test(),
  )

  inspect(
    store.reactive.provider_planning.watched_cells_are_rooted(),
    content="true",
  )
  store.reactive.provider_planning.runtime.gc()

  match store.reactive.provider_status() {
    Some(status) => {
      inspect(status.request_id() == request.id(), content="true")
      inspect(status.status() == ProviderRequestStatus::Pending, content="true")
    }
    None => fail("expected provider status after gc")
  }
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::StartProviderRequest(request),
    content="true",
  )
  match store.reactive.provider_dependency_fingerprint() {
    Some(fingerprint) =>
      inspect(fingerprint == request.dependency_fingerprint(), content="true")
    None => fail("expected dependency fingerprint after gc")
  }
}

///|
test "provider planning watches keep cancellation cells alive across gc" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_reactive_options_for_test(),
  )
  let _ = store.cancel_provider_request(request.id())

  inspect(
    store.reactive.provider_planning.watched_cells_are_rooted(),
    content="true",
  )
  store.reactive.provider_planning.runtime.gc()

  match store.reactive.provider_status() {
    Some(status) =>
      inspect(
        status.status() ==
        ProviderRequestStatus::Failed(ProviderError::Cancelled),
        content="true",
      )
    None => fail("expected cancellation status after gc")
  }
  inspect(
    store.reactive.provider_retry_classification() ==
    Some(ProviderRetryClassification::CallerInitiated),
    content="true",
  )
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::CancelProviderRequest(request.id()),
    content="true",
  )
}

///|
test "provider planning watches keep retry status cells alive across gc" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_reactive_options_for_test(),
  )
  store.reactive.provider_planning.set_fake_time_ms(25)
  let _ = store.complete_provider_request(
    provider_reactive_completion_for_test(
      request,
      ProviderResult::Failed(
        ProviderError::RateLimited(retry_after_ms=Some(75)),
      ),
    ),
  )

  inspect(
    store.reactive.provider_planning.watched_cells_are_rooted(),
    content="true",
  )
  store.reactive.provider_planning.runtime.gc()

  match store.reactive.provider_status() {
    Some(status) =>
      inspect(
        status.status() ==
        ProviderRequestStatus::Failed(
          ProviderError::RateLimited(retry_after_ms=Some(75)),
        ),
        content="true",
      )
    None => fail("expected retry status after gc")
  }
  inspect(
    store.reactive.provider_retry_classification() ==
    Some(ProviderRetryClassification::RetryableLater(retry_after_ms=Some(75))),
    content="true",
  )
  inspect(
    store.reactive.provider_next_driver_action() ==
    ProviderDriverAction::WaitProviderRetry(request.id(), 100),
    content="true",
  )
}
