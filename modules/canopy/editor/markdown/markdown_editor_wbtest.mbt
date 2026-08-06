///| The first public headless Markdown façade seam.

///|
fn fresh_markdown_ir(source : String) -> @md_markdown.MarkdownIR {
  let parser = @loom.new_parser(
    @loom.SourceId("markdown-editor-semantic-fresh"),
    source,
    @md_markdown.markdown_grammar,
  )
  let snapshot = parser.snapshot().read_or_abort()
  @md_markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    parser.source_id(),
    snapshot.syntax,
    snapshot.diagnostics,
  )
}

///|
test "semantic attachment follows MarkdownEditor source commits" {
  let source = "# Heading [ref]\n\nBefore\n\n[ref]: /one \"title\"\n"
  let (editor, attachment) = try! MarkdownEditor::with_semantic_attachment(
    agent_id="markdown-semantic-facade",
    source~,
  )

  assert_eq(attachment.document(), fresh_markdown_ir(source))

  let updated = "# Heading [ref]\n\nAfter\n\n[ref]: /two \"changed\"\n"
  match editor.commit(MarkdownEditRequest::ReplaceSource(updated)) {
    Ok(MarkdownCommitResult::Applied(_, None)) => ()
    _ => fail("expected source replacement to commit")
  }
  // snapshot observes both the projection and its SourceMap after attachment
  // collection has run on the shared parser runtime.
  let snapshot = editor.snapshot()
  assert_eq(snapshot.source(), updated)
  assert_eq(snapshot.blocks().to_array()[1].text(), "After")
  assert_eq(attachment.document(), fresh_markdown_ir(updated))
  attachment.dispose()
}

/// #1075 behavioral boundary matrix
/// Syntax: tight top-level unordered and ordered (`.`/`)`, non-1) list items,
/// fenced backtick/tilde code; terminators: LF/CRLF/CR/EOF; operations:
/// full/incremental projection and typed payload commits; modes: Raw/Block/
/// Preview; ownership: direct top-level supported nodes only, with nested,
/// loose, indented-code, and unsupported containers rejected atomically.
/// Every accepted snapshot carries stable identity plus exact source, payload,
/// marker, and fence spans; focus/selection success or rejection and fresh /
/// incremental parity are checked here or at the private disposable seam.

///|
test "1075 RED: mixed list and fenced-code snapshots expose typed ranges" {
  let source = "- one\r\n\r\n7) two\r\n~~~moonbit\r\nold\r\n~~~\r\n"
  let editor = try! MarkdownEditor(agent_id="1075-red", source~)
  let blocks = editor.snapshot().blocks().to_array()

  assert_eq(blocks.length(), 3)
  match blocks[0].kind() {
    MarkdownBlockKind::UnorderedListItem => ()
    _ => fail("expected an unordered list item snapshot")
  }
  match blocks[1].kind() {
    MarkdownBlockKind::OrderedListItem(start~, delimiter~) => {
      assert_eq(start, 7)
      assert_eq(delimiter, ")")
    }
    _ => fail("expected a non-1 ordered list item snapshot")
  }
  match blocks[2].kind() {
    MarkdownBlockKind::CodeBlock(info~) => assert_eq(info, "moonbit")
    _ => fail("expected a fenced-code snapshot")
  }
  assert_eq(blocks[0].text(), "one")
  assert_eq(blocks[1].text(), "two")
  assert_eq(blocks[2].text(), "old")
  assert_eq(blocks[0].marker_range(), Some((0, 2)))
  assert_eq(blocks[1].marker_range(), Some((9, 12)))
  assert_eq(blocks[2].fence_open_range(), Some((17, 27)))
  assert_eq(blocks[2].text_range(), (29, 32))
  assert_eq(blocks[2].fence_close_range(), Some((34, 39)))

  let unordered = blocks[0].node_id()
  let ordered = blocks[1].node_id()
  let code = blocks[2].node_id()
  match
    editor.commit(
      MarkdownEditRequest::CommitEdit(node_id=unordered, new_text="ONE"),
    ) {
    Ok(MarkdownCommitResult::Applied(snapshot, _)) =>
      assert_eq(
        snapshot.source(),
        "- ONE\r\n\r\n7) two\r\n~~~moonbit\r\nold\r\n~~~\r\n",
      )
    _ => fail("expected unordered payload commit")
  }
  match
    editor.commit(
      MarkdownEditRequest::CommitEdit(node_id=ordered, new_text="TWO"),
    ) {
    Ok(MarkdownCommitResult::Applied(snapshot, _)) =>
      assert_eq(
        snapshot.source(),
        "- ONE\r\n\r\n7) TWO\r\n~~~moonbit\r\nold\r\n~~~\r\n",
      )
    _ => fail("expected ordered payload commit")
  }
  match
    editor.commit(MarkdownEditRequest::CommitEdit(node_id=code, new_text="new")) {
    Ok(MarkdownCommitResult::Applied(snapshot, _)) =>
      assert_eq(
        snapshot.source(),
        "- ONE\r\n\r\n7) TWO\r\n~~~moonbit\r\nnew\r\n~~~\r\n",
      )
    _ => fail("expected fenced-code payload commit")
  }
}

///|
test "mixed list and fenced-code projection keeps identity and fresh parity" {
  let source = "- one\r\n\r\n7) two\r\n~~~moonbit\r\nold\r\n~~~\r\n"
  let editor = try! MarkdownEditor(agent_id="1075-identity", source~)
  let before = editor.snapshot().blocks().to_array()
  let unordered = before[0].node_id()
  let ordered = before[1].node_id()
  let code = before[2].node_id()

  match
    editor.commit(
      MarkdownEditRequest::CommitEdit(node_id=unordered, new_text="ONE"),
    ) {
    Ok(MarkdownCommitResult::Applied(snapshot, _)) => {
      let after = snapshot.blocks().to_array()
      assert_eq(after.length(), 3)
      assert_eq(after[1].node_id(), ordered)
      assert_eq(after[2].node_id(), code)
    }
    _ => fail("expected list payload edit")
  }

  match
    editor.commit(MarkdownEditRequest::CommitEdit(node_id=code, new_text="new")) {
    Ok(MarkdownCommitResult::Applied(snapshot, _)) => {
      let fresh = try! MarkdownEditor(
        agent_id="1075-identity-fresh",
        source=snapshot.source(),
      )
      let actual = snapshot.blocks().to_array()
      let expected = fresh.snapshot().blocks().to_array()
      assert_eq(actual.length(), expected.length())
      for i in 0..<actual.length() {
        assert_eq(actual[i].kind(), expected[i].kind())
        assert_eq(actual[i].text(), expected[i].text())
        assert_eq(actual[i].source_range(), expected[i].source_range())
        assert_eq(actual[i].text_range(), expected[i].text_range())
        assert_eq(actual[i].marker_range(), expected[i].marker_range())
        assert_eq(actual[i].fence_open_range(), expected[i].fence_open_range())
        assert_eq(
          actual[i].fence_close_range(),
          expected[i].fence_close_range(),
        )
      }
    }
    _ => fail("expected fenced-code payload edit")
  }
}

///|
test "headless facade commits exact source and exposes snapshot" {
  let editor = try! MarkdownEditor(agent_id="red", source="before")
  inspect(editor.snapshot().source(), content="before")

  let result = editor.commit(
    MarkdownEditRequest::ReplaceSource("# LF\n## CRLF\r\n### CR\rend"),
  )

  let after = editor.snapshot()
  inspect(after.source(), content="# LF\n## CRLF\r\n### CR\rend")
  match result {
    Ok(MarkdownCommitResult::Applied(snapshot, None)) =>
      assert_true(snapshot == after)
    _ => fail("expected Applied")
  }
}

///|
test "source-changing receipt carries history and a UTF-16 transform" {
  let editor = try! MarkdownEditor(
    agent_id="receipt-source-change",
    source="A🤣B\r\n",
  )
  let before_version = editor.version()

  let receipt = match
    (try! editor.commit_with_receipt(
      MarkdownEditRequest::ReplaceSource("AéB\r\n"),
    )) {
    Ok(receipt) => receipt
    Err(_) => fail("expected receipt commit to succeed")
  }

  match receipt.result() {
    MarkdownCommitResult::Applied(snapshot, None) =>
      assert_eq(snapshot.source(), "AéB\r\n")
    _ => fail("expected legacy Applied result")
  }
  assert_false(receipt.after_version() == before_version)
  match receipt.history() {
    Some(history) => {
      let expected = try! editor.history_since(version=before_version)
      assert_true(history == expected)
    }
    None => fail("expected incremental history")
  }
  let transforms = receipt.transforms().to_array()
  assert_eq(transforms.length(), 1)
  assert_eq(transforms[0].start(), 1)
  assert_eq(transforms[0].delete_len(), 2)
  assert_eq(transforms[0].inserted(), "é")
}

///|
test "headless facade reports unchanged source atomically" {
  let editor = try! MarkdownEditor(agent_id="unchanged", source="before")
  let before = editor.snapshot()
  let result = editor.commit(MarkdownEditRequest::ReplaceSource("before"))

  match result {
    Ok(MarkdownCommitResult::Unchanged(snapshot)) =>
      assert_true(snapshot == before)
    _ => fail("expected Unchanged")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "true no-op receipt has unchanged version and no history" {
  let editor = try! MarkdownEditor(agent_id="receipt-no-op", source="before")
  let before_version = editor.version()

  let receipt = match
    (try! editor.commit_with_receipt(
      MarkdownEditRequest::ReplaceSource("before"),
    )) {
    Ok(receipt) => receipt
    Err(_) => fail("expected no-op receipt commit to succeed")
  }

  match receipt.result() {
    MarkdownCommitResult::Unchanged(snapshot) =>
      assert_eq(snapshot.source(), "before")
    _ => fail("expected legacy Unchanged result")
  }
  assert_true(receipt.before_version() == before_version)
  assert_true(receipt.after_version() == before_version)
  assert_true(receipt.history() is None)
  assert_true(receipt.transforms().is_empty())
}

///|
test "headless facade preserves caller-owned ZWSP in exact source" {
  let source = "Hello\u200Bworld\n"
  let editor = try! MarkdownEditor(agent_id="zwsp", source~)

  assert_eq(editor.snapshot().source(), source)
  let result = editor.commit(MarkdownEditRequest::ReplaceSource(source))
  match result {
    Ok(MarkdownCommitResult::Unchanged(snapshot)) =>
      assert_eq(snapshot.source(), source)
    _ => fail("expected Unchanged")
  }
}

///|
test "headless facade applies UTF-16 exact text edits" {
  let editor = try! MarkdownEditor(agent_id="utf16", source="A🤣B\r\n")

  let result = editor.commit(
    MarkdownEditRequest::ReplaceText(start=1, delete_len=2, inserted="é"),
  )

  let after = editor.snapshot()
  inspect(after.source(), content="AéB\r\n")
  match result {
    Ok(MarkdownCommitResult::Applied(snapshot, None)) =>
      assert_true(snapshot == after)
    _ => fail("expected Applied")
  }
}

///|
test "headless facade reconciles LF control edits against CR payloads" {
  let editor = try! MarkdownEditor(
    agent_id="text-control-cr",
    source="Foo\rbar",
  )
  let block = editor.snapshot().blocks().to_array()[0]

  let result = editor.commit(
    MarkdownEditRequest::CommitTextControlEdit(
      node_id=block.node_id(),
      new_text="Foo\nChanged",
    ),
  )

  assert_true(result is Ok(_))
  assert_eq(editor.snapshot().source(), "Foo\rChanged")
}

///|
test "headless facade reconciles LF control edits against CRLF payloads" {
  let editor = try! MarkdownEditor(
    agent_id="text-control-crlf",
    source="Foo\r\nbar",
  )
  let block = editor.snapshot().blocks().to_array()[0]

  let result = editor.commit(
    MarkdownEditRequest::CommitTextControlEdit(
      node_id=block.node_id(),
      new_text="Foo\nChanged",
    ),
  )

  assert_true(result is Ok(_))
  assert_eq(editor.snapshot().source(), "Foo\r\nChanged")
}

///|
test "headless facade preserves multiple CR separators on a tail edit" {
  let editor = try! MarkdownEditor(
    agent_id="text-control-cr-multiple",
    source="One\rTwo\rThree",
  )
  let block = editor.snapshot().blocks().to_array()[0]

  let result = editor.commit(
    MarkdownEditRequest::CommitTextControlEdit(
      node_id=block.node_id(),
      new_text="One\nTwo\nChanged",
    ),
  )

  assert_true(result is Ok(_))
  assert_eq(editor.snapshot().source(), "One\rTwo\rChanged")
}

///|
test "headless facade preserves multiple CRLF separators on a tail edit" {
  let editor = try! MarkdownEditor(
    agent_id="text-control-crlf-multiple",
    source="One\r\nTwo\r\nThree",
  )
  let block = editor.snapshot().blocks().to_array()[0]

  let result = editor.commit(
    MarkdownEditRequest::CommitTextControlEdit(
      node_id=block.node_id(),
      new_text="One\nTwo\nChanged",
    ),
  )

  assert_true(result is Ok(_))
  assert_eq(editor.snapshot().source(), "One\r\nTwo\r\nChanged")
}

///|
test "headless facade keeps exact CommitEdit line endings" {
  let editor = try! MarkdownEditor(
    agent_id="exact-commit-edit",
    source="Foo\rbar",
  )
  let block = editor.snapshot().blocks().to_array()[0]

  let result = editor.commit(
    MarkdownEditRequest::CommitEdit(
      node_id=block.node_id(),
      new_text="Foo\nChanged",
    ),
  )

  assert_true(result is Ok(_))
  assert_eq(editor.snapshot().source(), "Foo\nChanged")
}

///|
test "invalid UTF-16 boundary leaves source unchanged" {
  let editor = try! MarkdownEditor(
    agent_id="invalid-range",
    source="A🤣B\r\n",
  )
  let before = editor.snapshot()

  let result = editor.commit(
    MarkdownEditRequest::ReplaceText(start=2, delete_len=1, inserted="x"),
  )

  match result {
    Err(MarkdownEditorError::EditFailed(_)) => ()
    _ => fail("expected EditFailed")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "out of range text edit is categorized and preserves source" {
  let editor = try! MarkdownEditor(agent_id="invalid-range", source="A\n")
  let before = editor.snapshot()

  let result = editor.commit(
    MarkdownEditRequest::ReplaceText(start=3, delete_len=1, inserted="x"),
  )

  match result {
    Err(MarkdownEditorError::InvalidTextRange(_)) => ()
    _ => fail("expected InvalidTextRange")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "snapshot owns immutable projection identities" {
  let editor = try! MarkdownEditor(
    agent_id="projection",
    source="# Heading\n\nBody\n",
  )
  let projection = editor.snapshot().projection()

  assert_true(projection.root_id() is Some(_))
  assert_true(projection.node_ids().length() >= 1)
}

///|
test "snapshot exposes editable heading payload and source spans" {
  let editor = try! MarkdownEditor(
    agent_id="block-snapshot",
    source="# Title\n",
  )
  let blocks = editor.snapshot().blocks().to_array()
  assert_eq(blocks.length(), 1)
  match blocks[0].kind() {
    MarkdownBlockKind::Heading(level~) => assert_eq(level, 1)
    _ => fail("expected heading block")
  }
  assert_eq(blocks[0].text(), "Title")
  assert_eq(blocks[0].source_range(), (0, 8))
  assert_eq(blocks[0].text_range(), (2, 7))
  assert_eq(blocks[0].marker_range(), Some((0, 2)))
}

///|
test "snapshot exposes multiline setext payload without underline" {
  let editor = try! MarkdownEditor(
    agent_id="setext-snapshot",
    source="Foo\nbar\n---\n",
  )
  let blocks = editor.snapshot().blocks().to_array()
  assert_eq(blocks.length(), 1)
  assert_eq(blocks[0].text(), "Foo\nbar")
  assert_eq(blocks[0].marker_range(), Some((8, 11)))
}

///|
test "snapshot omits unsupported container payloads" {
  let editor = try! MarkdownEditor(
    agent_id="unsupported-container",
    source="> quoted\n\n# Direct\n",
  )
  let blocks = editor.snapshot().blocks().to_array()
  assert_eq(blocks.length(), 1)
  assert_eq(blocks[0].text(), "Direct")
  match blocks[0].kind() {
    MarkdownBlockKind::Heading(level~) => assert_eq(level, 1)
    _ => fail("expected direct heading block")
  }
}

///|
test "snapshot rejects nested and loose lists and indented code" {
  let nested = try! MarkdownEditor(
    agent_id="nested-list-unsupported",
    source="- parent\n  - child\n\n# Direct\n",
  )
  let nested_blocks = nested.snapshot().blocks().to_array()
  assert_eq(nested_blocks.length(), 1)
  assert_eq(nested_blocks[0].text(), "Direct")

  let loose = try! MarkdownEditor(
    agent_id="loose-list-unsupported",
    source="- one\n\n- two\n\n# Direct\n",
  )
  let loose_blocks = loose.snapshot().blocks().to_array()
  assert_eq(loose_blocks.length(), 1)
  assert_eq(loose_blocks[0].text(), "Direct")

  let indented = try! MarkdownEditor(
    agent_id="indented-code-unsupported",
    source="    code\n\n# Direct\n",
  )
  let indented_blocks = indented.snapshot().blocks().to_array()
  assert_eq(indented_blocks.length(), 1)
  assert_eq(indented_blocks[0].text(), "Direct")
}

///|
test "empty fenced code exposes a zero-length payload and preserves delimiters" {
  let source = "~~~\r\n~~~\r\n"
  let editor = try! MarkdownEditor(agent_id="empty-fenced-code", source~)
  let blocks = editor.snapshot().blocks().to_array()
  assert_eq(blocks.length(), 1)
  match blocks[0].kind() {
    MarkdownBlockKind::CodeBlock(info~) => assert_eq(info, "")
    _ => fail("expected an empty fenced-code snapshot")
  }
  assert_eq(blocks[0].text(), "")
  assert_eq(blocks[0].text_range(), (5, 5))
  assert_eq(blocks[0].fence_open_range(), Some((0, 3)))
  assert_eq(blocks[0].fence_close_range(), Some((5, 10)))

  match
    editor.commit(
      MarkdownEditRequest::CommitEdit(
        node_id=blocks[0].node_id(),
        new_text="filled",
      ),
    ) {
    Ok(MarkdownCommitResult::Applied(snapshot, _)) =>
      assert_eq(snapshot.source(), "~~~\r\nfilled\r\n~~~\r\n")
    _ => fail("expected empty fenced-code payload commit")
  }
}

///|
test "empty fenced code preserves terminal payload newlines and boundaries" {
  let cases : Array[(String, String, String)] = [
    ("~~~\n~~~\n", "x\n", "~~~\nx\n\n~~~\n"),
    ("~~~\r\n~~~\r\n", "x\r\n", "~~~\r\nx\r\n\r\n~~~\r\n"),
    ("~~~\r~~~\r", "x\r", "~~~\rx\r\r~~~\r"),
  ]
  for case in cases {
    let editor = try! MarkdownEditor(
      agent_id="empty-fenced-terminal-newline",
      source=case.0,
    )
    let block = editor.snapshot().blocks().to_array()[0]
    match
      editor.commit(
        MarkdownEditRequest::CommitEdit(
          node_id=block.node_id(),
          new_text=case.1,
        ),
      ) {
      Ok(MarkdownCommitResult::Applied(snapshot, _)) => {
        assert_eq(snapshot.source(), case.2)
        assert_eq(snapshot.blocks().to_array()[0].text(), case.1)
      }
      _ => fail("expected terminal-newline fenced payload commit")
    }
  }
}

///|
test "headless facade rejects CommitEdit for nested list items atomically" {
  let source = "- parent\n  - child\n\n# Direct\n"
  let editor = try! MarkdownEditor(agent_id="nested-list-commit-edit", source~)
  let nested_id = editor.snapshot().projection().node_ids().get(2).unwrap()
  let before = editor.snapshot()

  match
    editor.commit(
      MarkdownEditRequest::CommitEdit(node_id=nested_id, new_text="changed"),
    ) {
    Err(MarkdownEditorError::EditFailed(_)) => ()
    _ => fail("expected nested list CommitEdit to fail")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "headless facade rejects CommitEdit for loose list items atomically" {
  let source = "- one\n\n- two\n\n# Direct\n"
  let editor = try! MarkdownEditor(agent_id="loose-list-commit-edit", source~)
  let loose_id = editor.snapshot().projection().node_ids().get(2).unwrap()
  let before = editor.snapshot()

  match
    editor.commit(
      MarkdownEditRequest::CommitEdit(node_id=loose_id, new_text="changed"),
    ) {
    Err(MarkdownEditorError::EditFailed(_)) => ()
    _ => fail("expected loose list CommitEdit to fail")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "typed block receipt carries the lowered transform and selection" {
  let editor = try! MarkdownEditor(
    agent_id="receipt-typed-block",
    source="# Title\n",
  )
  let block = editor.snapshot().blocks().to_array()[0]
  let before_version = editor.version()

  let receipt = match
    (try! editor.commit_with_receipt(
      MarkdownEditRequest::CommitEdit(
        node_id=block.node_id(),
        new_text="Renamed",
      ),
    )) {
    Ok(receipt) => receipt
    Err(_) => fail("expected typed block receipt")
  }

  match receipt.result() {
    MarkdownCommitResult::Applied(snapshot, Some(selection)) => {
      assert_eq(snapshot.source(), "# Renamed\n")
      assert_eq(selection.node_id(), snapshot.blocks().to_array()[0].node_id())
      assert_eq(selection.offset(), 7)
    }
    _ => fail("expected typed block commit to apply with a selection")
  }
  let typed_history = try! editor.history_since(version=before_version)
  match receipt.history() {
    Some(history) => assert_true(history == typed_history)
    None => fail("expected typed block history increment")
  }
  let transforms = receipt.transforms().to_array()
  assert_eq(transforms.length(), 1)
  assert_eq(transforms[0].start(), 2)
  assert_eq(transforms[0].delete_len(), 5)
  assert_eq(transforms[0].inserted(), "Renamed")
}

///|
test "split and merge receipts retain exact sequential lowering transforms" {
  let editor = try! MarkdownEditor(
    agent_id="receipt-block-structure",
    source="Hello\n\nWorld\n",
  )
  let first = editor.snapshot().blocks().to_array()[0].node_id()
  let before_split = editor.version()

  let split = match
    (try! editor.commit_with_receipt(
      MarkdownEditRequest::SplitBlock(node_id=first, offset=2),
    )) {
    Ok(receipt) => receipt
    Err(_) => fail("expected split receipt")
  }
  match split.result() {
    MarkdownCommitResult::Applied(snapshot, Some(selection)) => {
      assert_eq(snapshot.source(), "He\n\nllo\n\nWorld\n")
      assert_eq(selection.node_id(), snapshot.blocks().to_array()[1].node_id())
      assert_eq(selection.offset(), 0)
    }
    _ => fail("expected split to apply with a selection")
  }
  let split_history = try! editor.history_since(version=before_split)
  assert_true(split.history().unwrap() == split_history)
  let split_transforms = split.transforms().to_array()
  assert_eq(split_transforms.length(), 1)
  assert_eq(split_transforms[0].start(), 2)
  assert_eq(split_transforms[0].delete_len(), 4)
  assert_eq(split_transforms[0].inserted(), "\n\nllo\n")

  let before_merge = editor.version()
  let second = editor.snapshot().blocks().to_array()[1].node_id()
  let merge = match
    (try! editor.commit_with_receipt(
      MarkdownEditRequest::MergeWithPrevious(node_id=second),
    )) {
    Ok(receipt) => receipt
    Err(_) => fail("expected merge receipt")
  }
  match merge.result() {
    MarkdownCommitResult::Applied(snapshot, Some(selection)) => {
      assert_eq(snapshot.source(), "Hello\n\nWorld\n")
      assert_eq(selection.node_id(), snapshot.blocks().to_array()[0].node_id())
      assert_eq(selection.offset(), 2)
    }
    _ => fail("expected merge to apply with a selection")
  }
  let merge_history = try! editor.history_since(version=before_merge)
  assert_true(merge.history().unwrap() == merge_history)
  let merge_transforms = merge.transforms().to_array()
  assert_eq(merge_transforms.length(), 1)
  assert_eq(merge_transforms[0].start(), 2)
  assert_eq(merge_transforms[0].delete_len(), 6)
  assert_eq(merge_transforms[0].inserted(), "llo\n")
}

///|
test "receipt transforms use sequential reverse-document order" {
  let transforms = sequential_text_transforms([
    @core.SpanEdit::{ start: 1, delete_len: 1, inserted: "X" },
    @core.SpanEdit::{ start: 4, delete_len: 0, inserted: "!" },
  ]).to_array()

  assert_eq(transforms.length(), 2)
  assert_eq(transforms[0].start(), 4)
  assert_eq(transforms[0].delete_len(), 0)
  assert_eq(transforms[0].inserted(), "!")
  assert_eq(transforms[1].start(), 1)
  assert_eq(transforms[1].delete_len(), 1)
  assert_eq(transforms[1].inserted(), "X")

  // Every coordinate is read against the source left by the prior transform.
  let source = "abcde"
  let after_first = source[:4].to_owned() + "!" + source[4:].to_owned()
  let after_second = after_first[:1].to_owned() +
    "X" +
    after_first[2:].to_owned()
  assert_eq(after_second, "aXcd!e")
}

///|
test "headless facade lowers supported split and merge requests" {
  let editor = try! MarkdownEditor(
    agent_id="block-structure",
    source="Hello\n\nWorld\n",
  )
  let first = editor.snapshot().blocks().to_array()[0].node_id()

  match
    editor.commit(MarkdownEditRequest::SplitBlock(node_id=first, offset=2)) {
    Ok(MarkdownCommitResult::Applied(snapshot, Some(selection))) => {
      assert_eq(snapshot.source(), "He\n\nllo\n\nWorld\n")
      let blocks = snapshot.blocks().to_array()
      assert_eq(selection.node_id(), blocks[1].node_id())
      assert_eq(selection.offset(), 0)
    }
    _ => fail("expected split to apply")
  }

  let second = editor.snapshot().blocks().to_array()[1].node_id()
  match editor.commit(MarkdownEditRequest::MergeWithPrevious(node_id=second)) {
    Ok(MarkdownCommitResult::Applied(snapshot, Some(selection))) => {
      assert_eq(snapshot.source(), "Hello\n\nWorld\n")
      assert_eq(selection.node_id(), snapshot.blocks().to_array()[0].node_id())
      assert_eq(selection.offset(), 2)
    }
    _ => fail("expected merge to apply")
  }
}

///|
test "headless facade splits at block start into an empty previous block" {
  let editor = try! MarkdownEditor(
    agent_id="block-start-split",
    source="Hello\n",
  )
  let first = editor.snapshot().blocks().to_array()[0]

  match
    editor.commit(
      MarkdownEditRequest::SplitBlock(node_id=first.node_id(), offset=0),
    ) {
    Ok(MarkdownCommitResult::Applied(snapshot, selection)) => {
      assert_eq(
        snapshot.source(),
        @md_sentinel.EMPTY_PARAGRAPH_SENTINEL + "\n\nHello\n",
      )
      let blocks = snapshot.blocks().to_array()
      assert_eq(blocks.length(), 2)
      assert_eq(blocks[0].text(), "")
      assert_eq(blocks[1].text(), "Hello")
      match selection {
        Some(selection) => {
          assert_eq(selection.node_id(), blocks[0].node_id())
          assert_eq(selection.offset(), 0)
        }
        None => fail("expected selection in the empty previous block")
      }
    }
    _ => fail("expected block-start split to apply")
  }
}

///|
test "headless facade keeps structural no-op selection empty" {
  let editor = try! MarkdownEditor(
    agent_id="block-structure-no-op",
    source="Hello\n\nWorld\n",
  )
  let first = editor.snapshot().blocks().to_array()[0].node_id()

  match editor.commit(MarkdownEditRequest::MergeWithPrevious(node_id=first)) {
    Ok(MarkdownCommitResult::Unchanged(snapshot)) =>
      assert_eq(snapshot.source(), "Hello\n\nWorld\n")
    _ => fail("expected merge on first block to remain unchanged")
  }
}

///|
test "text-control clear keeps an empty editable block" {
  let editor = try! MarkdownEditor(
    agent_id="cleared-block-placeholder",
    source="Hello\n",
  )
  let first = editor.snapshot().blocks().to_array()[0]

  match
    editor.commit(
      MarkdownEditRequest::CommitTextControlEdit(
        node_id=first.node_id(),
        new_text="",
      ),
    ) {
    Ok(MarkdownCommitResult::Applied(snapshot, _)) => {
      assert_eq(snapshot.source(), @md_sentinel.EMPTY_PARAGRAPH_SENTINEL + "\n")
      let blocks = snapshot.blocks().to_array()
      assert_eq(blocks.length(), 1)
      assert_eq(blocks[0].text(), "")
    }
    _ => fail("expected cleared block to remain editable")
  }
}

///|
test "text-control replacement preserves caller text after an end split" {
  let editor = try! MarkdownEditor(
    agent_id="end-split-placeholder",
    source="Hello\n",
  )
  let first = editor.snapshot().blocks().to_array()[0]
  match
    editor.commit(
      MarkdownEditRequest::SplitBlock(
        node_id=first.node_id(),
        offset=first.text().length(),
      ),
    ) {
    Ok(MarkdownCommitResult::Applied(snapshot, Some(_))) => {
      let empty = snapshot.blocks().to_array()[1]
      assert_eq(empty.text(), "")
      match
        editor.commit(
          MarkdownEditRequest::CommitTextControlEdit(
            node_id=empty.node_id(),
            new_text="X\u200B",
          ),
        ) {
        Ok(MarkdownCommitResult::Applied(after, _)) =>
          assert_eq(after.source(), "Hello\n\nX\u200B\n")
        _ => fail("expected placeholder replacement to apply")
      }
    }
    _ => fail("expected end split to apply")
  }
}

///|
test "block structure preserves unaffected identity and fresh parity" {
  let source = "Hello\n\nWorld\n"
  let editor = try! MarkdownEditor(agent_id="block-identity", source~)
  let before = editor.snapshot().blocks().to_array()
  let first = before[0].node_id()
  let world = before[1].node_id()

  match
    editor.commit(MarkdownEditRequest::SplitBlock(node_id=first, offset=2)) {
    Ok(MarkdownCommitResult::Applied(snapshot, Some(_))) => {
      assert_eq(snapshot.source(), "He\n\nllo\n\nWorld\n")
      let blocks = snapshot.blocks().to_array()
      assert_eq(blocks.length(), 3)
      assert_eq(blocks[2].node_id(), world)

      let fresh = try! MarkdownEditor(
        agent_id="block-identity-fresh-split",
        source="He\n\nllo\n\nWorld\n",
      )
      let fresh_blocks = fresh.snapshot().blocks().to_array()
      assert_eq(fresh_blocks.length(), blocks.length())
      assert_eq(blocks[0].text(), fresh_blocks[0].text())
      assert_eq(blocks[1].text(), fresh_blocks[1].text())
      assert_eq(blocks[2].text(), fresh_blocks[2].text())
      assert_eq(blocks[0].kind(), fresh_blocks[0].kind())
      assert_eq(blocks[1].kind(), fresh_blocks[1].kind())
      assert_eq(blocks[2].kind(), fresh_blocks[2].kind())
      assert_eq(blocks[0].source_range(), fresh_blocks[0].source_range())
      assert_eq(blocks[1].source_range(), fresh_blocks[1].source_range())
      assert_eq(blocks[2].source_range(), fresh_blocks[2].source_range())
      assert_eq(blocks[0].text_range(), fresh_blocks[0].text_range())
      assert_eq(blocks[1].text_range(), fresh_blocks[1].text_range())
      assert_eq(blocks[2].text_range(), fresh_blocks[2].text_range())
    }
    _ => fail("expected split to apply")
  }

  let second = editor.snapshot().blocks().to_array()[1].node_id()
  match editor.commit(MarkdownEditRequest::MergeWithPrevious(node_id=second)) {
    Ok(MarkdownCommitResult::Applied(snapshot, Some(_))) => {
      assert_eq(snapshot.source(), source)
      let blocks = snapshot.blocks().to_array()
      assert_eq(blocks.length(), 2)
      assert_eq(blocks[1].node_id(), world)

      let fresh = try! MarkdownEditor(
        agent_id="block-identity-fresh-merge",
        source~,
      )
      let fresh_blocks = fresh.snapshot().blocks().to_array()
      assert_eq(fresh_blocks.length(), blocks.length())
      assert_eq(blocks[0].text(), fresh_blocks[0].text())
      assert_eq(blocks[1].text(), fresh_blocks[1].text())
      assert_eq(blocks[0].kind(), fresh_blocks[0].kind())
      assert_eq(blocks[1].kind(), fresh_blocks[1].kind())
      assert_eq(blocks[0].source_range(), fresh_blocks[0].source_range())
      assert_eq(blocks[1].source_range(), fresh_blocks[1].source_range())
      assert_eq(blocks[0].text_range(), fresh_blocks[0].text_range())
      assert_eq(blocks[1].text_range(), fresh_blocks[1].text_range())
    }
    _ => fail("expected merge to apply")
  }
}

///|
test "headless facade rejects list item split atomically" {
  let source = "- item\n\n# Direct\n"
  let editor = try! MarkdownEditor(agent_id="list-split-rejected", source~)
  let list_item_id = editor.snapshot().projection().node_ids().get(2).unwrap()
  let before = editor.snapshot()

  match
    editor.commit(
      MarkdownEditRequest::SplitBlock(
        node_id={ value: list_item_id.value },
        offset=2,
      ),
    ) {
    Err(MarkdownEditorError::EditFailed(_)) => ()
    _ => fail("expected list item split to fail")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "headless facade rejects list item merge before lowering" {
  let source = "- first\n- second\n"
  let editor = try! MarkdownEditor(agent_id="list-merge-rejected", source~)
  let list_item_id = editor.snapshot().projection().node_ids().get(3).unwrap()
  let before = editor.snapshot()

  match
    editor.commit(MarkdownEditRequest::MergeWithPrevious(node_id=list_item_id)) {
    Err(MarkdownEditorError::EditFailed(detail~)) =>
      assert_true(detail.contains("not an editable top-level block"))
    _ => fail("expected list item merge to fail")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "headless facade splits and merges an ATX heading without marker leakage" {
  let editor = try! MarkdownEditor(
    agent_id="atx-structure",
    source="# Hello\n\nWorld\n",
  )
  let first = editor.snapshot().blocks().to_array()[0]

  match
    editor.commit(
      MarkdownEditRequest::SplitBlock(node_id=first.node_id(), offset=2),
    ) {
    Ok(MarkdownCommitResult::Applied(snapshot, Some(selection))) => {
      assert_eq(snapshot.source(), "# He\n\nllo\n\nWorld\n")
      let blocks = snapshot.blocks().to_array()
      assert_eq(blocks.length(), 3)
      assert_eq(selection.node_id(), blocks[1].node_id())
      assert_eq(selection.offset(), 0)
      match blocks[0].kind() {
        MarkdownBlockKind::Heading(level~) => assert_eq(level, 1)
        _ => fail("expected split heading to retain ATX kind")
      }
      assert_eq(blocks[0].text(), "He")
      assert_eq(blocks[1].text(), "llo")
    }
    _ => fail("expected ATX split to apply")
  }

  let second = editor.snapshot().blocks().to_array()[1]
  match
    editor.commit(
      MarkdownEditRequest::MergeWithPrevious(node_id=second.node_id()),
    ) {
    Ok(MarkdownCommitResult::Applied(snapshot, Some(selection))) => {
      assert_eq(snapshot.source(), "# Hello\n\nWorld\n")
      let blocks = snapshot.blocks().to_array()
      assert_eq(selection.node_id(), blocks[0].node_id())
      assert_eq(selection.offset(), 2)
      match blocks[0].kind() {
        MarkdownBlockKind::Heading(level~) => assert_eq(level, 1)
        _ => fail("expected merged heading to retain ATX kind")
      }
      assert_eq(blocks[0].text(), "Hello")
    }
    _ => fail("expected ATX merge to apply")
  }
}

///|
test "headless facade keeps structural selection offsets in UTF-16 units" {
  let editor = try! MarkdownEditor(
    agent_id="block-structure-utf16-selection",
    source="A\u{1f600}B\n\nC\n",
  )
  let first = editor.snapshot().blocks().to_array()[0].node_id()

  match
    editor.commit(MarkdownEditRequest::SplitBlock(node_id=first, offset=3)) {
    Ok(MarkdownCommitResult::Applied(snapshot, Some(selection))) => {
      assert_eq(snapshot.source(), "A\u{1f600}\n\nB\n\nC\n")
      assert_eq(selection.offset(), 0)
    }
    _ => fail("expected UTF-16 split to apply")
  }

  let second = editor.snapshot().blocks().to_array()[1].node_id()
  match editor.commit(MarkdownEditRequest::MergeWithPrevious(node_id=second)) {
    Ok(MarkdownCommitResult::Applied(_, Some(selection))) =>
      assert_eq(selection.offset(), 3)
    _ => fail("expected UTF-16 merge to apply")
  }
}

///|
test "headless facade rejects unsupported container edits atomically" {
  let source = "> quoted\n\n# Direct\n"
  let editor = try! MarkdownEditor(
    agent_id="unsupported-container-edit",
    source~,
  )
  let quote_id = editor.snapshot().projection().node_ids().get(1).unwrap()
  let before = editor.snapshot()

  match
    editor.commit(
      MarkdownEditRequest::CommitEdit(node_id=quote_id, new_text="changed"),
    ) {
    Err(MarkdownEditorError::EditFailed(detail~)) =>
      assert_true(detail.contains("no editable span"))
    _ => fail("expected unsupported container edit to fail")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "headless facade rejects fenced code heading changes atomically" {
  let source = "```moonbit\nvalue\n```\n"
  let editor = try! MarkdownEditor(agent_id="fenced-heading", source~)
  let code_id = editor.snapshot().projection().node_ids().get(1).unwrap()
  let before = editor.snapshot()

  match
    editor.commit(
      MarkdownEditRequest::ChangeHeadingLevel(node_id=code_id, level=2),
    ) {
    Err(MarkdownEditorError::EditFailed(detail~)) =>
      assert_eq(
        detail, "change heading level requires a paragraph or heading block",
      )
    _ => fail("expected fenced code heading-level change to fail")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "headless facade rejects fenced code list toggles atomically" {
  let source = "```moonbit\nvalue\n```\n"
  let editor = try! MarkdownEditor(agent_id="fenced-list-toggle", source~)
  let code_id = editor.snapshot().projection().node_ids().get(1).unwrap()
  let before = editor.snapshot()

  match editor.commit(MarkdownEditRequest::ToggleListItem(node_id=code_id)) {
    Err(MarkdownEditorError::EditFailed(detail~)) =>
      assert_eq(
        detail, "toggle list item requires a paragraph or list item block",
      )
    _ => fail("expected fenced code list toggle to fail")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "headless facade rejects thematic break edits atomically" {
  let source = "# Before\n\n---\n\n## After\n"
  let editor = try! MarkdownEditor(agent_id="thematic-break-edit", source~)
  let thematic_id = editor.snapshot().projection().node_ids().get(2).unwrap()
  let before = editor.snapshot()

  match
    editor.commit(
      MarkdownEditRequest::CommitEdit(node_id=thematic_id, new_text="changed"),
    ) {
    Err(MarkdownEditorError::EditFailed(detail~)) =>
      assert_true(detail.contains("no editable span"))
    _ => fail("expected thematic break edit to fail")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "headless facade rejects merge after thematic break atomically" {
  let source = "---\n\nBody\n"
  let editor = try! MarkdownEditor(
    agent_id="merge-after-thematic-break",
    source~,
  )
  let current_id = editor.snapshot().projection().node_ids().get(2).unwrap()
  let before = editor.snapshot()

  match
    editor.commit(MarkdownEditRequest::MergeWithPrevious(node_id=current_id)) {
    Err(MarkdownEditorError::EditFailed(detail~)) =>
      assert_true(detail.contains("previous block"))
    _ => fail("expected merge after thematic break to fail")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "headless facade rejects merge after block quote atomically" {
  let source = "> quoted\n\n# Heading\n"
  let editor = try! MarkdownEditor(agent_id="merge-after-block-quote", source~)
  let current_id = editor.snapshot().projection().node_ids().get(2).unwrap()
  let before = editor.snapshot()

  match
    editor.commit(MarkdownEditRequest::MergeWithPrevious(node_id=current_id)) {
    Err(MarkdownEditorError::EditFailed(detail~)) =>
      assert_true(detail.contains("previous block"))
    _ => fail("expected merge after block quote to fail")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "headless facade rejects merge after html block atomically" {
  let source = "<div>html</div>\n\nBody\n"
  let editor = try! MarkdownEditor(agent_id="merge-after-html-block", source~)
  let current_id = editor.snapshot().projection().node_ids().get(2).unwrap()
  let before = editor.snapshot()

  match
    editor.commit(MarkdownEditRequest::MergeWithPrevious(node_id=current_id)) {
    Err(MarkdownEditorError::EditFailed(detail~)) =>
      assert_true(detail.contains("previous block"))
    _ => fail("expected merge after html block to fail")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "unsupported typed edit preserves source and projection" {
  let editor = try! MarkdownEditor(agent_id="unsupported", source="# Heading\n")
  let stale_node_id = editor.snapshot().projection().node_ids().get(1).unwrap()
  let replacement = editor.commit(MarkdownEditRequest::ReplaceSource(""))
  assert_true(replacement is Ok(_))
  let before = editor.snapshot()

  let result = editor.commit(MarkdownEditRequest::Delete(node_id=stale_node_id))

  match result {
    Err(MarkdownEditorError::EditFailed(_)) => ()
    _ => fail("expected EditFailed")
  }
  assert_true(editor.snapshot() == before)
}

///|
test "supported typed delete lowers through the Markdown edit companion" {
  let editor = try! MarkdownEditor(agent_id="delete", source="# Heading\n")
  let ids = editor.snapshot().projection().node_ids()
  let node_id = ids.get(1).unwrap()

  let result = editor.commit(MarkdownEditRequest::Delete(node_id~))

  assert_true(result is Ok(_))
  inspect(editor.snapshot().source(), content="")
}

///|
test "typed delete selects the next surviving block" {
  let editor = try! MarkdownEditor(
    agent_id="delete-survivor-selection",
    source="First\n\nSecond\n",
  )
  let first = editor.snapshot().blocks().get(0).unwrap()

  match editor.commit(MarkdownEditRequest::Delete(node_id=first.node_id())) {
    Ok(MarkdownCommitResult::Applied(snapshot, Some(selection))) => {
      let survivor = snapshot.blocks().get(0).unwrap()
      assert_eq(selection.node_id(), survivor.node_id())
      assert_eq(selection.offset(), survivor.text().length())
    }
    _ => fail("expected a typed selection for the surviving block")
  }
}

///|
test "typed delete selects the adjacent survivor instead of a stale cursor" {
  let editor = try! MarkdownEditor(
    agent_id="delete-adjacent-survivor-selection",
    source="First\n\nSecond\n\nThird\n",
  )
  let first = editor.snapshot().blocks().get(0).unwrap()
  ignore(
    editor.commit(
      MarkdownEditRequest::CommitEdit(
        node_id=first.node_id(),
        new_text="Changed",
      ),
    ),
  )
  let third = editor.snapshot().blocks().get(2).unwrap()

  let receipt = match
    (try! editor.commit_with_receipt(
      MarkdownEditRequest::Delete(node_id=third.node_id()),
    )) {
    Ok(receipt) => receipt
    Err(_) => fail("expected the adjacent survivor receipt")
  }
  match receipt.result() {
    MarkdownCommitResult::Applied(snapshot, Some(selection)) => {
      let survivor = snapshot.blocks().get(1).unwrap()
      assert_eq(selection.node_id(), survivor.node_id())
      assert_eq(selection.offset(), survivor.text().length())
    }
    _ => fail("expected the adjacent survivor selection")
  }
  let transforms = receipt.transforms().to_array()
  assert_eq(transforms.length(), 1)
  assert_eq(transforms[0].start(), 17)
  assert_eq(transforms[0].delete_len(), 6)
  assert_eq(transforms[0].inserted(), "")
}

///|
test "empty replica identity is a categorized construction failure" {
  let result : Result[MarkdownEditor, MarkdownEditorError] = Ok(
    MarkdownEditor(agent_id="", source=""),
  ) catch {
    error => Err(error)
  }

  match result {
    Err(MarkdownEditorError::InvalidAgentId) => ()
    _ => fail("expected InvalidAgentId")
  }
}

///|
/// Repeats the probe's checkpoint round-trip through the façade.
///
/// workspace/probe pinned this at the editor layer because the façade exposed
/// neither version nor history transport. It now does, so the same claim is
/// asserted where the application actually stands.
test "facade history round-trips into a reopened document" {
  let original = try! MarkdownEditor(
    agent_id="owner-1",
    source="# Title\n\nbody text\n",
  )
  let edited = original.commit(
    MarkdownEditRequest::ReplaceText(start=8, delete_len=0, inserted="!"),
  )
  assert_true(edited is Ok(MarkdownCommitResult::Applied(_)))
  let want_source = original.snapshot().source()
  let want_version = original.version()
  let history = try! original.history_since()

  let reopened = try! MarkdownEditor::open(agent_id="owner-2", history~)

  assert_eq(reopened.snapshot().source(), want_source)
  assert_true(reopened.version() == want_version)
  // Same past. Source and version are asserted above as consequences, and
  // would not on their own distinguish a continuation from a document that
  // merely looks alike -- see the next test. Sharing a future is a separate
  // claim, asserted by the convergence test below.
  let reopened_history = try! reopened.history_since()
  assert_true(reopened_history == history)
}

///|
/// A reopened document still shares a future with the one it came from.
///
/// This is the half of the design's oracle that equality cannot reach. Equal
/// history shows the two agree about the past; only an exchange of subsequent
/// operations shows the reopened document is a replica rather than a copy that
/// happens to match.
test "reopened and original converge after divergent edits" {
  let a = try! MarkdownEditor(agent_id="peer-a", source="hello world")
  let seed = try! a.history_since()
  let b = try! MarkdownEditor::open(agent_id="peer-b", history=seed)

  assert_true(
    a.commit(
      MarkdownEditRequest::ReplaceText(start=0, delete_len=0, inserted="A"),
    )
    is Ok(_),
  )
  assert_true(
    b.commit(
      MarkdownEditRequest::ReplaceText(start=11, delete_len=0, inserted="B"),
    )
    is Ok(_),
  )
  assert_false(a.snapshot().source() == b.snapshot().source())

  let from_b = try! b.history_since()
  let from_a = try! a.history_since()
  // Each side is handed the other's whole history, most of which it already
  // holds. Operations already present are neither applied again nor withheld.
  assert_eq(try! a.admit(from_b), MarkdownAdmitReport::Complete)
  assert_eq(try! b.admit(from_a), MarkdownAdmitReport::Complete)

  assert_eq(a.snapshot().source(), b.snapshot().source())
  let history_a = try! a.history_since()
  let history_b = try! b.history_since()
  assert_true(history_a == history_b)
}

///|
/// Opening blames the writer it could not create, not the history.
///
/// The two failures are reported at the same moment and read alike from the
/// outside, so the categories are easy to collapse -- and this one did, until
/// the mapping was corrected. An admission failure means a history was taken
/// in and the taking failed; here nothing was ever attempted.
test "open categorizes a bad writer identity as such" {
  let document = try! MarkdownEditor(agent_id="identity-source", source="# T\n")
  let history = try! document.history_since()

  let refused : Result[MarkdownEditor, MarkdownArchiveError] = Ok(
    MarkdownEditor::open(agent_id="", history~),
  ) catch {
    error => Err(error)
  }

  match refused {
    Err(MarkdownArchiveError::InvalidAgentId) => ()
    Err(MarkdownArchiveError::AdmitFailed(detail~)) =>
      fail("blamed admission for a writer that was never created: \{detail}")
    _ => fail("expected InvalidAgentId")
  }
}

///|
/// Taking back a history the document already holds changes nothing.
///
/// The convergence test above traverses this path -- each side is sent the
/// other's whole history -- without ever pinning it, so a document that
/// re-applied operations it already had would have converged anyway and gone
/// unnoticed. Admission is idempotent, and that is asserted here rather than
/// relied on there.
test "re-admitting a held history advances nothing" {
  let document = try! MarkdownEditor(agent_id="idempotent", source="# Title\n")
  assert_true(
    document.commit(
      MarkdownEditRequest::ReplaceText(start=8, delete_len=0, inserted="body\n"),
    )
    is Ok(_),
  )
  let before_source = document.snapshot().source()
  let before_version = document.version()
  let held = try! document.history_since()

  assert_eq(try! document.admit(held), MarkdownAdmitReport::Complete)

  assert_eq(document.snapshot().source(), before_source)
  assert_true(document.version() == before_version)
  let after = try! document.history_since()
  assert_true(after == held)
}

///|
/// A history missing its prerequisites is a state, not a failure -- and an
/// archive claiming to be whole is contradicted by it.
///
/// The same increment produces both outcomes. Admission reports what it could
/// not place; opening refuses it. Nothing separates the two but the judgment
/// each makes about the same report.
test "withheld operations are reported by admit and refused by open" {
  let source = try! MarkdownEditor(agent_id="gap-source", source="x")
  let cut = source.version()
  assert_true(
    source.commit(
      MarkdownEditRequest::ReplaceText(start=1, delete_len=0, inserted="y"),
    )
    is Ok(_),
  )
  // Everything after the cut, whose parents the receiver never saw.
  let gapped = try! source.history_since(version=cut)

  let receiver = try! MarkdownEditor(agent_id="gap-receiver", source="")
  // Exact counts, not merely the distinction: the increment carries one
  // operation, whose parent is absent, so nothing lands and one is held.
  assert_eq(
    try! receiver.admit(gapped),
    MarkdownAdmitReport::Withheld(applied=0, withheld=1),
  )

  let refused : Result[MarkdownEditor, MarkdownArchiveError] = Ok(
    MarkdownEditor::open(agent_id="gap-open", history=gapped),
  ) catch {
    error => Err(error)
  }
  match refused {
    Err(MarkdownArchiveError::IncompleteArchive) => ()
    _ => fail("expected IncompleteArchive")
  }
}

///|
/// Equal source and equal version do not make one document a continuation.
///
/// Two façade editors sharing a writer identity reach the same source and the
/// same frontier while holding different histories. This is why restore is
/// checked by comparing history, and it fails first if that ever stops being
/// true.
test "equal source and version do not imply equal history" {
  let one = try! MarkdownEditor(agent_id="same-identity", source="")
  let two = try! MarkdownEditor(agent_id="same-identity", source="")
  for writer in [(one, "A"), (two, "B")] {
    let (editor, inserted) = writer
    assert_true(
      editor.commit(
        MarkdownEditRequest::ReplaceText(start=0, delete_len=0, inserted~),
      )
      is Ok(_),
    )
    assert_true(
      editor.commit(
        MarkdownEditRequest::ReplaceText(start=0, delete_len=1, inserted=""),
      )
      is Ok(_),
    )
  }

  assert_eq(one.snapshot().source(), two.snapshot().source())
  assert_true(one.version() == two.version())
  let history_one = try! one.history_since()
  let history_two = try! two.history_since()
  assert_false(history_one == history_two)
}

///|
/// A source-preserving commit still carries the history it advanced.
///
/// Replacing one character with itself emits a real CRDT operation even though
/// the detached source is equal. The receipt must follow the version frontier,
/// not the legacy result's source-based `Unchanged` classification.
test "text-preserving commit receipt carries advanced history" {
  let editor = try! MarkdownEditor(agent_id="advance", source="hello")
  let before_version = editor.version()

  let receipt = match
    (try! editor.commit_with_receipt(
      MarkdownEditRequest::ReplaceText(start=0, delete_len=1, inserted="h"),
    )) {
    Ok(receipt) => receipt
    Err(_) => fail("expected receipt commit to succeed")
  }

  match receipt.result() {
    MarkdownCommitResult::Unchanged(snapshot) =>
      assert_eq(snapshot.source(), "hello")
    _ => fail("expected legacy Unchanged result")
  }
  assert_true(receipt.origin() is MarkdownCommitOrigin::Local)
  assert_true(receipt.before_version() == before_version)
  assert_false(receipt.after_version() == before_version)
  assert_true(receipt.after_version() == editor.version())
  match receipt.history() {
    Some(history) => {
      let expected = try! editor.history_since(version=before_version)
      assert_true(history == expected)
    }
    None => fail("expected incremental history from the before-version")
  }
  let transforms = receipt.transforms().to_array()
  assert_eq(transforms.length(), 1)
  assert_eq(transforms[0].start(), 0)
  assert_eq(transforms[0].delete_len(), 1)
  assert_eq(transforms[0].inserted(), "h")
}

///|
test "reference definition insertion preserves facade block identities" {
  let prefix = "[ref]: /target\n\n"
  let source = "# Heading\n\nBody [link][ref].\n"
  let editor = try! MarkdownEditor(agent_id="reference-definition", source~)
  let before_ids = editor.snapshot().projection().node_ids()
  assert_eq(before_ids.length(), 3)

  let result = editor.commit(
    MarkdownEditRequest::ReplaceText(start=0, delete_len=0, inserted=prefix),
  )

  match result {
    Ok(MarkdownCommitResult::Applied(after, None)) => {
      assert_eq(after.source(), prefix + source)
      let after_ids = after.projection().node_ids()
      assert_eq(after_ids.length(), 3)
      assert_eq(after_ids.get(1), before_ids.get(1))
      assert_eq(after_ids.get(2), before_ids.get(2))
    }
    _ => fail("expected reference definition insertion to apply")
  }
}

///|
test "history codec round-trips through the Markdown façade" {
  let editor = try! MarkdownEditor(
    agent_id="history-codec-red",
    source="# Title\n\nbody\n",
  )
  ignore(
    editor.commit(
      MarkdownEditRequest::ReplaceText(start=2, delete_len=0, inserted="New "),
    ),
  )
  let history = try! editor.history_since()
  let encoded = history.to_json_string()
  let decoded = try! MarkdownDocumentHistory::from_json_string(encoded)
  assert_true(decoded == history)
}

///|
test "portable Markdown delegates façade sentinel export" {
  let editor = try! MarkdownEditor(
    agent_id="portable-markdown-facade",
    source="Hello\n",
  )
  let first = editor.snapshot().blocks().to_array()[0]
  assert_true(
    editor.commit(
      MarkdownEditRequest::SplitBlock(node_id=first.node_id(), offset=0),
    )
    is Ok(_),
  )
  assert_false(editor.portable_markdown().contains("\u200B"))
  assert_eq(editor.portable_markdown(), "\n\nHello\n")
}
