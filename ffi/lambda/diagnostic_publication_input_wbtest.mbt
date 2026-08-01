// Behavioral boundary matrix for #1096.
//
// | Coverage / event | Observable boundary |
// | --- | --- |
// | One real editor | One WorkspaceCellHandle read returns its stable source id and causal version. |
// | A0 -> A1 -> A0 | Equal restored text still has a newer captured causal version. |
// | Two sources + host inputs in one batch | A read returns the complete pre-batch or post-batch tuple, never a mix. |
// | One covered input changes | A later read changes; an earlier returned snapshot stays detached. |
// | Uncovered editor changes | The declared snapshot remains equal. |
// | Duplicate source/dependency declarations | Registration is rejected before coordinator state changes. |
// | Live/disposed handle | Destroy is refused while live, then succeeds after idempotent disposal. |

///|
test "diagnostic input snapshot captures one real Lambda editor" {
  reset_coordinator_for_phase1_tests()
  let raw_handle = create_editor("diagnostic_snapshot_single")
  let editor_handle = lambda_registry.get(raw_handle).unwrap()
  editor_handle.editor.set_text("let answer = 42")
  let configuration = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticConfigurationId("config-0"),
    label="diagnostic_configuration",
  )
  let generation = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticProducerGeneration(0),
    label="diagnostic_generation",
  )
  let producer = @editor.DiagnosticProducerId("lambda-typecheck")
  let snapshot_handle = match
    register_diagnostic_publication_input_snapshot(
      [editor_handle],
      [],
      configuration,
      producer,
      generation,
    ) {
    Ok(handle) => handle
    Err(error) => fail("register diagnostic snapshot: \{error}")
  }
  let snapshot = snapshot_handle.read().unwrap()
  let sources = snapshot.sources()
  assert_eq(sources.length(), 1)
  assert_eq(sources[0].source(), editor_handle.editor.parser_source_id())
  assert_eq(sources[0].version(), editor_handle.editor.get_version())
  assert_eq(snapshot.producer(), producer)
  assert_eq(snapshot.configuration(), configuration.peek())
  assert_eq(snapshot.generation(), generation.peek())
  snapshot_handle.dispose()
  destroy_editor(raw_handle)
}

///|
test "diagnostic input snapshot keeps A0 A1 A0 causally distinct" {
  reset_coordinator_for_phase1_tests()
  let raw_handle = create_editor("diagnostic_snapshot_aba")
  let editor_handle = lambda_registry.get(raw_handle).unwrap()
  let configuration = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticConfigurationId("config-0"),
  )
  let generation = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticProducerGeneration(0),
  )
  let producer = @editor.DiagnosticProducerId("lambda-typecheck")
  let snapshot_handle = register_diagnostic_publication_input_snapshot(
    [editor_handle],
    [],
    configuration,
    producer,
    generation,
  ).unwrap()
  editor_handle.editor.set_text("A0")
  let first = snapshot_handle.read().unwrap()
  editor_handle.editor.set_text("A1")
  let middle = snapshot_handle.read().unwrap()
  editor_handle.editor.set_text("A0")
  let restored = snapshot_handle.read().unwrap()
  assert_eq(editor_handle.editor.get_text(), "A0")
  assert_true(first.sources()[0].version() != middle.sources()[0].version())
  assert_true(first.sources()[0].version() != restored.sources()[0].version())
  assert_true(middle.sources()[0].version() != restored.sources()[0].version())
  snapshot_handle.dispose()
  destroy_editor(raw_handle)
}

///|
test "diagnostic input snapshot observes one batched multi-source host tuple" {
  reset_coordinator_for_phase1_tests()
  let raw_a = create_editor("diagnostic_snapshot_batch_a")
  let raw_b = create_editor("diagnostic_snapshot_batch_b")
  let handle_a = lambda_registry.get(raw_a).unwrap()
  let handle_b = lambda_registry.get(raw_b).unwrap()
  handle_a.editor.set_text("A0")
  handle_b.editor.set_text("B0")
  let dependency_identity = @incr.Input(coordinator.runtime(), "dependency-0")
  let dependency = DiagnosticPublicationDependencyInput(
    @editor.DiagnosticDependencyId("workspace"),
    dependency_identity,
  )
  let configuration = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticConfigurationId("config-0"),
  )
  let generation = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticProducerGeneration(0),
  )
  let producer = @editor.DiagnosticProducerId("lambda-typecheck")
  let snapshot_handle = register_diagnostic_publication_input_snapshot(
    [handle_b, handle_a],
    [dependency],
    configuration,
    producer,
    generation,
  ).unwrap()
  let before = snapshot_handle.read().unwrap()
  coordinator
  .runtime()
  .batch(() => {
    handle_a.editor.set_text("A1")
    handle_b.editor.set_text("B1")
    dependency_identity.set("dependency-1")
    configuration.set(@editor.DiagnosticConfigurationId("config-1"))
    generation.set(@editor.DiagnosticProducerGeneration(1))
  })
  let after = snapshot_handle.read().unwrap()
  let after_sources = after.sources()
  assert_true(
    after_sources.any(source => {
      source.source() == handle_a.editor.parser_source_id() &&
      source.version() == handle_a.editor.get_version()
    }),
  )
  assert_true(
    after_sources.any(source => {
      source.source() == handle_b.editor.parser_source_id() &&
      source.version() == handle_b.editor.get_version()
    }),
  )
  assert_eq(after.dependencies()[0].identity(), "dependency-1")
  assert_eq(
    after.configuration(),
    @editor.DiagnosticConfigurationId("config-1"),
  )
  assert_eq(after.generation(), @editor.DiagnosticProducerGeneration(1))
  assert_eq(before.dependencies()[0].identity(), "dependency-0")
  assert_eq(
    before.configuration(),
    @editor.DiagnosticConfigurationId("config-0"),
  )
  assert_eq(before.generation(), @editor.DiagnosticProducerGeneration(0))
  snapshot_handle.dispose()
  destroy_editor(raw_a)
  destroy_editor(raw_b)
}

///|
test "diagnostic input snapshot invalidates only for declared inputs" {
  reset_coordinator_for_phase1_tests()
  let raw_covered = create_editor("diagnostic_snapshot_covered")
  let raw_uncovered = create_editor("diagnostic_snapshot_uncovered")
  let covered = lambda_registry.get(raw_covered).unwrap()
  let uncovered = lambda_registry.get(raw_uncovered).unwrap()
  let dependency_identity = @incr.Input(coordinator.runtime(), "dependency-0")
  let dependency = DiagnosticPublicationDependencyInput(
    @editor.DiagnosticDependencyId("workspace"),
    dependency_identity,
  )
  let configuration = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticConfigurationId("config-0"),
  )
  let generation = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticProducerGeneration(0),
  )
  let snapshot_handle = register_diagnostic_publication_input_snapshot(
    [covered],
    [dependency],
    configuration,
    @editor.DiagnosticProducerId("lambda-typecheck"),
    generation,
  ).unwrap()
  let initial = snapshot_handle.read().unwrap()
  uncovered.editor.set_text("unrelated")
  assert_eq(snapshot_handle.read().unwrap(), initial)
  covered.editor.set_text("covered")
  let after_source = snapshot_handle.read().unwrap()
  assert_true(after_source != initial)
  dependency_identity.set("dependency-1")
  let after_dependency = snapshot_handle.read().unwrap()
  assert_true(after_dependency != after_source)
  configuration.set(@editor.DiagnosticConfigurationId("config-1"))
  let after_configuration = snapshot_handle.read().unwrap()
  assert_true(after_configuration != after_dependency)
  generation.set(@editor.DiagnosticProducerGeneration(1))
  let after_generation = snapshot_handle.read().unwrap()
  assert_true(after_generation != after_configuration)
  assert_eq(initial.dependencies()[0].identity(), "dependency-0")
  assert_eq(
    initial.configuration(),
    @editor.DiagnosticConfigurationId("config-0"),
  )
  assert_eq(initial.generation(), @editor.DiagnosticProducerGeneration(0))
  snapshot_handle.dispose()
  destroy_editor(raw_covered)
  destroy_editor(raw_uncovered)
}

///|
test "duplicate source coverage is rejected before coordinator mutation" {
  reset_coordinator_for_phase1_tests()
  let raw_handle = create_editor("diagnostic_snapshot_duplicate_source")
  let editor_handle = lambda_registry.get(raw_handle).unwrap()
  let configuration = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticConfigurationId("config-0"),
  )
  let generation = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticProducerGeneration(0),
  )
  match
    register_diagnostic_publication_input_snapshot(
      [editor_handle, editor_handle],
      [],
      configuration,
      @editor.DiagnosticProducerId("lambda-typecheck"),
      generation,
    ) {
    Err(InvalidInput(@editor.DuplicateSource(_))) => ()
    Err(error) => fail("expected duplicate source, got \{error}")
    Ok(_) => fail("expected duplicate source rejection")
  }
  match coordinator.destroy_editor(editor_handle.editor_id) {
    Ok(_) => ()
    Err(report) =>
      fail("duplicate validation leaked coordinator state: \{report}")
  }
  drain_lambda_handle_after_direct_coordinator_destroy(
    raw_handle, editor_handle,
  )
}

///|
test "duplicate dependency coverage is rejected before coordinator mutation" {
  reset_coordinator_for_phase1_tests()
  let raw_handle = create_editor("diagnostic_snapshot_duplicate_dependency")
  let editor_handle = lambda_registry.get(raw_handle).unwrap()
  let dependency = DiagnosticPublicationDependencyInput(
    @editor.DiagnosticDependencyId("workspace"),
    @incr.Input(coordinator.runtime(), "dependency-0"),
  )
  let configuration = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticConfigurationId("config-0"),
  )
  let generation = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticProducerGeneration(0),
  )
  match
    register_diagnostic_publication_input_snapshot(
      [editor_handle],
      [dependency, dependency],
      configuration,
      @editor.DiagnosticProducerId("lambda-typecheck"),
      generation,
    ) {
    Err(InvalidInput(@editor.DuplicateDependency(_))) => ()
    Err(error) => fail("expected duplicate dependency, got \{error}")
    Ok(_) => fail("expected duplicate dependency rejection")
  }
  match coordinator.destroy_editor(editor_handle.editor_id) {
    Ok(_) => ()
    Err(report) =>
      fail("duplicate validation leaked coordinator state: \{report}")
  }
  drain_lambda_handle_after_direct_coordinator_destroy(
    raw_handle, editor_handle,
  )
}

///|
test "diagnostic snapshot handle owns symmetric idempotent lifecycle" {
  reset_coordinator_for_phase1_tests()
  let raw_handle = create_editor("diagnostic_snapshot_lifecycle")
  let editor_handle = lambda_registry.get(raw_handle).unwrap()
  let configuration = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticConfigurationId("config-0"),
  )
  let generation = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticProducerGeneration(0),
  )
  let snapshot_handle = register_diagnostic_publication_input_snapshot(
    [editor_handle],
    [],
    configuration,
    @editor.DiagnosticProducerId("lambda-typecheck"),
    generation,
  ).unwrap()
  match coordinator.destroy_editor(editor_handle.editor_id) {
    Err(report) => {
      assert_eq(report.kind, @workspace.DestroyWhileDependedUpon)
      @debug.assert_eq(report.cell_id, Some(snapshot_handle.id()))
    }
    Ok(_) => fail("expected live snapshot handle to protect editor")
  }
  let before = snapshot_handle.read().unwrap()
  editor_handle.editor.set_text("still alive")
  assert_true(snapshot_handle.read().unwrap() != before)
  snapshot_handle.dispose()
  snapshot_handle.dispose()
  match coordinator.destroy_editor(editor_handle.editor_id) {
    Ok(_) => ()
    Err(report) => fail("expected destroy after snapshot disposal: \{report}")
  }
  drain_lambda_handle_after_direct_coordinator_destroy(
    raw_handle, editor_handle,
  )
}

///|
test "diagnostic snapshot registration preserves typed coordinator failures" {
  reset_coordinator_for_phase1_tests()
  let configuration = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticConfigurationId("config-0"),
  )
  let generation = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticProducerGeneration(0),
  )
  let producer = @editor.DiagnosticProducerId("lambda-typecheck")
  let raw_dead = create_editor("diagnostic_snapshot_dead")
  let dead = lambda_registry.get(raw_dead).unwrap()
  coordinator.destroy_editor(dead.editor_id).unwrap()
  match
    register_diagnostic_publication_input_snapshot(
      [dead],
      [],
      configuration,
      producer,
      generation,
    ) {
    Err(Coordinator(report)) =>
      assert_eq(report.kind, @workspace.EditorDestroyed)
    Err(error) => fail("expected EditorDestroyed, got \{error}")
    Ok(handle) => {
      handle.dispose()
      fail("expected destroyed editor rejection")
    }
  }
  drain_lambda_handle_after_direct_coordinator_destroy(raw_dead, dead)
  let raw_a = create_editor("diagnostic_snapshot_foreign_a")
  let raw_b = create_editor("diagnostic_snapshot_foreign_b")
  let handle_a = lambda_registry.get(raw_a).unwrap()
  let handle_b = lambda_registry.get(raw_b).unwrap()
  let foreign : LambdaHandle = {
    editor: handle_a.editor,
    companion: handle_a.companion,
    editor_id: handle_a.editor_id,
    cells: handle_b.cells,
  }
  match
    register_diagnostic_publication_input_snapshot(
      [foreign],
      [],
      configuration,
      producer,
      generation,
    ) {
    Err(Coordinator(report)) =>
      assert_eq(report.kind, @workspace.CellNotInProtectedSurface)
    Err(error) => fail("expected CellNotInProtectedSurface, got \{error}")
    Ok(handle) => {
      handle.dispose()
      fail("expected foreign cell rejection")
    }
  }
  destroy_editor(raw_a)
  destroy_editor(raw_b)
  let raw_disposed = create_editor("diagnostic_snapshot_disposed")
  let disposed = lambda_registry.get(raw_disposed).unwrap()
  (disposed.cells.diagnostic_source_revision.dispose)()
  match
    register_diagnostic_publication_input_snapshot(
      [disposed],
      [],
      configuration,
      producer,
      generation,
    ) {
    Err(Coordinator(report)) =>
      assert_eq(report.kind, @workspace.ProtectedCellDisposed)
    Err(error) => fail("expected ProtectedCellDisposed, got \{error}")
    Ok(handle) => {
      handle.dispose()
      fail("expected disposed protected cell rejection")
    }
  }
  destroy_editor(raw_disposed)
}

///|
test "two producers capture one source without sharing producer identity" {
  reset_coordinator_for_phase1_tests()
  let raw_handle = create_editor("diagnostic_snapshot_two_producers")
  let editor_handle = lambda_registry.get(raw_handle).unwrap()
  let configuration = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticConfigurationId("config-0"),
  )
  let generation_a = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticProducerGeneration(0),
  )
  let generation_b = @incr.Input(
    coordinator.runtime(),
    @editor.DiagnosticProducerGeneration(0),
  )
  let handle_a = register_diagnostic_publication_input_snapshot(
    [editor_handle],
    [],
    configuration,
    @editor.DiagnosticProducerId("producer-a"),
    generation_a,
  ).unwrap()
  let handle_b = register_diagnostic_publication_input_snapshot(
    [editor_handle],
    [],
    configuration,
    @editor.DiagnosticProducerId("producer-b"),
    generation_b,
  ).unwrap()
  let snapshot_a = handle_a.read().unwrap()
  let snapshot_b = handle_b.read().unwrap()
  assert_true(snapshot_a.producer() != snapshot_b.producer())
  assert_eq(snapshot_a.sources(), snapshot_b.sources())
  handle_a.dispose()
  handle_b.dispose()
  destroy_editor(raw_handle)
}
