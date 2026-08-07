///|
/// Pure decisions for deferred after-render effects. The shell reads the
/// latest rendered model and executes the decision; the decision itself is
/// DOM-free and wbtest-able.
///
/// `repair_eligible` guards the raw/block input repair: a repair scheduled
/// for a specific mode, input generation, and source revision only writes
/// when the rendered model still matches all three. Preview repairs also
/// require the split Raw surface to remain rendered. A missing model (no
/// render yet) is never eligible.
fn repair_eligible(
  current : DriverModel?,
  expected_mode : @core.ApplicationMode,
  expected_generation : Int,
  expected_revision : Int,
) -> Bool {
  match current {
    Some(current) => {
      let control_rendered = match expected_mode {
        @core.Raw => true
        @core.Preview => current.split_preview_open
        @core.Block => true
      }
      current.state.mode() == expected_mode &&
      current.text_input_generation == expected_generation &&
      current.source_revision == expected_revision &&
      control_rendered
    }
    None => false
  }
}

///|
/// A Raw repair is valid while the Raw control is still rendered. In split
/// Preview the application mode is Preview, but the Raw textarea remains in
/// the DOM; Block mode never provides a valid Raw repair target.
fn raw_input_repair_eligible(
  current : DriverModel?,
  expected_generation : Int,
  expected_revision : Int,
) -> Bool {
  match current {
    Some(current) =>
      current.text_input_generation == expected_generation &&
      current.source_revision == expected_revision &&
      (
        current.state.mode() == @core.Raw ||
        (current.state.mode() == @core.Preview && current.split_preview_open)
      )
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
