///|
test "description decorates IR tasks but leaves code examples literal" {
  let lead = lead_for(
    Some(
      "# Same\n\n```text\n- [ ] literal example\n```\n\n- [ ] real task\n- [x] finished task\n",
    ),
  ).unwrap()
  let rendered = @rabbita_testing.server_side_render(() => {
    description_view(lead, "description")
  })
  assert_true(rendered.contains("- [ ] literal example"))
  assert_false(rendered.contains("- [ ] real task"))
  assert_true(rendered.contains("real task"))
  assert_true(rendered.contains("i-lucide-square-check"))
  assert_true(rendered.contains("aria-label=\"Completed task\""))
  assert_true(rendered.contains("aria-label=\"Incomplete task\""))
  assert_false(rendered.contains("type=\"checkbox\""))
}

///|
test "row has bounded description and no dangling description reference" {
  let seed = Seed::Seed(
    docid="one",
    ordinal=None,
    lead_source=Some("# Same"),
    selected=true,
    can_select=false,
    can_delete=true,
    untouched_new=false,
    compact=false,
    status=None,
  )
  let rendered = @rabbita_testing.server_side_render(() => {
    render_row(
      "one",
      { seed, lead: lead_for(seed.lead_source) },
      @cmd.Emit(_ => @cmd.none),
      @cmd.none,
    )
  })
  assert_false(rendered.contains("aria-describedby"))
  assert_true(rendered.contains("data-state=\"active\""))
  let with_description = @rabbita_testing.server_side_render(() => {
    render_row(
      "one",
      { seed, lead: lead_for(Some("# Same\n\nDifferent content")) },
      @cmd.Emit(_ => @cmd.none),
      @cmd.none,
    )
  })
  assert_true(with_description.contains("Different content"))
  assert_true(
    with_description.contains(
      "aria-describedby=\"loomark-document-description-one\"",
    ),
  )
  assert_true(with_description.contains("[-webkit-line-clamp:2]"))
}

///|
test "bounded lead is the only row label authority" {
  let text = "# " + "a".repeat(80) + "DO_NOT_EXPOSE\n\nShort description"
  let seed = Seed::Seed(
    docid="bounded",
    ordinal=Some((2, 2)),
    lead_source=Some(text),
    selected=false,
    can_select=true,
    can_delete=true,
    untouched_new=false,
    compact=false,
    status=None,
  )
  let html = @rabbita_testing.server_side_render(() => {
    render_row(
      "bounded",
      { seed, lead: lead_for(Some(text)) },
      @cmd.Emit(_ => @cmd.none),
      @cmd.none,
    )
  })
  assert_false(html.contains("DO_NOT_EXPOSE"))
  assert_true(html.contains("aria-label=\"" + "a".repeat(80) + " (2 of 2)\""))
  let preparing = @rabbita_testing.server_side_render(() => {
    render_row(
      "bounded",
      { seed, lead: None },
      @cmd.Emit(_ => @cmd.none),
      @cmd.none,
    )
  })
  assert_false(preparing.contains("DO_NOT_EXPOSE"))
  assert_true(preparing.contains("Document (2 of 2)"))
  let task = @rabbita_testing.server_side_render(() => {
    render_row(
      "bounded",
      {
        seed: { ..seed, ordinal: None },
        lead: lead_for(Some("- [x] Buy tickets")),
      },
      @cmd.Emit(_ => @cmd.none),
      @cmd.none,
    )
  })
  assert_true(task.contains("aria-label=\"Completed task — Buy tickets\""))
  assert_false(task.contains("type=\"checkbox\""))
}
