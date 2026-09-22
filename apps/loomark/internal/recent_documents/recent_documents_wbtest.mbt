///|
/// Basic presentation invariants stay inside the feature.
test "rendered duplicate bounded labels match confirmation labels" {
  let source = "# " + "a".repeat(80) + "\n\nDescription"
  let seeds = @vector.Vector([
    Seed::Seed(
      docid="one",
      source~,
      selection=Selection::Editing,
      deletion=DeletionAvailability::Available(ThisBrowser),
      status=RowStatus::Saved,
    ),
    Seed::Seed(
      docid="two",
      source~,
      selection=Selection::Selectable,
      deletion=DeletionAvailability::Available(ThisBrowser),
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
  assert_true(first.contains("aria-description=\"Description\""))
  assert_false(first.contains("loomark-document-description-"))
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
  assert_eq(
    delete_confirmation_description(presented[0]),
    "This removes the document from this browser.",
  )
}

///|
test "typed document ids pass through intents unchanged" {
  let seed = Seed::Seed(
    docid=42,
    source="# Typed",
    selection=Selection::Selectable,
    deletion=DeletionAvailability::Available(AllDevices),
    status=RowStatus::Saved,
  )
  assert_eq(seed.docid(), 42)
  let _feature = build(
    input=@rabbita.Val::constant(@vector.Vector([seed])),
    visible=@rabbita.Val::constant(true),
    can_create=@rabbita.Val::constant(true),
    compact=@rabbita.Val::constant(false),
    delete_target=@rabbita.Val::constant(Some(42)),
    on_intent=@cmd.Emit((_ : Intent[Int]) => @cmd.none),
    lifecycle_key=id => id.to_string(),
    close_after_action=@cmd.none,
  )
  let select : Intent[Int] = Intent::Select(42)
  let request_delete : Intent[Int] = Intent::RequestDelete(42)
  let confirm_delete : Intent[Int] = Intent::ConfirmDelete(42)
  match select {
    Select(id) => assert_eq(id, 42)
    _ => fail("expected Select")
  }
  match request_delete {
    RequestDelete(id) => assert_eq(id, 42)
    _ => fail("expected RequestDelete")
  }
  match confirm_delete {
    ConfirmDelete(id) => assert_eq(id, 42)
    _ => fail("expected ConfirmDelete")
  }
}

///|
test "delete controls reflect availability in SSR" {
  let source = "# Document"
  let deletion_states = [
    (DeletionAvailability::Available(ThisBrowser), true),
    (DeletionAvailability::Failed(ThisBrowser), true),
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
    deletion=DeletionAvailability::Available(ThisBrowser),
    status=RowStatus::Saved,
  )
  let lead = @document_lead.extract(seed.source)
  assert_false(lead.primary().contains("SECRET"))
  assert_true(lead.primary_truncated())
  assert_true(row_base_label({ seed, lead, }) != "Empty document")
}
