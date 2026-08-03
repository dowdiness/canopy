///| The first public headless Markdown façade seam.

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
