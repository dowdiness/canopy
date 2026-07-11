///|
/// Plan graph-visible provider work for `target` with safe-to-store options.
///
/// Planning is synchronous and deterministic. It records the request descriptor
/// and marks the request pending for an external driver to consume. It does not
/// start tasks, schedule retries, read credentials, or perform transport.
pub fn CognitionStore::plan_provider_request(
  self : CognitionStore,
  target~ : CognitionKey,
  options~ : ProviderOptionProvenance,
) -> ProviderRequestDescriptor {
  let dependencies = self.provider_dependencies_for_target(target)
  let source_revisions = self.provider_source_snapshots_for(dependencies)
  let request = self.reactive.plan_provider_request(
    target~,
    options~,
    context=self.provider_context_for_target(target, dependencies),
    source_revisions~,
    dependencies~,
  )
  let request_id = request.id()
  match self.provider_requests.get(request_id) {
    Some(request) => {
      let current_status = self.provider_statuses
        .get(request_id)
        .unwrap_or(ProviderRequestStatus::Planned)
      match current_status {
        ProviderRequestStatus::Planned | ProviderRequestStatus::Pending =>
          self.provider_statuses[request_id] = ProviderRequestStatus::Pending
        ProviderRequestStatus::Failed(error) =>
          match error.retry_classification() {
            ProviderRetryClassification::RetryableLater(_) => {
              self.provider_statuses[request_id] = ProviderRequestStatus::Pending
              self.provider_results.remove(request_id)
              self.reactive.clear_provider_events()
            }
            _ =>
              match self.provider_results.get(request_id) {
                Some(result) =>
                  self.reactive.record_provider_completion(request, result)
                None => ()
              }
          }
        ProviderRequestStatus::Succeeded =>
          match self.provider_results.get(request_id) {
            Some(result) =>
              self.reactive.record_provider_completion(request, result)
            None => ()
          }
      }
      request
    }
    None => {
      self.reactive.clear_provider_events()
      self.provider_requests[request_id] = request
      self.provider_statuses[request_id] = ProviderRequestStatus::Pending
      request
    }
  }
}

///|
/// Return a planned provider request, if the store knows it.
pub fn CognitionStore::get_provider_request(
  self : CognitionStore,
  request_id : ProviderRequestId,
) -> ProviderRequestDescriptor? {
  self.provider_requests.get(request_id)
}

///|
/// Return the latest provider status descriptor for `request_id`.
pub fn CognitionStore::get_provider_status(
  self : CognitionStore,
  request_id : ProviderRequestId,
) -> ProviderStatusDescriptor? {
  match
    (
      self.provider_requests.get(request_id),
      self.provider_statuses.get(request_id),
    ) {
    (Some(request), Some(status)) =>
      Some(
        ProviderStatusDescriptor::new(
          request_id~,
          target=request.target(),
          status~,
        ),
      )
    _ => None
  }
}

///|
/// Return the latest accepted or rejected completion record for `request_id`.
pub fn CognitionStore::get_provider_result(
  self : CognitionStore,
  request_id : ProviderRequestId,
) -> ProviderResultDescriptor? {
  self.provider_results.get(request_id)
}

///|
/// Cancel an in-flight provider request without deleting the last clean artifact.
pub fn CognitionStore::cancel_provider_request(
  self : CognitionStore,
  request_id : ProviderRequestId,
) -> ProviderStatusDescriptor? {
  match self.provider_requests.get(request_id) {
    Some(request) => {
      let current_status = self.provider_statuses
        .get(request_id)
        .unwrap_or(ProviderRequestStatus::Planned)
      if current_status == ProviderRequestStatus::Pending {
        let status = ProviderRequestStatus::Failed(ProviderError::Cancelled)
        self.provider_statuses[request_id] = status
        let result = ProviderResultDescriptor::new(
          request_id~,
          target=request.target(),
          options=request.options(),
          source_revisions=request.source_revisions(),
          dependency_fingerprint=request.dependency_fingerprint(),
          result=ProviderResult::Failed(ProviderError::Cancelled),
        )
        self.provider_results[request_id] = result
        self.reactive.record_provider_cancellation(request)
        Some(
          ProviderStatusDescriptor::new(
            request_id~,
            target=request.target(),
            status~,
          ),
        )
      } else {
        Some(
          ProviderStatusDescriptor::new(
            request_id~,
            target=request.target(),
            status=current_status,
          ),
        )
      }
    }
    None => None
  }
}

///|
/// Complete provider work explicitly after validating graph provenance.
///
/// The store accepts only completions that match the planned request id, target,
/// option provenance, source revisions, and dependency fingerprint, and whose
/// planned sources are still clean at the recorded revisions.
pub fn CognitionStore::complete_provider_request(
  self : CognitionStore,
  completion : ProviderResultDescriptor,
) -> ProviderStatusDescriptor {
  let request_id = completion.request_id()
  match self.provider_requests.get(request_id) {
    None =>
      ProviderStatusDescriptor::new(
        request_id~,
        target=completion.target(),
        status=ProviderRequestStatus::Failed(
          ProviderError::InvalidRequest(message="unknown request id"),
        ),
      )
    Some(request) => {
      let current_status = self.provider_statuses
        .get(request_id)
        .unwrap_or(ProviderRequestStatus::Planned)
      if current_status != ProviderRequestStatus::Pending {
        ProviderStatusDescriptor::new(
          request_id~,
          target=request.target(),
          status=current_status,
        )
      } else {
        match self.provider_completion_rejection(request, completion) {
          Some(error) => self.reject_provider_completion(request, error)
          None => self.accept_provider_completion(request, completion)
        }
      }
    }
  }
}

///|
fn CognitionStore::provider_completion_rejection(
  self : CognitionStore,
  request : ProviderRequestDescriptor,
  completion : ProviderResultDescriptor,
) -> ProviderError? {
  if completion.target() != request.target() {
    Some(ProviderError::InvalidRequest(message="target mismatch"))
  } else if !provider_result_matches_target(
      completion.target(),
      completion.result(),
    ) {
    Some(ProviderError::InvalidRequest(message="result value type mismatch"))
  } else if completion.options() != request.options() {
    Some(ProviderError::StaleCompletion)
  } else if completion.source_revisions() != request.source_revisions() {
    Some(ProviderError::StaleCompletion)
  } else if completion.dependency_fingerprint() !=
    request.dependency_fingerprint() {
    Some(ProviderError::StaleCompletion)
  } else if !self.provider_source_snapshots_are_current(
      request.source_revisions(),
    ) {
    Some(ProviderError::StaleCompletion)
  } else if self.provider_current_dependency_fingerprint(request.target()) !=
    request.dependency_fingerprint() {
    Some(ProviderError::StaleCompletion)
  } else {
    None
  }
}

///|
fn CognitionStore::accept_provider_completion(
  self : CognitionStore,
  request : ProviderRequestDescriptor,
  completion : ProviderResultDescriptor,
) -> ProviderStatusDescriptor {
  let request_id = request.id()
  let status = completion.status()
  match completion.result() {
    ProviderResult::Succeeded(value) => {
      self.store_provider_value(request.target(), value, request.dependencies())
      self.provider_results[request_id] = completion
      self.provider_statuses[request_id] = status
    }
    ProviderResult::Failed(_) => {
      self.provider_results[request_id] = completion
      self.provider_statuses[request_id] = status
    }
  }
  self.reactive.record_provider_completion(request, completion)
  ProviderStatusDescriptor::new(request_id~, target=request.target(), status~)
}

///|
fn CognitionStore::reject_provider_completion(
  self : CognitionStore,
  request : ProviderRequestDescriptor,
  error : ProviderError,
) -> ProviderStatusDescriptor {
  let request_id = request.id()
  let status = ProviderRequestStatus::Failed(error)
  let result = ProviderResultDescriptor::new(
    request_id~,
    target=request.target(),
    options=request.options(),
    source_revisions=request.source_revisions(),
    dependency_fingerprint=request.dependency_fingerprint(),
    result=ProviderResult::Failed(error),
  )
  self.provider_results[request_id] = result
  self.provider_statuses[request_id] = status
  self.reactive.record_provider_completion(request, result)
  ProviderStatusDescriptor::new(request_id~, target=request.target(), status~)
}

///|
fn provider_result_matches_target(
  target : CognitionKey,
  result : ProviderResult,
) -> Bool {
  match result {
    ProviderResult::Failed(_) => true
    ProviderResult::Succeeded(value) =>
      match (target, value) {
        (FileText(_), Text(_)) => true
        (FileSummary(_), Summary(_)) => true
        (RepoSummary, Summary(_)) => true
        (QueryContext(_), ContextBundle(_)) => true
        (PackedContext(_, _), ContextItems(_)) => true
        (BudgetedContext(_, _, _), ContextItems(_)) => true
        (TruncatedContext(_, _, _), ContextItems(_)) => true
        _ => false
      }
  }
}

///|
fn CognitionStore::store_provider_value(
  self : CognitionStore,
  target : CognitionKey,
  value : CognitionValue,
  dependencies : Array[CognitionKey],
) -> Unit {
  let provider_dependencies = dependencies.filter(fn(input) { input != target })
  match (target, value) {
    (FileText(_), Text(_)) => {
      self.store_input(target, value)
      self.set_dependencies(target, provider_dependencies)
    }
    _ => {
      self.values[target] = value.copy_value()
      self.set_dependencies(target, provider_dependencies)
      self.bump_revision(target)
      self.dirty.remove(target)
      let _ = self.dirty_dependents(target)
    }
  }
}

///|
fn CognitionStore::provider_context_for_target(
  self : CognitionStore,
  target : CognitionKey,
  dependencies : Array[CognitionKey],
) -> Array[ContextItem] {
  match self.values.get(target) {
    Some(ContextItems(items)) => items.copy()
    _ => self.provider_context_for_dependencies(target, dependencies)
  }
}

///|
fn CognitionStore::provider_context_for_dependencies(
  self : CognitionStore,
  target : CognitionKey,
  dependencies : Array[CognitionKey],
) -> Array[ContextItem] {
  let items : Array[ContextItem] = []
  for dependency in normalize_provider_dependencies(dependencies) {
    self.push_context_item(
      items,
      dependency,
      reason="planned provider input for " + target.label(),
    )
  }
  items
}

///|
fn CognitionStore::provider_dependencies_for_target(
  self : CognitionStore,
  target : CognitionKey,
) -> Array[CognitionKey] {
  match self.dependencies.get(target) {
    Some(dependencies) if dependencies.length() > 0 &&
      !self.dirty.contains(target) =>
      normalize_provider_dependencies(dependencies)
    _ => self.provider_default_dependencies_for_target(target)
  }
}

///|
fn CognitionStore::provider_default_dependencies_for_target(
  self : CognitionStore,
  target : CognitionKey,
) -> Array[CognitionKey] {
  match target {
    FileText(_) => if self.revisions.contains(target) { [target] } else { [] }
    FileSummary(path) => [FileText(path)]
    RepoSummary => self.provider_file_text_dependencies()
    QueryContext(_) => self.provider_repo_context_dependencies()
    PackedContext(query, _) => self.provider_context_dependencies(query)
    BudgetedContext(query, _, _) => self.provider_context_dependencies(query)
    TruncatedContext(query, _, _) => self.provider_context_dependencies(query)
  }
}

///|
fn CognitionStore::provider_file_text_dependencies(
  self : CognitionStore,
) -> Array[CognitionKey] {
  let dependencies : Array[CognitionKey] = []
  for path in self.known_files() {
    dependencies.push(FileText(path))
  }
  dependencies
}

///|
fn CognitionStore::provider_repo_context_dependencies(
  self : CognitionStore,
) -> Array[CognitionKey] {
  let dependencies : Array[CognitionKey] = [RepoSummary]
  for file_text in self.provider_file_text_dependencies() {
    dependencies.push(file_text)
  }
  normalize_provider_dependencies(dependencies)
}

///|
fn CognitionStore::provider_context_dependencies(
  self : CognitionStore,
  query : String,
) -> Array[CognitionKey] {
  let dependencies = self.provider_repo_context_dependencies()
  for summary_key in self.selected_file_summary_keys(query) {
    dependencies.push(summary_key)
  }
  normalize_provider_dependencies(dependencies)
}

///|
fn CognitionStore::provider_source_snapshots_for(
  self : CognitionStore,
  dependencies : Array[CognitionKey],
) -> Array[ProviderSourceSnapshot] {
  let snapshots : Array[ProviderSourceSnapshot] = []
  for key in normalize_provider_dependencies(dependencies) {
    snapshots.push(
      ProviderSourceSnapshot::new(
        key~,
        revision=self.revisions.get(key).unwrap_or(Revision(0)),
      ),
    )
  }
  snapshots
}

///|
fn CognitionStore::provider_source_snapshots_are_current(
  self : CognitionStore,
  snapshots : Array[ProviderSourceSnapshot],
) -> Bool {
  for snapshot in snapshots {
    if self.dirty.contains(snapshot.key) {
      return false
    }
    match self.revisions.get(snapshot.key) {
      Some(revision) if revision == snapshot.revision => ()
      None if snapshot.revision == Revision(0) => ()
      _ => return false
    }
  }
  true
}

///|
fn CognitionStore::provider_current_dependency_fingerprint(
  self : CognitionStore,
  target : CognitionKey,
) -> ProviderDependencyFingerprint {
  let dependencies = self.provider_dependencies_for_target(target)
  provider_dependency_fingerprint_for_snapshots(
    dependencies,
    self.provider_source_snapshots_for(dependencies),
  )
}

///|
fn normalize_provider_dependencies(
  dependencies : Array[CognitionKey],
) -> Array[CognitionKey] {
  let normalized : Array[CognitionKey] = []
  for dependency in dependencies {
    if !normalized.contains(dependency) {
      normalized.push(dependency)
    }
  }
  normalized.sort_by(fn(a, b) { a.compare(b) })
  normalized
}

///|
fn provider_dependency_fingerprint_for_snapshots(
  dependencies : Array[CognitionKey],
  snapshots : Array[ProviderSourceSnapshot],
) -> ProviderDependencyFingerprint {
  let parts : Array[String] = []
  for dependency in normalize_provider_dependencies(dependencies) {
    parts.push(
      "\{dependency.label()}@\{provider_snapshot_revision_label(dependency, snapshots)}",
    )
  }
  ProviderDependencyFingerprint::new(parts.join("|"))
}

///|
fn provider_snapshot_revision_label(
  dependency : CognitionKey,
  snapshots : Array[ProviderSourceSnapshot],
) -> String {
  for snapshot in snapshots {
    if snapshot.key == dependency {
      return snapshot.revision.to_int().to_string()
    }
  }
  "missing"
}

///|
fn provider_request_id_for(
  target : CognitionKey,
  options : ProviderOptionProvenance,
  dependency_fingerprint : ProviderDependencyFingerprint,
) -> ProviderRequestId {
  ProviderRequestId::new(
    "provider-request:v2:" +
    [
      target.label(),
      options.task_kind,
      options.provider_id,
      options.model_id,
      options.option_identity.to_string(),
      dependency_fingerprint.to_string(),
    ]
    .map(provider_request_id_component)
    .join(""),
  )
}

///|
fn provider_request_id_component(value : String) -> String {
  "\{value.length()}:\{value}"
}
