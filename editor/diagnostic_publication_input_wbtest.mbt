///|
test "diagnostic publication input rejects duplicate declared identities" {
  let producer = DiagnosticProducerId("producer")
  let generation = DiagnosticProducerGeneration(0)
  let configuration = DiagnosticConfigurationId("configuration")
  let source = @loom_core.SourceId("source")
  let source_revision = DiagnosticPublicationSourceRevision(
    source,
    @text.Version::empty(),
  )
  let duplicate_source = try {
    let _ = DiagnosticPublicationInputSnapshot(
      producer,
      generation,
      [source_revision, source_revision],
      [],
      configuration,
    )
    None
  } catch {
    error => Some(error)
  }
  guard duplicate_source is Some(DuplicateSource(duplicate)) else {
    fail("expected DuplicateSource")
  }
  assert_eq(duplicate, source)
  let dependency_id = DiagnosticDependencyId("dependency")
  let dependency = DiagnosticDependencyRevision(dependency_id, "identity")
  let duplicate_dependency = try {
    let _ = DiagnosticPublicationInputSnapshot(
      producer,
      generation,
      [source_revision],
      [dependency, dependency],
      configuration,
    )
    None
  } catch {
    error => Some(error)
  }
  guard duplicate_dependency is Some(DuplicateDependency(duplicate)) else {
    fail("expected DuplicateDependency")
  }
  assert_eq(duplicate, dependency_id)
}

///|
test "diagnostic publication input normalizes order and owns its arrays" {
  let source_z = DiagnosticPublicationSourceRevision(
    @loom_core.SourceId("z-source"),
    @text.Version::empty(),
  )
  let source_a = DiagnosticPublicationSourceRevision(
    @loom_core.SourceId("a-source"),
    @text.Version::empty(),
  )
  let dependency_z = DiagnosticDependencyRevision(
    DiagnosticDependencyId("z-dependency"),
    "z-identity",
  )
  let dependency_a = DiagnosticDependencyRevision(
    DiagnosticDependencyId("a-dependency"),
    "a-identity",
  )
  let constructor_sources = [source_z, source_a]
  let constructor_dependencies = [dependency_z, dependency_a]
  let snapshot = DiagnosticPublicationInputSnapshot(
    DiagnosticProducerId("producer"),
    DiagnosticProducerGeneration(0),
    constructor_sources,
    constructor_dependencies,
    DiagnosticConfigurationId("configuration"),
  )
  assert_eq(snapshot.sources()[0].source().value(), "a-source")
  assert_eq(snapshot.dependencies()[0].dependency().to_string(), "a-dependency")
  constructor_sources.clear()
  constructor_dependencies.clear()
  assert_eq(snapshot.sources().length(), 2)
  assert_eq(snapshot.dependencies().length(), 2)
  let returned_sources = snapshot.sources()
  let returned_dependencies = snapshot.dependencies()
  returned_sources.clear()
  returned_dependencies.clear()
  assert_eq(snapshot.sources().length(), 2)
  assert_eq(snapshot.dependencies().length(), 2)
}

///|
test "diagnostic source revision follows local structural undo redo and remote edits" {
  let primary = try! @probe.new_test_editor("diagnostic-source-local")
  let local_watch = primary.diagnostic_publication_source_revision().watch()
  let initial = local_watch.read().unwrap()
  primary.set_text("a")
  let after_local = local_watch.read().unwrap()
  assert_true(after_local.version() != initial.version())
  let root = primary.get_proj_node().unwrap()
  primary.commit_edit(root.id(), "b", 0).unwrap()
  let after_structural = local_watch.read().unwrap()
  assert_true(after_structural.version() != after_local.version())
  assert_true(primary.undo())
  let after_undo = local_watch.read().unwrap()
  assert_true(after_undo.version() != after_structural.version())
  assert_true(primary.redo())
  let after_redo = local_watch.read().unwrap()
  assert_true(after_redo.version() != after_undo.version())
  let remote = try! @probe.new_test_editor("diagnostic-source-remote")
  let remote_watch = remote.diagnostic_publication_source_revision().watch()
  let before_remote = remote_watch.read().unwrap()
  try! remote.apply_sync(try! primary.export_all())
  let after_remote = remote_watch.read().unwrap()
  assert_true(after_remote.version() != before_remote.version())
  local_watch.dispose()
  remote_watch.dispose()
}

///|
test "diagnostic source revision follows causal changes with identical text" {
  let receiver = try! @probe.new_test_editor("diagnostic-causal-receiver")
  let watch = receiver.diagnostic_publication_source_revision().watch()
  let before = watch.read().unwrap()
  let sender = try! @probe.new_test_editor("diagnostic-causal-sender")
  sender.set_text("transient")
  sender.set_text("")
  assert_eq(receiver.get_text(), sender.get_text())
  try! receiver.apply_sync(try! sender.export_all())
  let after = watch.read().unwrap()
  assert_true(after.version() != before.version())
  assert_eq(receiver.get_text(), "")
  watch.dispose()
}
