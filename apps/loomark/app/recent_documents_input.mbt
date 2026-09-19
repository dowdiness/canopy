///|
/// Resolve app state into the narrow Recent documents feature input.
fn recent_document_seeds(
  editing : EditingState,
) -> @vector.Vector[@recent_documents.Seed[@documents.Key]] {
  @vector.Vector(
    editing.documents
    .recent()
    .map(item => {
      let (id, source, save, deletion_status) = item
      let selection = if id == editing.activation.key {
        @recent_documents.Selection::Editing
      } else if editing.can_select(id) {
        @recent_documents.Selection::Selectable
      } else {
        @recent_documents.Selection::Blocked
      }
      let deletion = if editing.creation == Creating {
        @recent_documents.DeletionAvailability::Blocked
      } else {
        match deletion_status {
          @documents.DeleteStatus::Deletable =>
            @recent_documents.DeletionAvailability::Available
          @documents.DeleteStatus::DeleteFailed(_) =>
            @recent_documents.DeletionAvailability::Failed
          @documents.DeleteStatus::NotDeletable =>
            @recent_documents.DeletionAvailability::Blocked
          @documents.DeleteStatus::DeletePending =>
            @recent_documents.DeletionAvailability::Pending
        }
      }
      let status = match save {
        @documents.SaveStatus::Clean => @recent_documents.RowStatus::Saved
        _ => @recent_documents.RowStatus::Unsaved
      }
      @recent_documents.Seed::Seed(
        docid=id,
        source~,
        selection~,
        deletion~,
        status~,
      )
    })[:],
  )
}
