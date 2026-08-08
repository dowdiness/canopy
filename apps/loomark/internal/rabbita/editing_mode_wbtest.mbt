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
  let raw = RawInput("source", None, None)
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
/// Every Block* variant is gated together; representative coverage for each
/// so a future misclassification cannot evade the matrix.
fn block_variants() -> Array[EditingEvent] {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title\n\nParagraph",
  )
  let node_id = (try! editor.snapshot()).blocks()[0].node_id()
  [
    BlockFocused("key"),
    BlockHeading(2, None),
    BlockToggleList(None),
    BlockDelete,
    BlockInput(
      token=0,
      input=PendingBlockInput::PendingBlockInput(
        document_id=@archive.LoomarkDocumentId::from_string("test-document") catch {
          _ => abort("test document id must construct")
        },
        expected_version=editor.version(),
        node_id~,
        input_id="in",
        text="t",
        selection=@dom_boundary.TextSelection(0, 0, @dom_boundary.NoDirection),
      ),
    ),
    BlockSplit(node_id~, offset=0),
    BlockMerge(node_id~, selection=BlockSelection::{
      key: "k",
      index: 0,
      start: 0,
      end: 0,
    }),
    BlockNavigate(key="k", direction=1),
  ]
}

///|
test "every block editing variant requires Block mode" {
  for variant in block_variants() {
    assert_eq(editing_mode_applicable(variant, block_mode(), false), None)
    assert_eq(
      editing_mode_applicable(variant, raw_mode(), false),
      Some("Block editing is unavailable outside Block mode"),
    )
  }
}

///|
test "selection read applies the driver probe result to the model" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title",
  )
  let next = apply_selection_read(
    test_model(try! editor.snapshot(), editor.version()),
    3,
    5,
  )
  assert_eq(next.selection, Some("3:5"))
}

///|
test "measurement applies the driver probe result to the model" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="agent-a",
    source="# Title",
  )
  let next = apply_measurement(
    test_model(try! editor.snapshot(), editor.version()),
    640.0,
    480.0,
  )
  assert_eq(next.measurement, Some("640:480"))
  let fractional = apply_measurement(
    test_model(try! editor.snapshot(), editor.version()),
    120.5,
    48.25,
  )
  assert_eq(fractional.measurement, Some("120.5:48.25"))
}
