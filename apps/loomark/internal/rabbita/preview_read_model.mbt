///|
/// Pure preview read-model decision. The shell reads the attachment only when
/// this boundary returns `PreviewDocumentRead`.
#warnings("-unused_value")
priv enum PreviewDocumentDecision {
  PreviewDocumentRead
  PreviewDocumentKeep
  PreviewDocumentClear
} derive(Eq, Debug)

///|
fn preview_document_decision(
  old_requested : Bool,
  next_requested : Bool,
  accepted~ : Bool,
  changed~ : Bool,
) -> PreviewDocumentDecision {
  if !accepted {
    PreviewDocumentKeep
  } else if !next_requested {
    PreviewDocumentClear
  } else if !old_requested || changed {
    PreviewDocumentRead
  } else {
    PreviewDocumentKeep
  }
}

///|
/// Aggregate document-level Preview demand independently from the active mode.
fn preview_requested(model : DriverModel) -> Bool {
  model.state.mode() == @core.Preview || model.split_preview_open
}

///|
/// Imperative shell around `preview_document_decision`; this is the sole
/// application read site for the mount-owned semantic attachment.
fn update_preview_document(
  attachment : @md_markdown.MarkdownSemanticAttachment,
  model : DriverModel,
  old_requested : Bool,
  accepted~ : Bool,
  changed~ : Bool,
) -> DriverModel {
  match
    preview_document_decision(
      old_requested,
      preview_requested(model),
      accepted~,
      changed~,
    ) {
    PreviewDocumentRead => {
      projection_trace_begin_demand_group(
        next_requested=(!old_requested && preview_requested(model)),
      )
      projection_trace_semantic_attachment_read()
      {
        ..model,
        semantic_document: Some(attachment.document()),
        semantic_read_count: model.semantic_read_count + 1,
      }
    }
    PreviewDocumentKeep => model
    PreviewDocumentClear => { ..model, semantic_document: None }
  }
}
