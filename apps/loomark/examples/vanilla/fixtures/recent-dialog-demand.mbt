///|
fn demand_dialog_fixture() -> @rabbita.Val[@html.Html] {
  let input = @rabbita.Val::constant(@vector.Vector([
    @recent_documents.Seed(
      docid="a",
      source="# Shared\n",
      selection=@recent_documents.Selection::Selectable,
      deletion=@recent_documents.DeletionAvailability::Available,
      status=@recent_documents.RowStatus::Saved,
    ),
    @recent_documents.Seed(
      docid="b",
      source="# Shared\n",
      selection=@recent_documents.Selection::Selectable,
      deletion=@recent_documents.DeletionAvailability::Available,
      status=@recent_documents.RowStatus::Saved,
    ),
    @recent_documents.Seed(
      docid="c",
      source="# Other\n",
      selection=@recent_documents.Selection::Selectable,
      deletion=@recent_documents.DeletionAvailability::Available,
      status=@recent_documents.RowStatus::Saved,
    ),
  ]))
  let feature = @recent_documents.build(
    input~,
    visible=@rabbita.Val::constant(false),
    can_create=@rabbita.Val::constant(true),
    compact=@rabbita.Val::constant(false),
    delete_target=@rabbita.Val::constant(Some("b")),
    on_intent=@cmd.Emit(_ => @rabbita.none),
    close_after_action=@rabbita.none,
  )
  feature.navigation().map2(
    feature.dialog(),
    (navigation, dialog) => @html.div([navigation, dialog]),
  )
}
