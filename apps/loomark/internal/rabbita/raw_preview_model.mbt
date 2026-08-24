///|
/// Rabbita model for speculative Raw Preview values. Browser-owned draft
/// source and Worker handles deliberately remain outside this model.
priv enum RawPreviewModel {
  Disabled
  Enabled(StampedPreviewProjection?)
} derive(Eq)

///|
fn RawPreviewModel::enabled() -> RawPreviewModel {
  Enabled(None)
}

///|
fn RawPreviewModel::disabled() -> RawPreviewModel {
  Disabled
}

///|
fn RawPreviewModel::artifact(
  self : RawPreviewModel,
) -> StampedPreviewProjection? {
  match self {
    Disabled => None
    Enabled(artifact) => artifact
  }
}

///|
fn RawPreviewModel::clear(self : RawPreviewModel) -> RawPreviewModel {
  match self {
    Disabled => Disabled
    Enabled(_) => Enabled(None)
  }
}

///|
/// Value-level result delivered by the Raw Preview runtime to its update.
priv enum RawPreviewMsg {
  ProjectionCompleted(Int, ProjectionStamp, String, String)
}

///|
priv enum RawPreviewResult {
  Ready(String, ProjectionStamp, NormalizedPreviewProjection)
  Empty
  Failed
}

///|
priv enum RawPreviewDecision {
  Adopted
  Rejected
  Recover(String)
  Stopped
}

///|
/// Pure Rabbita update. It adopts only an artifact produced for the currently
/// demanded browser source and describes recovery without executing it.
fn update_raw_preview(
  result : RawPreviewResult,
  model : RawPreviewModel,
  current_source~ : String,
  demanded~ : Bool,
  speculative~ : Bool,
) -> (RawPreviewModel, RawPreviewDecision) {
  guard model is Enabled(_) else { return (model, Rejected) }
  guard demanded && speculative else { return (model.clear(), Stopped) }
  match result {
    Ready(source, stamp, preview) =>
      if demanded && source == current_source && preview.source == source {
        (Enabled(Some({ stamp, preview })), Adopted)
      } else {
        (model, Rejected)
      }
    Empty => (model, Rejected)
    Failed => (model.clear(), Recover(current_source))
  }
}
