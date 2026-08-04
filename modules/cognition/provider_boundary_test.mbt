///|
fn provider_boundary_revision_for_test() -> Revision {
  let store = CognitionStore::new()
  let _ = store.set_input(FileText("src/a.mbt"), Text("alpha"))
  store.current_revision()
}

///|
fn provider_boundary_context_item(
  path : String,
  revision : Revision,
  payload : String,
) -> ContextItem {
  {
    source: FileSummary(path),
    source_revision: revision,
    payload,
    reason: "test context",
  }
}

///|
fn provider_boundary_options_for_test() -> ProviderOptionProvenance {
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
test "provider request descriptor carries pure provenance" {
  let revision = provider_boundary_revision_for_test()
  let request_id = ProviderRequestId::new("req-1")
  let fingerprint = ProviderDependencyFingerprint::new("deps:repo,a")
  let options = provider_boundary_options_for_test()
  let context : Array[ContextItem] = [
    provider_boundary_context_item("src/a.mbt", revision, "alpha summary"),
  ]
  let source_revisions : Array[ProviderSourceSnapshot] = [
    ProviderSourceSnapshot::new(key=FileSummary("src/a.mbt"), revision~),
  ]
  let dependencies : Array[CognitionKey] = [
    RepoSummary,
    FileSummary("src/a.mbt"),
  ]

  let request = ProviderRequestDescriptor::new(
    id=request_id,
    target=QueryContext("explain alpha"),
    options~,
    context~,
    source_revisions~,
    dependencies~,
    dependency_fingerprint=fingerprint,
  )

  context.push(provider_boundary_context_item("src/b.mbt", revision, "beta"))
  source_revisions.push(
    ProviderSourceSnapshot::new(key=FileSummary("src/b.mbt"), revision~),
  )
  dependencies.push(FileSummary("src/b.mbt"))

  inspect(request.id() == request_id, content="true")
  inspect(request.target() == QueryContext("explain alpha"), content="true")
  inspect(request.options().task_kind, content="summarize")
  inspect(request.options().provider_id, content="mock-provider")
  inspect(request.options().model_id, content="mock-model")
  inspect(
    request.options().option_identity.to_string(),
    content="temperature=<redacted>;max=128",
  )
  inspect(request.context().length(), content="1")
  inspect(request.source_revisions().length(), content="1")
  inspect(request.dependencies().length(), content="2")
  inspect(request.dependency_fingerprint().to_string(), content="deps:repo,a")

  let returned_dependencies = request.dependencies()
  returned_dependencies.push(FileText("external.mbt"))
  inspect(request.dependencies().length(), content="2")
}

///|
test "provider result descriptor copies result payloads and derives status" {
  let revision = provider_boundary_revision_for_test()
  let request_id = ProviderRequestId::new("req-2")
  let fingerprint = ProviderDependencyFingerprint::new("deps:context")
  let options = provider_boundary_options_for_test()
  let payload_items : Array[ContextItem] = [
    provider_boundary_context_item("src/a.mbt", revision, "alpha summary"),
  ]
  let source_revisions : Array[ProviderSourceSnapshot] = [
    ProviderSourceSnapshot::new(key=FileSummary("src/a.mbt"), revision~),
  ]

  let result = ProviderResultDescriptor::new(
    request_id~,
    target=PackedContext("explain alpha", 1),
    options~,
    source_revisions~,
    dependency_fingerprint=fingerprint,
    result=ProviderResult::Succeeded(ContextItems(payload_items)),
  )

  payload_items.push(
    provider_boundary_context_item("src/b.mbt", revision, "beta"),
  )
  source_revisions.push(
    ProviderSourceSnapshot::new(key=FileSummary("src/b.mbt"), revision~),
  )

  inspect(result.request_id() == request_id, content="true")
  inspect(result.target() == PackedContext("explain alpha", 1), content="true")
  inspect(result.source_revisions().length(), content="1")
  inspect(result.dependency_fingerprint().to_string(), content="deps:context")
  inspect(result.status() == ProviderRequestStatus::Succeeded, content="true")

  match result.result() {
    ProviderResult::Succeeded(ContextItems(items)) => {
      inspect(items.length(), content="1")
      items.push(
        provider_boundary_context_item("external.mbt", revision, "external"),
      )
    }
    _ => fail("expected successful context result")
  }
  match result.result() {
    ProviderResult::Succeeded(ContextItems(items)) =>
      inspect(items.length(), content="1")
    _ => fail("expected successful context result")
  }
}

///|
test "provider errors expose retry classification" {
  inspect(
    ProviderError::Timeout.retry_classification() ==
    ProviderRetryClassification::RetryableLater(retry_after_ms=None),
    content="true",
  )
  inspect(
    ProviderError::RateLimited(retry_after_ms=Some(250)).retry_classification() ==
    ProviderRetryClassification::RetryableLater(retry_after_ms=Some(250)),
    content="true",
  )
  inspect(
    ProviderError::Network(message="offline").retry_classification() ==
    ProviderRetryClassification::RetryableLater(retry_after_ms=None),
    content="true",
  )
  inspect(
    ProviderError::Auth.retry_classification() ==
    ProviderRetryClassification::TerminalUntilConfigurationChanges,
    content="true",
  )
  inspect(
    ProviderError::UnsupportedModel(model_id="mock-missing").retry_classification() ==
    ProviderRetryClassification::TerminalUntilConfigurationChanges,
    content="true",
  )
  inspect(
    ProviderError::ProviderRejected(message="refused").retry_classification() ==
    ProviderRetryClassification::TerminalForRequest,
    content="true",
  )
  inspect(
    ProviderError::BudgetExceeded.retry_classification() ==
    ProviderRetryClassification::TerminalForRequest,
    content="true",
  )
  inspect(
    ProviderError::Cancelled.retry_classification() ==
    ProviderRetryClassification::CallerInitiated,
    content="true",
  )
  inspect(
    ProviderError::StaleCompletion.retry_classification() ==
    ProviderRetryClassification::GraphConsistency,
    content="true",
  )
}

///|
test "provider status descriptor classifies status without scheduling" {
  let request_id = ProviderRequestId::new("req-3")
  let pending = ProviderStatusDescriptor::new(
    request_id~,
    target=RepoSummary,
    status=ProviderRequestStatus::Pending,
  )
  let failed = ProviderStatusDescriptor::new(
    request_id~,
    target=RepoSummary,
    status=ProviderRequestStatus::Failed(ProviderError::StaleCompletion),
  )

  inspect(
    ProviderRequestStatus::Planned.classification() ==
    ProviderStatusClassification::NotStarted,
    content="true",
  )
  inspect(
    pending.classification() == ProviderStatusClassification::InFlight,
    content="true",
  )
  inspect(
    failed.classification() ==
    ProviderStatusClassification::Failed(
      ProviderRetryClassification::GraphConsistency,
    ),
    content="true",
  )
  inspect(failed.request_id() == request_id, content="true")
  inspect(failed.target() == RepoSummary, content="true")
  inspect(
    failed.status() ==
    ProviderRequestStatus::Failed(ProviderError::StaleCompletion),
    content="true",
  )
}
