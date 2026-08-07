///|
/// Pure decisions for deferred after-render effects. The shell reads the
/// latest rendered model and executes the decision; the decision itself is
/// DOM-free and wbtest-able.
///
/// `repair_eligible` guards the raw/block input repair: a repair scheduled
/// for a specific mode, input generation, and source revision only writes
/// when the rendered model still matches all three. A missing model (no
/// render yet) is never eligible.
fn repair_eligible(
  current : DriverModel?,
  expected_mode : @core.ApplicationMode,
  expected_generation : Int,
  expected_revision : Int,
) -> Bool {
  match current {
    Some(current) =>
      current.state.mode() == expected_mode &&
      current.text_input_generation == expected_generation &&
      current.source_revision == expected_revision
    None => false
  }
}

///|
/// One post-render block selection outcome. `Apply(index)` is the only arm
/// that writes the DOM; the remaining arms classify why a scheduled
/// selection must not be applied.
enum BlockSelectionDecision {
  Apply(Int)
  ModeStale
  Superseded
  TargetUnavailable
  ModelUnavailable
} derive(Eq, Debug)

///|
/// Classify a scheduled block selection restore against the latest rendered
/// model: mode must still be Block, the revision must match the schedule,
/// and the immutable block view must resolve the target.
fn block_selection_effect_decision(
  current : DriverModel?,
  selection : BlockSelection,
  expected_revision : Int,
) -> BlockSelectionDecision {
  match current {
    None => BlockSelectionDecision::ModelUnavailable
    Some(model) =>
      if model.state.mode() != @core.Block {
        BlockSelectionDecision::ModeStale
      } else if model.source_revision != expected_revision {
        BlockSelectionDecision::Superseded
      } else {
        match block_selection_target(model.document, selection) {
          Some(index) => BlockSelectionDecision::Apply(index)
          None => BlockSelectionDecision::TargetUnavailable
        }
      }
  }
}
