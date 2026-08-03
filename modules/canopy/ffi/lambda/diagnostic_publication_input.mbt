///|
/// Host-owned reactive identity for one declared dependency. The dependency
/// id is fixed for the registration lifetime; only its safe fingerprint is an
/// incremental input.
priv struct DiagnosticPublicationDependencyInput {
  dependency : @editor.DiagnosticDependencyId
  identity : @incr.Input[String]
}

///|
#warnings("-unused_value")
fn DiagnosticPublicationDependencyInput::DiagnosticPublicationDependencyInput(
  dependency : @editor.DiagnosticDependencyId,
  identity : @incr.Input[String],
) -> DiagnosticPublicationDependencyInput {
  { dependency, identity }
}

///|
priv enum DiagnosticPublicationInputCaptureError {
  InvalidInput(@editor.DiagnosticPublicationInputError)
  Coordinator(@workspace.AbortReport)
} derive(@debug.Debug)

///|
#warnings("-unused_value")
impl Show for DiagnosticPublicationInputCaptureError with fn output(
  self,
  logger,
) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Lambda-host assembly shell for #1096. Coverage is validated before the
/// coordinator is mutated. The returned workspace-cell handle is the only
/// supported capture operation and owns registration/disposal symmetry.
#warnings("-unused_value")
fn register_diagnostic_publication_input_snapshot(
  source_handles : Array[LambdaHandle],
  dependency_inputs : Array[DiagnosticPublicationDependencyInput],
  configuration : @incr.Input[@editor.DiagnosticConfigurationId],
  producer : @editor.DiagnosticProducerId,
  generation : @incr.Input[@editor.DiagnosticProducerGeneration],
) -> Result[
  @workspace.WorkspaceCellHandle[@editor.DiagnosticPublicationInputSnapshot],
  DiagnosticPublicationInputCaptureError,
] {
  let captured_sources = source_handles.copy()
  let captured_dependencies = dependency_inputs.copy()
  // Imperative-shell preflight only: these eager reads validate lifecycle and
  // declared identity before registration. Their values are discarded after
  // validation and never become a captured request snapshot.
  let validation_sources : Array[@editor.DiagnosticPublicationSourceRevision] = []
  for handle in captured_sources {
    match
      coordinator.read_protected(
        handle.editor_id,
        handle.cells.diagnostic_source_revision,
      ) {
      Ok(source) => validation_sources.push(source)
      Err(report) => return Err(Coordinator(report))
    }
  }
  let validation_dependencies = captured_dependencies.map(input => {
    @editor.DiagnosticDependencyRevision(input.dependency, "validation")
  })
  try
    @editor.DiagnosticPublicationInputSnapshot(
      producer,
      generation.peek(),
      validation_sources,
      validation_dependencies,
      configuration.peek(),
    )
  catch {
    error => return Err(InvalidInput(error))
  } noraise {
    _ => ()
  }
  let snapshot_cell : @incr.Derived[@editor.DiagnosticPublicationInputSnapshot] = @incr.Derived::Derived(
    coordinator.runtime(),
    () => {
      let sources = captured_sources.map(handle => {
        match
          coordinator.read_protected(
            handle.editor_id,
            handle.cells.diagnostic_source_revision,
          ) {
          Ok(source) => source
          Err(report) =>
            abort("diagnostic publication source read failed: \{report}")
        }
      })
      let dependencies = captured_dependencies.map(input => {
        @editor.DiagnosticDependencyRevision(
          input.dependency,
          input.identity.get(),
        )
      })
      try
        @editor.DiagnosticPublicationInputSnapshot(
          producer,
          generation.get(),
          sources,
          dependencies,
          configuration.get(),
        )
      catch {
        error =>
          abort("validated diagnostic publication coverage changed: \{error}")
      } noraise {
        snapshot => snapshot
      }
    },
    label="diagnostic_publication_input_snapshot",
  )
  let editor_dependencies = captured_sources.map(handle => {
    (handle.editor_id, handle.cells.diagnostic_source_revision.cell_id())
  })
  match
    coordinator.register_workspace_cell(snapshot_cell, editor_dependencies) {
    Ok(handle) => Ok(handle)
    Err(report) => Err(Coordinator(report))
  }
}
