///|
fn provider_boundary_completion_for_test(
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
fn provider_boundary_summary_for_test(
  store : CognitionStore,
  key : CognitionKey,
) -> String raise {
  match store.get_value(key) {
    Some(Summary(summary)) => summary
    _ => fail("expected summary")
  }
}

///|
test "provider request planning records pending descriptor and reuses clean id" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let _ = store.set_input(FileText("src/b.mbt"), Text("beta"))
  let target = CognitionKey::PackedContext("explain alpha", 2)
  let items = store.pack_context("explain alpha", 2)

  let request = store.plan_provider_request(
    target~,
    options=provider_boundary_options_for_test(),
  )
  let repeated = store.plan_provider_request(
    target~,
    options=provider_boundary_options_for_test(),
  )

  inspect(request.id() == repeated.id(), content="true")
  inspect(request.target() == target, content="true")
  inspect(request.context().length(), content="2")
  inspect(request.context().length() == items.length(), content="true")
  inspect(request.dependencies().contains(RepoSummary), content="true")
  inspect(request.source_revisions().length() > 0, content="true")
  inspect(
    request.dependency_fingerprint().to_string().contains("RepoSummary@"),
    content="true",
  )
  match store.get_provider_request(request.id()) {
    Some(stored) => inspect(stored == request, content="true")
    None => fail("expected stored request")
  }
  match store.get_provider_status(request.id()) {
    Some(status) => {
      inspect(status.request_id() == request.id(), content="true")
      inspect(status.target() == target, content="true")
      inspect(status.status() == ProviderRequestStatus::Pending, content="true")
      inspect(
        status.classification() == ProviderStatusClassification::InFlight,
        content="true",
      )
    }
    None => fail("expected provider status")
  }
}

///|
test "provider request re-planning resets failed status to pending" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_boundary_options_for_test(),
  )

  let failed = store.complete_provider_request(
    provider_boundary_completion_for_test(
      request,
      ProviderResult::Failed(ProviderError::Timeout),
    ),
  )
  inspect(
    failed.status() == ProviderRequestStatus::Failed(ProviderError::Timeout),
    content="true",
  )

  let repeated = store.plan_provider_request(
    target~,
    options=provider_boundary_options_for_test(),
  )
  inspect(repeated.id() == request.id(), content="true")
  match store.get_provider_status(request.id()) {
    Some(status) =>
      inspect(status.status() == ProviderRequestStatus::Pending, content="true")
    None => fail("expected provider status")
  }

  let retry_status = store.complete_provider_request(
    provider_boundary_completion_for_test(
      repeated,
      ProviderResult::Succeeded(Summary("retry summary")),
    ),
  )
  inspect(
    retry_status.status() == ProviderRequestStatus::Succeeded,
    content="true",
  )
  inspect(
    provider_boundary_summary_for_test(store, target),
    content="retry summary",
  )
}

///|
test "provider request planning does not recompute dirty file summary target" {
  let file_calls = Ref(0)
  let provider : CognitionProvider = {
    file_summary: fn(path, text) {
      file_calls.val += 1
      "sync \{path}: \{text.length()}"
    },
    repo_summary: fn(items) { "repo: " + items.join(",") },
  }
  let store = CognitionStore::new_with_provider(provider)
  let target = CognitionKey::FileSummary("src/a.mbt")
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let _ = store.compute(target)
  inspect(file_calls.val, content="1")
  inspect(
    provider_boundary_summary_for_test(store, target),
    content="sync src/a.mbt: 5",
  )

  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha changed"))
  inspect(store.is_dirty(target), content="true")
  let request = store.plan_provider_request(
    target~,
    options=provider_boundary_options_for_test(),
  )

  inspect(file_calls.val, content="1")
  inspect(store.is_dirty(target), content="true")
  inspect(
    request.dependencies().contains(FileText("src/a.mbt")),
    content="true",
  )
  inspect(
    provider_boundary_summary_for_test(store, target),
    content="sync src/a.mbt: 5",
  )

  let status = store.complete_provider_request(
    provider_boundary_completion_for_test(
      request,
      ProviderResult::Succeeded(Summary("external summary")),
    ),
  )
  inspect(status.status() == ProviderRequestStatus::Succeeded, content="true")
  inspect(store.is_dirty(target), content="false")
  inspect(
    provider_boundary_summary_for_test(store, target),
    content="external summary",
  )
}

///|
test "provider completion accepts matching success and stores artifact" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let _ = store.compute(FileSummary("src/a.mbt"))
  let request = store.plan_provider_request(
    target=FileSummary("src/a.mbt"),
    options=provider_boundary_options_for_test(),
  )
  let completion = provider_boundary_completion_for_test(
    request,
    ProviderResult::Succeeded(Summary("provider summary")),
  )

  let status = store.complete_provider_request(completion)

  inspect(status.status() == ProviderRequestStatus::Succeeded, content="true")
  inspect(
    provider_boundary_summary_for_test(store, FileSummary("src/a.mbt")),
    content="provider summary",
  )
  match store.get_provider_result(request.id()) {
    Some(result) =>
      inspect(
        result.status() == ProviderRequestStatus::Succeeded,
        content="true",
      )
    None => fail("expected completion record")
  }
  match store.get_provider_status(request.id()) {
    Some(stored) =>
      inspect(
        stored.status() == ProviderRequestStatus::Succeeded,
        content="true",
      )
    None => fail("expected provider status")
  }
}

///|
test "provider completion rejects value type that does not match target" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let _ = store.compute(FileSummary("src/a.mbt"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let before = provider_boundary_summary_for_test(store, target)
  let request = store.plan_provider_request(
    target~,
    options=provider_boundary_options_for_test(),
  )

  let status = store.complete_provider_request(
    provider_boundary_completion_for_test(
      request,
      ProviderResult::Succeeded(Text("not a summary")),
    ),
  )

  inspect(
    status.status() ==
    ProviderRequestStatus::Failed(
      ProviderError::InvalidRequest(message="result value type mismatch"),
    ),
    content="true",
  )
  inspect(provider_boundary_summary_for_test(store, target), content=before)
}

///|
test "provider cancellation preserves last clean artifact and blocks completion" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let _ = store.compute(FileSummary("src/a.mbt"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let before = provider_boundary_summary_for_test(store, target)
  let request = store.plan_provider_request(
    target~,
    options=provider_boundary_options_for_test(),
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
  let late_completion = provider_boundary_completion_for_test(
    request,
    ProviderResult::Succeeded(Summary("late provider summary")),
  )
  let late_status = store.complete_provider_request(late_completion)

  inspect(
    late_status.status() ==
    ProviderRequestStatus::Failed(ProviderError::Cancelled),
    content="true",
  )
  inspect(provider_boundary_summary_for_test(store, target), content=before)
}

///|
test "provider cancellation after success leaves terminal result intact" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let _ = store.compute(FileSummary("src/a.mbt"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_boundary_options_for_test(),
  )
  let complete_status = store.complete_provider_request(
    provider_boundary_completion_for_test(
      request,
      ProviderResult::Succeeded(Summary("provider summary")),
    ),
  )
  inspect(
    complete_status.status() == ProviderRequestStatus::Succeeded,
    content="true",
  )

  match store.cancel_provider_request(request.id()) {
    Some(status) =>
      inspect(
        status.status() == ProviderRequestStatus::Succeeded,
        content="true",
      )
    None => fail("expected cancellation status")
  }
  inspect(
    provider_boundary_summary_for_test(store, target),
    content="provider summary",
  )
  match store.get_provider_result(request.id()) {
    Some(result) =>
      inspect(
        result.status() == ProviderRequestStatus::Succeeded,
        content="true",
      )
    None => fail("expected completion record")
  }
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
test "provider completion rejects stale source revisions after edit" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let _ = store.compute(FileSummary("src/a.mbt"))
  let target = CognitionKey::FileSummary("src/a.mbt")
  let before = provider_boundary_summary_for_test(store, target)
  let request = store.plan_provider_request(
    target~,
    options=provider_boundary_options_for_test(),
  )
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha changed"))

  let status = store.complete_provider_request(
    provider_boundary_completion_for_test(
      request,
      ProviderResult::Succeeded(Summary("stale provider summary")),
    ),
  )

  inspect(
    status.status() ==
    ProviderRequestStatus::Failed(ProviderError::StaleCompletion),
    content="true",
  )
  inspect(provider_boundary_summary_for_test(store, target), content=before)
  match store.get_provider_result(request.id()) {
    Some(result) =>
      inspect(
        result.status() ==
        ProviderRequestStatus::Failed(ProviderError::StaleCompletion),
        content="true",
      )
    None => fail("expected stale completion record")
  }
}

///|
test "provider completion for input target avoids self dependency" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let target = CognitionKey::FileText("src/a.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_boundary_options_for_test(),
  )

  let status = store.complete_provider_request(
    provider_boundary_completion_for_test(
      request,
      ProviderResult::Succeeded(Text("provider text")),
    ),
  )

  inspect(status.status() == ProviderRequestStatus::Succeeded, content="true")
  inspect(store.is_dirty(target), content="false")
  inspect(store.dependencies_of(target).contains(target), content="false")
  match store.get_value(target) {
    Some(Text(text)) => inspect(text, content="provider text")
    _ => fail("expected provider text")
  }
}

///|
test "provider completion for new FileText registers workspace input" {
  let store = CognitionStore::new()
  let target = CognitionKey::FileText("generated.mbt")
  let request = store.plan_provider_request(
    target~,
    options=provider_boundary_options_for_test(),
  )

  let status = store.complete_provider_request(
    provider_boundary_completion_for_test(
      request,
      ProviderResult::Succeeded(Text("let generated = 1")),
    ),
  )

  inspect(status.status() == ProviderRequestStatus::Succeeded, content="true")
  inspect(store.known_files().contains("generated.mbt"), content="true")
  match store.get_value(target) {
    Some(Text(text)) => inspect(text, content="let generated = 1")
    _ => fail("expected provider text")
  }
  match store.compute(RepoSummary) {
    Some(Summary(summary)) =>
      inspect(summary.contains("generated.mbt:"), content="true")
    _ => fail("expected repo summary")
  }
}

///|
test "provider completion validates option provenance" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let request = store.plan_provider_request(
    target=FileSummary("src/a.mbt"),
    options=provider_boundary_options_for_test(),
  )
  let bad_options = ProviderOptionProvenance::new(
    task_kind="summarize",
    provider_id="mock-provider",
    model_id="other-model",
    option_identity=RedactedOptionIdentity::new(
      "temperature=<redacted>;max=128",
    ),
  )
  let completion = ProviderResultDescriptor::new(
    request_id=request.id(),
    target=request.target(),
    options=bad_options,
    source_revisions=request.source_revisions(),
    dependency_fingerprint=request.dependency_fingerprint(),
    result=ProviderResult::Succeeded(Summary("wrong options")),
  )

  let status = store.complete_provider_request(completion)

  inspect(
    status.status() ==
    ProviderRequestStatus::Failed(ProviderError::StaleCompletion),
    content="true",
  )
}

///|
test "provider completion validates dependency fingerprint" {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  let request = store.plan_provider_request(
    target=FileSummary("src/a.mbt"),
    options=provider_boundary_options_for_test(),
  )
  let completion = ProviderResultDescriptor::new(
    request_id=request.id(),
    target=request.target(),
    options=request.options(),
    source_revisions=request.source_revisions(),
    dependency_fingerprint=ProviderDependencyFingerprint::new("bad"),
    result=ProviderResult::Succeeded(Summary("bad fingerprint")),
  )

  let status = store.complete_provider_request(completion)

  inspect(
    status.status() ==
    ProviderRequestStatus::Failed(ProviderError::StaleCompletion),
    content="true",
  )
}
