///|
#warnings("-alert_unstable")
fn render_preview_state(state : PreviewState) -> String {
  @rabbita_testing.server_side_render(() => preview_view(state))
}

///|
test "Document controls render Source-derived identities with usable labels" {
  let snapshot = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-a", "# Untitled\n").unwrap(),
    @source_repository.SourceRecord::new("document-b", "# Untitled\n").unwrap(),
    @source_repository.SourceRecord::new("document-c", "Body only\n").unwrap(),
  ]).unwrap()
  let editing : EditingState = {
    activation: { document_id: "document-a", generation: 0 },
    text: "# Untitled\n",
    composing: false,
    save: Saved,
    creation: Idle,
    mode: Text,
    focused_mode: Text,
    compact: false,
    preview: Unrequested,
    repository: snapshot,
  }
  let rendered = @rabbita_testing.server_side_render(() => {
    document_controls(editing, @cmd.Emit(_ => @cmd.none))
  })
  assert_true(rendered.contains("data-slot=\"native-select\""))
  assert_true(rendered.contains("aria-label=\"Document\""))
  assert_true(rendered.contains("value=\"document-a\""))
  assert_true(rendered.contains("value=\"document-b\""))
  assert_true(rendered.contains("Untitled (1 of 2)"))
  assert_true(rendered.contains("Untitled (2 of 2)"))
  assert_true(rendered.contains("Unnamed document"))
  assert_true(rendered.contains("New document"))

  let unavailable = @rabbita_testing.server_side_render(() => {
    document_controls({ ..editing, save: Waiting }, @cmd.Emit(_ => @cmd.none))
  })
  assert_true(unavailable.contains("disabled"))
  assert_false(unavailable.contains("Wait for saving to finish."))
}

///|
test "creation failure explains the result and exposes retry" {
  let rendered = @rabbita_testing.server_side_render(() => {
    creation_failure_view(
      @source_repository.CreateFailure::QuotaExceeded,
      @cmd.Emit(_ => @cmd.none),
    )
  })
  assert_true(rendered.contains("role=\"alert\""))
  assert_true(rendered.contains("Browser storage is full."))
  assert_true(rendered.contains("Retry creating"))
}

///|
test "Preview view distinguishes preparing initial failure and stale result" {
  let preparing = render_preview_state(Preparing)
  assert_true(preparing.contains("role=\"status\""))
  assert_true(preparing.contains("Preparing preview…"))
  assert_true(preparing.contains("prose loomark-prose"))

  let initial_failure = render_preview_state(Failed(None))
  assert_true(initial_failure.contains("role=\"alert\""))
  assert_true(initial_failure.contains("Preview could not be prepared."))

  let stale = render_preview_state(
    Failed(
      Some({ text: "# Last good\n", html: @html.h1("Last good"), empty: false }),
    ),
  )
  assert_true(stale.contains("Showing the last completed preview."))
  assert_true(stale.contains(">Last good</h1>"))
}
