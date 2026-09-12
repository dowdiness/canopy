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
test "Recent document adapter admits only listed lead sources" {
  let editing = test_editing()
  let seeds = recent_document_seeds(editing).to_array()
  assert_eq(seeds.length(), 2)
  assert_true(seeds[0].source() != "")
  assert_true(seeds[1].source() != "")
}

///|
test "Recent document adapter uses one selection state" {
  let editing = test_editing()
  let seeds = recent_document_seeds(editing).to_array()
  assert_true(seeds[0].selection() is @recent_documents.Selection::Editing)
  assert_true(seeds[1].selection() is @recent_documents.Selection::Selectable)
}

///|
test "creation failure explains the result and exposes retry" {
  let rendered = @rabbita_testing.server_side_render(() => {
    creation_failure_view(
      @source_repository.CreateFailure::DocumentIdentityUnavailable,
      @cmd.Emit(_ => @cmd.none),
    )
  })
  assert_true(rendered.contains("role=\"alert\""))
  assert_true(
    rendered.contains("This browser cannot create a document identity."),
  )
  assert_true(rendered.contains("Retry creating"))
}
