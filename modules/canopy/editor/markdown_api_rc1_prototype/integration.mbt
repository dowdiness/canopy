// PROTOTYPE — integration checks against the real Markdown façade.

///|
struct IntegrationCase {
  name : String
  passed : Bool
  detail : String
}

///|
struct IntegrationReport {
  cases : Array[IntegrationCase]
  passed : Bool
}

///|
fn snapshot_hidden_ranges(
  snapshot : @markdown_editor.MarkdownDocumentSnapshot,
) -> Array[HiddenRange] {
  let source = snapshot.source()
  let hidden : Array[HiddenRange] = []
  for block in snapshot.blocks().to_array() {
    let (start, end) = block.text_range()
    if block.text().is_empty() && source[start:end] == "\u200B" {
      hidden.push({ start, end })
    }
  }
  hidden
}

///|
fn hidden_inside_inserted_text(
  hidden_after : Array[HiddenRange],
  transform : @markdown_editor.MarkdownTextTransform,
) -> Array[HiddenRange] {
  let inserted_end = transform.start() + transform.inserted().length()
  hidden_after.filter_map(range => {
    if range.start >= transform.start() && range.end <= inserted_end {
      Some({
        start: range.start - transform.start(),
        end: range.end - transform.start(),
      })
    } else {
      None
    }
  })
}

///|
fn map_actual_transform(
  hidden_before : Array[HiddenRange],
  hidden_after : Array[HiddenRange],
  transform : @markdown_editor.MarkdownTextTransform,
) -> PublicTransform {
  let start = transform.start()
  let end = start + transform.delete_len()
  let inserted_hidden = hidden_inside_inserted_text(hidden_after, transform)
  {
    start: visible_offset(hidden_before, start),
    delete_len: visible_offset(hidden_before, end) -
    visible_offset(hidden_before, start),
    inserted: project_source(transform.inserted(), inserted_hidden),
  }
}

///|
fn public_range_valid(
  source : String,
  hidden : Array[HiddenRange],
  start : Int,
  end : Int,
) -> Bool {
  let public_start = visible_offset(hidden, start)
  let public_end = visible_offset(hidden, end)
  public_start >= 0 &&
  public_start <= public_end &&
  public_end <= project_source(source, hidden).length()
}

///|
fn optional_public_range_valid(
  source : String,
  hidden : Array[HiddenRange],
  range : (Int, Int)?,
) -> Bool {
  match range {
    None => true
    Some((start, end)) => public_range_valid(source, hidden, start, end)
  }
}

///|
fn snapshot_ranges_valid(
  snapshot : @markdown_editor.MarkdownDocumentSnapshot,
  hidden : Array[HiddenRange],
) -> Bool {
  let internal_source = snapshot.source()
  let public_source = project_source(internal_source, hidden)
  for block in snapshot.blocks().to_array() {
    let (source_start, source_end) = block.source_range()
    let (text_start, text_end) = block.text_range()
    let public_text_start = visible_offset(hidden, text_start)
    let public_text_end = visible_offset(hidden, text_end)
    if !public_range_valid(internal_source, hidden, source_start, source_end) ||
      !public_range_valid(internal_source, hidden, text_start, text_end) ||
      !optional_public_range_valid(
        internal_source,
        hidden,
        block.marker_range(),
      ) ||
      !optional_public_range_valid(
        internal_source,
        hidden,
        block.fence_open_range(),
      ) ||
      !optional_public_range_valid(
        internal_source,
        hidden,
        block.fence_close_range(),
      ) {
      return false
    }
    if public_source[public_text_start:public_text_end] != block.text() {
      return false
    }
  }
  true
}

///|
fn snapshot_from_result(
  result : @markdown_editor.MarkdownCommitResult,
) -> @markdown_editor.MarkdownDocumentSnapshot {
  match result {
    Applied(snapshot, _) => snapshot
    Unchanged(snapshot) => snapshot
  }
}

///|
fn run_actual_edit_case(
  name : String,
  source : String,
  request : (@markdown_editor.MarkdownEditor) -> @markdown_editor.MarkdownEditRequest raise,
) -> IntegrationCase raise {
  let editor = @markdown_editor.MarkdownEditor(agent_id=name, source~)
  let before = editor.snapshot()
  let hidden_before = snapshot_hidden_ranges(before)
  let public_before = project_source(before.source(), hidden_before)
  let receipt = match editor.commit_with_receipt(request(editor)) {
    Ok(receipt) => receipt
    Err(_) => return { name, passed: false, detail: "edit rejected" }
  }
  let after = snapshot_from_result(receipt.result())
  let hidden_after = snapshot_hidden_ranges(after)
  let public_after = project_source(after.source(), hidden_after)
  let exported_after = editor.portable_markdown()
  let transforms = receipt.transforms().to_array()
  guard transforms is [transform] else {
    return {
      name,
      passed: false,
      detail: "expected one real Markdown transform",
    }
  }
  let public_transform = map_actual_transform(
    hidden_before, hidden_after, transform,
  )
  let projected = apply_transform(public_before, public_transform)
  let ranges_valid = snapshot_ranges_valid(after, hidden_after)
  let passed = projected == public_after &&
    public_after == exported_after &&
    ranges_valid
  let detail = if passed {
    "portable transform, export, and block ranges agree"
  } else if projected != public_after {
    let before_text = public_before.escape()
    let projected_text = projected.escape()
    let after_text = public_after.escape()
    let inserted_text = public_transform.inserted.escape()
    "mapped transform start=\{public_transform.start} delete=\{public_transform.delete_len} insert=\{inserted_text}; before=\{before_text}; projected=\{projected_text}; after=\{after_text}"
  } else if public_after != exported_after {
    "hidden-range projection disagrees with portable export"
  } else {
    "one or more mapped block ranges disagree with block text"
  }
  { name, passed, detail }
}

///|
fn first_block(
  editor : @markdown_editor.MarkdownEditor,
) -> @markdown_editor.MarkdownBlockSnapshot raise {
  match editor.snapshot().blocks().to_array() {
    [first, ..] => first
    [] => fail("prototype expected a projected Markdown block")
  }
}

///|
fn second_block(
  editor : @markdown_editor.MarkdownEditor,
) -> @markdown_editor.MarkdownBlockSnapshot raise {
  match editor.snapshot().blocks().to_array() {
    [_, second, ..] => second
    _ => fail("prototype expected two projected Markdown blocks")
  }
}

///|
fn run_snapshot_case(name : String, source : String) -> IntegrationCase raise {
  let editor = @markdown_editor.MarkdownEditor(agent_id=name, source~)
  let snapshot = editor.snapshot()
  let hidden = snapshot_hidden_ranges(snapshot)
  let passed = snapshot_ranges_valid(snapshot, hidden) &&
    project_source(snapshot.source(), hidden) == editor.portable_markdown()
  {
    name,
    passed,
    detail: if passed {
      "all public block ranges agree with portable source"
    } else {
      "one or more public block ranges disagree with portable source"
    },
  }
}

///|
fn run_integration_matrix() -> IntegrationReport raise {
  let cases : Array[IntegrationCase] = [
    run_actual_edit_case("real split inserts hidden sentinel (LF)", "Hello\n", editor => {
      let block = first_block(editor)
      @markdown_editor.MarkdownEditRequest::SplitBlock(
        node_id=block.node_id(),
        offset=0,
      )
    }),
    run_actual_edit_case(
      "real split inserts hidden sentinel (CRLF)",
      "Hello\r\n",
      editor => {
        let block = first_block(editor)
        @markdown_editor.MarkdownEditRequest::SplitBlock(
          node_id=block.node_id(),
          offset=0,
        )
      },
    ),
    run_actual_edit_case("real non-BMP block edit", "😀\n", editor => {
      let block = first_block(editor)
      @markdown_editor.MarkdownEditRequest::CommitEdit(
        node_id=block.node_id(),
        new_text="🚀",
      )
    }),
    run_actual_edit_case(
      "real merge deletes hidden sentinel",
      "\u200B\n\nHello\n",
      editor => {
        let block = second_block(editor)
        @markdown_editor.MarkdownEditRequest::MergeWithPrevious(
          node_id=block.node_id(),
        )
      },
    ),
    run_actual_edit_case("real user ZWSP inside visible text", "A\u200BB\n", editor => {
      let block = first_block(editor)
      @markdown_editor.MarkdownEditRequest::CommitEdit(
        node_id=block.node_id(),
        new_text="A\u200BC",
      )
    }),
    run_snapshot_case("ATX heading ranges", "## Heading\r\n"),
    run_snapshot_case("Setext heading ranges", "Heading\r\n===\r\n"),
    run_snapshot_case("fenced code ranges", "```mbt\r\n😀\r\n```\r\n"),
    run_snapshot_case("ordered list ranges", "1. A\r\n2. B\r\n"),
  ]
  { cases, passed: cases.all(item => item.passed) }
}
