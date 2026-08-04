///|
test "fixed transcript preserves exact order and named prefixes" {
  let scenario = fixed_scenario()
  let steps = scenario.steps()
  inspect(steps.length(), content="23")
  inspect(
    steps.map(step => step.event().label()).join("\n"),
    content=(
      #|open document
      #|edit draft to invalid bytes
      #|submit agent request Q
      #|store commit Q
      #|lose response Q
      #|retry request Q
      #|deliver source effect E-source-1
      #|crash before source outcome
      #|recover document
      #|redeliver source effect E-source-1
      #|store blocked source outcome
      #|deliver renderer effect E-render-1
      #|renderer delivery E-render-1 fails
      #|store renderer dirty outcome
      #|deliver stale renderer effect E-render-0
      #|renderer rebuild succeeds
      #|crash before renderer outcome
      #|recover document
      #|redeliver stale renderer effect E-render-0
      #|renderer rebuild succeeds
      #|store rebuilt renderer outcome
      #|deliver duplicate renderer effect E-render-1
      #|store duplicate renderer outcome
    ),
  )

  let graph_prefix = scenario.prefix(GraphOperations)
  let persistence_prefix = scenario.prefix(RequestPersistence)
  let complete_prefix = scenario.prefix(CompleteTranscript)
  inspect(graph_prefix.length(), content="3")
  inspect(persistence_prefix.length(), content="6")
  inspect(complete_prefix.length(), content="23")
  inspect(graph_prefix.equal(steps.view(end=3)), content="true")
  inspect(persistence_prefix.equal(steps.view(end=6)), content="true")
  inspect(complete_prefix.equal(steps), content="true")
}

///|
test "fixed transcript retains exact draft bytes and operation algebra" {
  let scenario = fixed_scenario()
  inspect(
    scenario.invalid_draft_bytes().equal_to_bytes(b"valid\n<unfinished"),
    content="true",
  )
  inspect(
    scenario.request_batch().map(operation => operation.label()).join("\n"),
    content=(
      #|insert h0 panel at root end
      #|insert h1 text at root end
      #|set h0.note to null
      #|move h1 into h0 end
      #|remove h0.note
      #|remove h1
    ),
  )

  let expected = scenario.final_expectation()
  inspect(expected.graph_digest, content="graph:G1")
  inspect(expected.graph_revision, content="1")
  inspect(expected.schema_identity, content="schema:ui-v1")
  inspect(expected.schema_digest, content="schema-digest:ui-v1")
  inspect(expected.applied_history_length, content="1")
  inspect(expected.terminal_request_count, content="1")
  inspect(expected.inserted_node_ids.join(","), content="node:Q:0,node:Q:1")
  inspect(
    expected.draft_bytes.view().equal_to_bytes(b"valid\n<unfinished"),
    content="true",
  )
  inspect(expected.renderer_baseline, content="1")
  inspect(expected.renderer_dirty, content="false")
}

///|
test "fixed transcript event expectations are deterministic" {
  let first = fixed_scenario()
  let second = fixed_scenario()
  inspect(first.steps().equal(second.steps()), content="true")
  inspect(
    first.steps().all(step => !step.expectations().is_empty()),
    content="true",
  )
  inspect(first.request_batch().equal(second.request_batch()), content="true")
  inspect(
    first.final_expectation() == second.final_expectation(),
    content="true",
  )
}

///|
fn prop_named_prefix_selects_exact_transcript_view(
  checkpoint : ScenarioCheckpoint,
) -> Bool {
  let scenario = fixed_scenario()
  let end = match checkpoint {
    GraphOperations => 3
    RequestPersistence => 6
    CompleteTranscript => 23
  }
  scenario.prefix(checkpoint).equal(scenario.steps().view(end~))
}

///|
test "property: named prefixes select exact transcript views" {
  @qc.quick_check_fn(prop_named_prefix_selects_exact_transcript_view)
}
