///|
/// Basic presentation invariants stay inside the feature.
test "rendered duplicate bounded labels match confirmation labels" {
  let source = "# " + "a".repeat(80) + "\n\nDescription"
  let seeds = @vector.Vector([
    Seed::Seed(
      docid="one",
      source~,
      selection=Selection::Editing,
      deletion=DeletionAvailability::Available,
      status=RowStatus::Saved,
    ),
    Seed::Seed(
      docid="two",
      source~,
      selection=Selection::Selectable,
      deletion=DeletionAvailability::Available,
      status=RowStatus::Saved,
    ),
  ])
  let presented = rows_presented(
    seeds.map(seed => { seed, lead: @document_lead.extract(seed.source), }),
  ).to_array()
  let first = @rabbita_testing.server_side_render(() => {
    render_row("one", presented[0], @cmd.Emit(_ => @cmd.none), @cmd.none)
  })
  let second = @rabbita_testing.server_side_render(() => {
    render_row("two", presented[1], @cmd.Emit(_ => @cmd.none), @cmd.none)
  })
  assert_true(first.contains("(1 of 2)"))
  assert_true(second.contains("(2 of 2)"))
  assert_true(
    first.contains(
      "aria-label=\"Delete &quot;" + row_label(presented[0]) + "&quot;\"",
    ),
  )
  assert_true(
    first.contains(
      "title=\"Delete &quot;" + row_label(presented[0]) + "&quot;\"",
    ),
  )
  assert_eq(
    delete_confirmation_label(presented[0]),
    "Delete \"" + row_label(presented[0]) + "\"?",
  )
}

///|
test "delete controls reflect availability in SSR" {
  let source = "# Document"
  let deletion_states = [
    (DeletionAvailability::Available, true),
    (DeletionAvailability::Failed, true),
    (DeletionAvailability::Blocked, false),
    (DeletionAvailability::Pending, false),
  ]
  for (deletion, enabled) in deletion_states {
    let seed = Seed::Seed(
      docid="document",
      source~,
      selection=Selection::Selectable,
      deletion~,
      status=RowStatus::Saved,
    )
    let presented = rows_presented(
        @vector.Vector([{ seed, lead: @document_lead.extract(source), }]),
      ).to_array()[0]
    let rendered = @rabbita_testing.server_side_render(() => {
      render_row("document", presented, @cmd.Emit(_ => @cmd.none), @cmd.none)
    })
    assert_true(rendered.contains("Delete &quot;Document&quot;"))
    if enabled {
      assert_false(rendered.contains("aria-disabled=\"true\""))
    } else {
      assert_true(rendered.contains("aria-disabled=\"true\""))
    }
  }
}

///|
test "bounded lead labels do not expose omitted source" {
  let source = "# " + "a".repeat(80) + "SECRET\n\nDescription"
  let seed = Seed::Seed(
    docid="one",
    source~,
    selection=Selection::Editing,
    deletion=DeletionAvailability::Available,
    status=RowStatus::Saved,
  )
  let lead = @document_lead.extract(seed.source)
  assert_false(lead.primary().contains("SECRET"))
  assert_true(lead.primary_truncated())
  assert_true(row_base_label({ seed, lead, }) != "Empty document")
}
