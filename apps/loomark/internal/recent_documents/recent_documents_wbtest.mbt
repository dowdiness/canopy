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
    render_row(
      "one",
      presented[0],
      @cmd.Emit(_ => @cmd.none),
      @cmd.none,
      @html.nothing,
    )
  })
  let second = @rabbita_testing.server_side_render(() => {
    render_row(
      "two",
      presented[1],
      @cmd.Emit(_ => @cmd.none),
      @cmd.none,
      @html.nothing,
    )
  })
  assert_true(first.contains("(1 of 2)"))
  assert_true(second.contains("(2 of 2)"))
  assert_eq(
    delete_confirmation_label(presented[0]),
    "Delete \"" + row_label(presented[0]) + "\"?",
  )
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
