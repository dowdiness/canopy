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
/// Production authority adoption never reads the semantic attachment. The
/// projection Worker materializes and returns the demanded artifact.
fn update_preview_after_authority(
  attachment : @md_markdown.MarkdownSemanticAttachment,
  model : DriverModel,
  old_requested : Bool,
  accepted~ : Bool,
  changed~ : Bool,
) -> DriverModel {
  ignore(attachment)
  ignore(old_requested)
  ignore(changed)
  if accepted && !preview_requested(model) {
    projection_trace_current_request_no_demand()
  }
  model
}

///|
fn projection_demand_for_model(model : DriverModel) -> ProjectionDemand {
  {
    block: model.state.mode() == @core.Block,
    preview: preview_requested(model),
    diagnostics: false,
  }
}

///|
fn projection_pending_model(model : DriverModel) -> DriverModel {
  {
    ..model,
    error: Some("Projection is pending for the accepted document."),
    error_code: Some("projection-pending"),
    error_operation: Some("projection-demand"),
  }
}

///|
fn projection_failed_model(model : DriverModel, detail : String) -> DriverModel {
  {
    ..model,
    semantic_document: None,
    error: Some("Projection failed: " + detail),
    error_code: Some("projection-failed"),
    error_operation: Some("projection-execution"),
  }
}

///|
fn update_projection_demand(
  session : ProjectionSession,
  model : DriverModel,
) -> DriverModel {
  session.demand(projection_demand_for_model(model)) catch {
    error => return projection_failed_model(model, error.to_string())
  }
  model
}

///|
fn update_preview_document_with_projection(
  attachment : @md_markdown.MarkdownSemanticAttachment,
  projection_session : @ref.Ref[ProjectionSession?],
  model : DriverModel,
  old_requested : Bool,
  accepted~ : Bool,
  changed~ : Bool,
) -> DriverModel {
  match projection_session.val {
    None => {
      ignore(attachment)
      model
    }
    Some(session) => {
      let decision = preview_document_decision(
        old_requested,
        preview_requested(model),
        accepted~,
        changed~,
      )
      match decision {
        PreviewDocumentRead => {
          let demand = projection_demand_for_model(model)
          session.demand(demand) catch {
            error => return projection_failed_model(model, error.to_string())
          }
          let document = session.preview_document() catch {
            error => return projection_failed_model(model, error.to_string())
          }
          match document {
            Some(document) =>
              {
                ..model,
                semantic_document: Some(document),
                semantic_read_count: model.semantic_read_count + 1,
              }
            None => projection_pending_model(model)
          }
        }
        PreviewDocumentKeep | PreviewDocumentClear =>
          if decision is PreviewDocumentClear {
            { ..model, semantic_document: None }
          } else {
            model
          }
      }
    }
  }
}
