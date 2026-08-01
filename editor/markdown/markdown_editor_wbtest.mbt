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
    Ok(MarkdownCommitResult::Applied(snapshot)) =>
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
    Ok(MarkdownCommitResult::Applied(snapshot)) =>
      assert_true(snapshot == after)
    _ => fail("expected Applied")
  }
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
    Ok(MarkdownCommitResult::Applied(after)) => {
      assert_eq(after.source(), prefix + source)
      let after_ids = after.projection().node_ids()
      assert_eq(after_ids.length(), 3)
      assert_eq(after_ids.get(1), before_ids.get(1))
      assert_eq(after_ids.get(2), before_ids.get(2))
    }
    _ => fail("expected reference definition insertion to apply")
  }
}
