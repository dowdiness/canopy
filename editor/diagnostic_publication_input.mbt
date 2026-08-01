///|
/// A covered source's stable parser identity paired with its CRDT causal
/// document version. No source text or parser value crosses this boundary.
pub struct DiagnosticPublicationSourceRevision {
  priv source : @loom_core.SourceId
  priv version : @text.Version
} derive(Eq, @debug.Debug)

///|
pub fn DiagnosticPublicationSourceRevision::DiagnosticPublicationSourceRevision(
  source : @loom_core.SourceId,
  version : @text.Version,
) -> DiagnosticPublicationSourceRevision {
  { source, version }
}

///|
pub fn DiagnosticPublicationSourceRevision::source(
  self : DiagnosticPublicationSourceRevision,
) -> @loom_core.SourceId {
  self.source
}

///|
pub fn DiagnosticPublicationSourceRevision::version(
  self : DiagnosticPublicationSourceRevision,
) -> @text.Version {
  self.version
}

///|
pub(all) suberror DiagnosticPublicationInputError {
  NoCoveredSources
  DuplicateSource(@loom_core.SourceId)
  DuplicateDependency(DiagnosticDependencyId)
} derive(Eq, @debug.Debug)

///|
pub impl Show for DiagnosticPublicationInputError with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub struct DiagnosticPublicationInputSnapshot {
  priv producer : DiagnosticProducerId
  priv generation : DiagnosticProducerGeneration
  priv sources : Array[DiagnosticPublicationSourceRevision]
  priv dependencies : Array[DiagnosticDependencyRevision]
  priv configuration : DiagnosticConfigurationId
} derive(Eq, @debug.Debug)

///|
/// Pure validation and normalization boundary. The returned value owns fresh,
/// deterministically ordered arrays; no caller-owned collection escapes.
pub fn DiagnosticPublicationInputSnapshot::DiagnosticPublicationInputSnapshot(
  producer : DiagnosticProducerId,
  generation : DiagnosticProducerGeneration,
  sources : Array[DiagnosticPublicationSourceRevision],
  dependencies : Array[DiagnosticDependencyRevision],
  configuration : DiagnosticConfigurationId,
) -> DiagnosticPublicationInputSnapshot raise DiagnosticPublicationInputError {
  guard !sources.is_empty() else { raise NoCoveredSources }
  let normalized_sources = sources.copy()
  let source_ids : Set[@loom_core.SourceId] = Set([])
  for source_revision in normalized_sources {
    guard source_ids.add_and_check(source_revision.source) else {
      raise DuplicateSource(source_revision.source)
    }
  }
  normalized_sources.sort_by((left, right) => {
    left.source.value().compare(right.source.value())
  })
  let normalized_dependencies = dependencies.copy()
  let dependency_ids : Set[DiagnosticDependencyId] = Set([])
  for dependency_revision in normalized_dependencies {
    guard dependency_ids.add_and_check(dependency_revision.dependency) else {
      raise DuplicateDependency(dependency_revision.dependency)
    }
  }
  normalized_dependencies.sort_by((left, right) => {
    left.dependency.to_string().compare(right.dependency.to_string())
  })
  {
    producer,
    generation,
    sources: normalized_sources,
    dependencies: normalized_dependencies,
    configuration,
  }
}

///|
pub fn DiagnosticPublicationInputSnapshot::producer(
  self : DiagnosticPublicationInputSnapshot,
) -> DiagnosticProducerId {
  self.producer
}

///|
pub fn DiagnosticPublicationInputSnapshot::generation(
  self : DiagnosticPublicationInputSnapshot,
) -> DiagnosticProducerGeneration {
  self.generation
}

///|
pub fn DiagnosticPublicationInputSnapshot::sources(
  self : DiagnosticPublicationInputSnapshot,
) -> Array[DiagnosticPublicationSourceRevision] {
  self.sources.copy()
}

///|
pub fn DiagnosticPublicationInputSnapshot::dependencies(
  self : DiagnosticPublicationInputSnapshot,
) -> Array[DiagnosticDependencyRevision] {
  self.dependencies.copy()
}

///|
pub fn DiagnosticPublicationInputSnapshot::configuration(
  self : DiagnosticPublicationInputSnapshot,
) -> DiagnosticConfigurationId {
  self.configuration
}

///|
/// Reactive editor view used by host protected surfaces. Parser source is read
/// only to establish invalidation; the returned value carries no source text.
pub fn[T] SyncEditor::diagnostic_publication_source_revision(
  self : SyncEditor[T],
) -> @incr.Derived[DiagnosticPublicationSourceRevision] {
  let source_id = self.parser_source_id()
  @incr.Derived::Derived(
    self.parser_runtime(),
    () => {
      DiagnosticPublicationSourceRevision(
        source_id,
        self.document_version.get(),
      )
    },
    label="diagnostic_publication_source_revision",
  )
}
