///|
#warnings("-alert_unstable")
fn render_preview_state(state : PreviewState) -> String {
  @rabbita_testing.server_side_render(() => preview_view(state))
}

///|
test "Mode tabs use the RUI Tabs trigger contract" {
  let rendered = @rabbita_testing.server_side_render(() => {
    mode_tab(Text, Preview, @cmd.Emit(_ => @cmd.none))
  })
  assert_true(rendered.contains("data-slot=\"tabs-trigger\""))
  assert_true(rendered.contains("data-state=\"inactive\""))
  assert_true(rendered.contains("role=\"tab\""))
  assert_true(rendered.contains("aria-selected=\"false\""))
  assert_true(rendered.contains("aria-controls=\"loomark-editor-panel\""))
  assert_true(rendered.contains("id=\"loomark-mode-text\""))

  let content = @rabbita_testing.server_side_render(() => {
    mode_content(Text, @html.p("Editor"))
  })
  assert_true(content.contains("data-slot=\"tabs-content\""))
  assert_true(content.contains("role=\"tabpanel\""))
  assert_true(content.contains("aria-labelledby=\"loomark-mode-text\""))
  assert_true(content.contains("id=\"loomark-editor-panel\""))
}

///|
test "Document sidebar labels disambiguate Source-derived identities" {
  let snapshot = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("document-a", "# Untitled\n").unwrap(),
    @source_repository.SourceRecord::new("document-b", "# Untitled\n").unwrap(),
    @source_repository.SourceRecord::new("document-c", "Body only\n").unwrap(),
  ]).unwrap()
  let entries = snapshot.catalog().entries()
  assert_eq(document_option_label(entries, 0, entries[0]), "Untitled (1 of 2)")
  assert_eq(document_option_label(entries, 1, entries[1]), "Untitled (2 of 2)")
  assert_eq(document_option_label(entries, 2, entries[2]), "Unnamed document")
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
  assert_true(
    preparing.contains("prose prose-sm loomark-prose md:prose-base xl:prose-lg"),
  )

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
