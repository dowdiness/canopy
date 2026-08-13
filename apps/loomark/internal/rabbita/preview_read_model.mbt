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
      let document = attachment.document()
      projection_trace_semantic_attachment_read()
      {
        ..model,
        semantic_document: Some(document),
        semantic_read_count: model.semantic_read_count + 1,
      }
    }
    PreviewDocumentKeep => model
    PreviewDocumentClear => { ..model, semantic_document: None }
  }
}

/// Apply Preview demand after one authority request, then finalize that exact
/// trace request from the resulting artifact state.
fn update_preview_after_authority(
  attachment : @md_markdown.MarkdownSemanticAttachment,
  model : DriverModel,
  old_requested : Bool,
  accepted~ : Bool,
  changed~ : Bool,
) -> DriverModel {
  let decision = preview_document_decision(
    old_requested,
    preview_requested(model),
    accepted~,
    changed~,
  )
  let next = update_preview_document(
    attachment, model, old_requested, accepted~, changed~,
  )
  if accepted {
    match decision {
      PreviewDocumentRead => ()
      PreviewDocumentKeep =>
        if preview_requested(next) {
          if next.semantic_document is Some(_) {
            projection_trace_retained_preview_materialized()
          } else {
            projection_trace_generation_invalidated()
          }
        } else {
          projection_trace_current_request_no_demand()
        }
      PreviewDocumentClear => projection_trace_current_request_no_demand()
    }
  }
  next
}
