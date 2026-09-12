///|
/// Resolve app state into the narrow Recent documents feature input.
fn recent_document_seeds(
  editing : EditingState,
) -> @vector.Vector[@recent_documents.Seed] {
  @vector.Vector(
    editing.documents.records.filter_map(record => {
      let id = record.document.id()
      // LeadSource is the presentation admission authority. An empty lead is
      // valid; only an untouched New document remains Unlisted.
      guard record.lead_source is Available(source) else { return None }
      let selection = if id == editing.activation.document_id {
        @recent_documents.Selection::Editing
      } else if editing.can_select(id) {
        @recent_documents.Selection::Selectable
      } else {
        @recent_documents.Selection::Blocked
      }
      let deletion = if editing.creation == Creating {
        @recent_documents.DeletionAvailability::Blocked
      } else {
        match record.delete {
          Available => @recent_documents.DeletionAvailability::Available
          Failed(_, _) => @recent_documents.DeletionAvailability::Failed
          Waiting(_) | Deleting(_) =>
            @recent_documents.DeletionAvailability::Pending
        }
      }
      let status = match record.save {
        Saved => @recent_documents.RowStatus::Saved
        _ => @recent_documents.RowStatus::Unsaved
      }
      Some(
        @recent_documents.Seed::Seed(
          docid=id,
          source~,
          selection~,
          deletion~,
          status~,
        ),
      )
    })[:],
  )
}
