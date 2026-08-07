///|
/// Deferred-effect decision boundary matrix:
///
/// `repair_eligible`:
/// | current | expected mode | expected generation | expected revision | eligible |
/// | --- | --- | --- | --- | --- |
/// | None | any | any | any | false |
/// | Some | mismatch | — | — | false |
/// | Some | match | mismatch | — | false |
/// | Some | match | match | mismatch | false |
/// | Some | match | match | match | true |
///
/// `block_selection_effect_decision`:
/// | current | mode | revision | target | decision |
/// | --- | --- | --- | --- | --- |
/// | None | — | — | — | ModelUnavailable |
/// | Some | != Block | — | — | ModeStale |
/// | Some | Block | mismatch | — | Superseded |
/// | Some | Block | match | found | Apply(index) |
/// | Some | Block | match | missing | TargetUnavailable |

///|
test "repair_eligible skips before any model has rendered" {
  assert_false(repair_eligible(None, @core.Raw, 1, 1))
}

///|
test "repair_eligible requires mode, generation, and revision to match" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title",
  )
  let model = {
    ..test_model(editor.snapshot()),
    text_input_generation: 3,
    source_revision: 7,
  }
  assert_false(repair_eligible(Some(model), @core.Block, 3, 7))
  assert_false(repair_eligible(Some(model), @core.Raw, 4, 7))
  assert_false(repair_eligible(Some(model), @core.Raw, 3, 8))
  assert_true(repair_eligible(Some(model), @core.Raw, 3, 7))
  let preview = {
    ..model,
    state: @core.ApplicationState::ApplicationState(@core.Preview),
    split_preview_open: true,
  }
  assert_true(repair_eligible(Some(preview), @core.Preview, 3, 7))
  assert_false(
    repair_eligible(
      Some({ ..preview, split_preview_open: false }),
      @core.Preview,
      3,
      7,
    ),
  )
}

///|
test "raw repair requires a rendered Raw control" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title",
  )
  let model = {
    ..test_model(editor.snapshot()),
    text_input_generation: 3,
    source_revision: 7,
  }
  assert_true(raw_input_repair_eligible(Some(model), 3, 7))
  assert_true(
    raw_input_repair_eligible(
      Some({
        ..model,
        state: @core.ApplicationState::ApplicationState(@core.Preview),
        split_preview_open: true,
      }),
      3,
      7,
    ),
  )
  assert_false(
    raw_input_repair_eligible(
      Some({
        ..model,
        state: @core.ApplicationState::ApplicationState(@core.Preview),
        split_preview_open: false,
      }),
      3,
      7,
    ),
  )
  assert_false(
    raw_input_repair_eligible(
      Some({
        ..model,
        state: @core.ApplicationState::ApplicationState(@core.Block),
      }),
      3,
      7,
    ),
  )
}

///|
test "block selection decision applies when mode and revision match and target resolves" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title\n\nParagraph",
  )
  let document = editor.snapshot()
  let key = document.blocks()[0].key()
  let selection = BlockSelection::{ key, index: 0, start: 0, end: 0 }
  let model = {
    ..test_model(document),
    state: @core.ApplicationState::ApplicationState(@core.Block),
    source_revision: 7,
  }
  assert_eq(
    block_selection_effect_decision(Some(model), selection, 7),
    BlockSelectionDecision::Apply(0),
  )
}

///|
test "block selection decision classifies stale mode, superseded revision, missing target, and no model" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title\n\nParagraph",
  )
  let document = editor.snapshot()
  let key = document.blocks()[0].key()
  let selection = BlockSelection::{ key, index: 0, start: 0, end: 0 }
  let model = {
    ..test_model(document),
    state: @core.ApplicationState::ApplicationState(@core.Block),
    source_revision: 7,
  }
  assert_eq(
    block_selection_effect_decision(Some(model), selection, 6),
    BlockSelectionDecision::Superseded,
  )
  assert_eq(
    block_selection_effect_decision(
      Some({
        ..model,
        state: @core.ApplicationState::ApplicationState(@core.Raw),
      }),
      selection,
      7,
    ),
    BlockSelectionDecision::ModeStale,
  )
  assert_eq(
    block_selection_effect_decision(None, selection, 7),
    BlockSelectionDecision::ModelUnavailable,
  )
  let missing = BlockSelection::{
    key: "no-such-key",
    index: 0,
    start: 0,
    end: 0,
  }
  assert_eq(
    block_selection_effect_decision(Some(model), missing, 7),
    BlockSelectionDecision::TargetUnavailable,
  )
}
