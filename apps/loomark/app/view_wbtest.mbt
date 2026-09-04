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
  assert_eq(document_option_label(entries, 2, entries[2]), "Body only")
}

///|
test "Recent documents includes promoted New and current Change order" {
  let initial = test_editing()
  let (documents, _) = initial.documents.reduce(
    DocumentsTextChanged(
      "two",
      "two changed",
      @source_repository.ChangeOrder::from_int64(0L).unwrap(),
    ),
  )
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  let (documents, _) = documents.reduce(
    DocumentsTextChanged(
      "new",
      "new text",
      @source_repository.ChangeOrder::from_int64(0L).unwrap(),
    ),
  )
  let entries = recent_entries({ ..initial, documents, })
  assert_eq(entries.map(entry => entry.document_id()), ["new", "two", "one"])
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
