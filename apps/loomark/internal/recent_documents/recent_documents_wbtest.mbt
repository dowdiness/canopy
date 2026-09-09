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
      { row: { seed, lead: lead_for(seed.lead_source) }, ordinal: None },
      @cmd.Emit(_ => @cmd.none),
      @cmd.none,
    )
  })
  assert_false(rendered.contains("aria-describedby"))
  assert_true(rendered.contains("data-state=\"active\""))
  let with_description = @rabbita_testing.server_side_render(() => {
    render_row(
      "one",
      {
        row: { seed, lead: lead_for(Some("# Same\n\nDifferent content")) },
        ordinal: None,
      },
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
    lead_source=Some(text),
    selected=false,
    can_select=true,
    can_delete=true,
    untouched_new=false,
    compact=false,
    status=None,
  )
  let row = { seed, lead: lead_for(Some(text)) }
  let presented = PresentedRow::{ row, ordinal: Some((2, 2)) }
  let html = @rabbita_testing.server_side_render(() => {
    render_row("bounded", presented, @cmd.Emit(_ => @cmd.none), @cmd.none)
  })
  assert_false(html.contains("DO_NOT_EXPOSE"))
  assert_true(html.contains("aria-label=\"" + "a".repeat(80) + " (2 of 2)\""))
  let preparing = @rabbita_testing.server_side_render(() => {
    render_row(
      "bounded",
      { row: { seed, lead: None }, ordinal: Some((2, 2)) },
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
        row: { seed, lead: lead_for(Some("- [x] Buy tickets")) },
        ordinal: None,
      },
      @cmd.Emit(_ => @cmd.none),
      @cmd.none,
    )
  })
  assert_true(task.contains("aria-label=\"Completed task — Buy tickets\""))
  assert_false(task.contains("type=\"checkbox\""))
}

///|
test "bounded label collisions receive feature-owned ordinals" {
  let prefix = "c".repeat(80)
  fn row(id : String, text : String) -> Row {
    let seed = Seed::Seed(
      docid=id,
      lead_source=Some(text),
      selected=false,
      can_select=true,
      can_delete=true,
      untouched_new=false,
      compact=false,
      status=None,
    )
    { seed, lead: lead_for(Some(text)) }
  }
  let presented = present_rows(
    @vector.Vector([
      row("first", "# \{prefix}FIRST"),
      row("second", "# \{prefix}SECOND"),
      row("other", "# Other"),
    ]),
  ).to_array()
  assert_eq(row_label(presented[0]), "\{prefix} (1 of 2)")
  assert_eq(row_label(presented[1]), "\{prefix} (2 of 2)")
  assert_eq(row_label(presented[2]), "Other")
}

///|
test "row and Delete confirmation share one bounded lead label" {
  let text = "# " + "b".repeat(80) + "DO_NOT_EXPOSE\n\nDescription"
  let seed = Seed::Seed(
    docid="shared-label",
    lead_source=Some(text),
    selected=false,
    can_select=true,
    can_delete=true,
    untouched_new=false,
    compact=false,
    status=None,
  )
  let row = PresentedRow::{
    row: { seed, lead: lead_for(Some(text)) },
    ordinal: Some((1, 2)),
  }
  let navigation = @rabbita_testing.server_side_render(() => {
    render_row("shared-label", row, @cmd.Emit(_ => @cmd.none), @cmd.none)
  })
  let label = "b".repeat(80) + " (1 of 2)"
  assert_true(navigation.contains("aria-label=\"\{label}\""))
  assert_eq(delete_dialog_title(row), "Delete \"\{label}\"?")
  assert_false(navigation.contains("DO_NOT_EXPOSE"))
  assert_false(delete_dialog_title(row).contains("DO_NOT_EXPOSE"))
}

///|
test "Delete confirmation requires an available prepared lead" {
  let seed = Seed::Seed(
    docid="pending",
    lead_source=None,
    selected=false,
    can_select=true,
    can_delete=true,
    untouched_new=false,
    compact=false,
    status=None,
  )
  assert_false(
    can_open_delete_dialog({ row: { seed, lead: None }, ordinal: None }),
  )
  assert_false(
    can_open_delete_dialog({
      row: {
        seed: { ..seed, can_delete: false },
        lead: lead_for(Some("# Ready")),
      },
      ordinal: None,
    }),
  )
  assert_true(
    can_open_delete_dialog({
      row: { seed, lead: lead_for(Some("# Ready")) },
      ordinal: None,
    }),
  )
}
