///|
/// Editing mode-gate boundary matrix:
///
/// | event | mode | split_preview_open | applicable |
/// | --- | --- | --- | --- |
/// | ReplaceSource / ProbeBlockSelection | any | any | yes |
/// | RawInput | Raw | any | yes |
/// | RawInput | Preview | true | yes |
/// | RawInput | Preview | false | no |
/// | RawInput | Block | any | no |
/// | Block* | Block | any | yes |
/// | Block* | Raw / Preview | any | no |
///
/// The rejection messages are part of the driver contract (Playwright
/// asserts error_operation strings) and are pinned here.
fn raw_mode() -> @core.ApplicationMode {
  @core.Raw
}

///|
fn block_mode() -> @core.ApplicationMode {
  @core.Block
}

///|
fn preview_mode() -> @core.ApplicationMode {
  @core.Preview
}

///|
test "source replacement and the block selection probe are exempt from the mode gate" {
  assert_eq(
    editing_mode_applicable(ReplaceSource("x"), raw_mode(), false),
    None,
  )
  assert_eq(
    editing_mode_applicable(ReplaceSource("x"), block_mode(), false),
    None,
  )
  assert_eq(
    editing_mode_applicable(ProbeBlockSelection("stale"), preview_mode(), false),
    None,
  )
}

///|
test "raw input requires Raw mode or a split-open Preview" {
  let raw = RawInput("source", None)
  assert_eq(editing_mode_applicable(raw, raw_mode(), false), None)
  assert_eq(editing_mode_applicable(raw, preview_mode(), true), None)
  assert_eq(
    editing_mode_applicable(raw, preview_mode(), false),
    Some("Raw input is unavailable outside Raw mode"),
  )
  assert_eq(
    editing_mode_applicable(raw, block_mode(), false),
    Some("Raw input is unavailable outside Raw mode"),
  )
}

///|
test "block editing requires Block mode" {
  let heading = BlockHeading(2, None)
  assert_eq(editing_mode_applicable(heading, block_mode(), false), None)
  assert_eq(
    editing_mode_applicable(heading, raw_mode(), false),
    Some("Block editing is unavailable outside Block mode"),
  )
  assert_eq(
    editing_mode_applicable(BlockDelete, preview_mode(), true),
    Some("Block editing is unavailable outside Block mode"),
  )
}

///|
test "selection read applies the driver probe result to the model" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title",
  )
  let next = apply_selection_read(test_model(editor.snapshot()), 3, 5)
  assert_eq(next.selection, Some("3:5"))
}

///|
test "measurement applies the driver probe result to the model" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title",
  )
  let next = apply_measurement(test_model(editor.snapshot()), 640.0, 480.0)
  assert_eq(next.measurement, Some("640:480"))
}
