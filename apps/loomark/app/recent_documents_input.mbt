///| Recent-document presentation seeds are resolved here, at the app boundary.

///|
fn recent_entries(
  editing : EditingState,
) -> Array[@source_repository.CatalogEntry] {
  let persisted = editing.documents.snapshot().catalog().entries()
  let entries = editing.documents
    .current_sources()
    .filter_map(source => {
      let document_id = source.document_id()
      let persisted_entry = match
        persisted.search_by(entry => entry.document_id() == document_id) {
        Some(index) => persisted.get(index)
        None => None
      }
      let visible = persisted_entry is Some(_) ||
        source.text() != "" ||
        source.change_order().value() > 0L
      if visible {
        @source_repository.CatalogEntry::new(
          document_id,
          match persisted_entry {
            Some(entry) => entry.name()
            None => None
          },
          change_order=source.change_order(),
        )
      } else {
        None
      }
    })
  let ordered = @source_repository.Catalog::from_entries(entries)
    .unwrap()
    .entries()
    .to_owned()
  let document_id = editing.activation.document_id
  if editing.documents.is_untouched_new(document_id) {
    let visible = [
      @source_repository.CatalogEntry::new(document_id, Some("New document")).unwrap(),
    ]
    visible.append(ordered.view())
    visible
  } else {
    ordered
  }
}

///|
fn recent_document_seeds(
  editing : EditingState,
) -> @vector.Vector[@recent_documents.Seed] {
  let entries = recent_entries(editing)
  @vector.Vector(
    entries.map(entry => {
      let docid = entry.document_id()
      let status = match editing.documents.delete_status(docid) {
        Some(Available) => None
        Some(Failed(_, _)) => Some("Delete failed")
        Some(Waiting(_)) | Some(Deleting(_)) | Some(Probing(_)) =>
          Some("Deleting")
        Some(Unknown(_)) => Some("Unknown deletion outcome")
        None => None
      }
      let can_delete = match editing.documents.delete_status(docid) {
        Some(Available) | Some(Failed(_, _)) => true
        _ => false
      }
      @recent_documents.Seed::Seed(
        docid~,
        lead_source=editing.documents.lead_source(docid),
        selected=docid == editing.activation.document_id,
        can_select=can_select(editing, docid),
        can_delete~,
        untouched_new=editing.documents.is_untouched_new(docid),
        compact=editing.compact,
        status~,
      )
    })[:],
  )
}
