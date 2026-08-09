///| Portable commit transaction boundary matrix.

///|

///| - accepted one-span edit: apply once, refresh once, return portable before,

///|   portable after, and the exact projected transform

///| - accepted source no-op: return Unchanged without inventing a transform

///| - lowering rejection: return EditRejected and leave source unchanged

///| - failure before source mutation: return NotCommitted

///| - failure after source mutation: return Committed with portable evidence

///| - unexpected multi-span lowering: report a committed protocol issue; current

///|   Markdown lowerers do not emit this shape, so no fake production case

///| - parser, projection tree, source map, hidden ranges, sentinel metadata, and

///|   canonical coordinates remain package-private

///|
test "portable commit transaction projects InsertBlockAfter atomically" {
  let editor = try! new_editor("portable-commit-insert")
  editor.set_text("Hello\n")
  editor.refresh()
  guard editor.get_proj_node() is Some(root) && root.children is [paragraph] else {
    fail("expected one projected paragraph")
  }

  match
    commit_portable_edit(
      editor,
      @md_edits.MarkdownEditOp::InsertBlockAfter(node_id=paragraph.id()),
      0,
    ) {
    Ok(PortableCommitOutcome::Applied(commit)) => {
      assert_eq(commit.before(), "Hello\n")
      assert_eq(commit.after(), "Hello\n\n\n")
      let transform = commit.transform()
      assert_eq(transform.start, 6)
      assert_eq(transform.delete_len, 0)
      assert_eq(transform.inserted, "\n\n")
      assert_eq(apply_span_edit(commit.before(), transform), commit.after())
      assert_eq(editor.get_text(), "Hello\n\n\u{200B}\n")
    }
    _ => fail("expected one applied portable commit")
  }
}

///|
test "portable commit transaction preserves an accepted no-op" {
  let editor = try! new_editor("portable-commit-no-op")
  editor.set_text("First\n")
  editor.refresh()
  guard editor.get_proj_node() is Some(root) && root.children is [paragraph] else {
    fail("expected one projected paragraph")
  }
  let version_before = editor.get_version()

  match
    commit_portable_edit(
      editor,
      @md_edits.MarkdownEditOp::MergeWithPrevious(node_id=paragraph.id()),
      0,
    ) {
    Ok(PortableCommitOutcome::Unchanged(source~)) => {
      assert_eq(source, "First\n")
      assert_eq(editor.get_text(), "First\n")
      assert_eq(editor.get_version(), version_before)
    }
    _ => fail("expected an unchanged portable commit")
  }
}

///|
test "portable commit transaction keeps lowering rejection pre-commit" {
  let editor = try! new_editor("portable-commit-rejected")
  editor.set_text("# Present\n")
  editor.refresh()
  let source_before = editor.get_text()
  let version_before = editor.get_version()
  let missing = @core.NodeId::from_int(999999)

  match
    commit_portable_edit(
      editor,
      @md_edits.MarkdownEditOp::ChangeHeadingLevel(node_id=missing, level=2),
      0,
    ) {
    Err(
      PortableCommitError::EditRejected(
        error=@core.EditError::NodeNotFound(action~, node_id~)
      )
    ) => {
      assert_eq(action, "compute_markdown_edit")
      assert_eq(node_id, missing)
      assert_eq(editor.get_text(), source_before)
      assert_eq(editor.get_version(), version_before)
    }
    _ => fail("expected a typed pre-commit lowering rejection")
  }
}

///|
test "portable commit transaction removes the empty-previous merge sentinel" {
  let editor = try! new_editor("portable-commit-merge")
  editor.set_text("Hello\n")
  editor.refresh()
  guard editor.get_proj_node() is Some(initial) &&
    initial.children is [paragraph] else {
    fail("expected one projected paragraph")
  }
  match
    apply_edit(
      editor,
      @md_edits.MarkdownEditOp::SplitBlock(node_id=paragraph.id(), offset=0),
      0,
    ) {
    Ok([_]) => ()
    _ => fail("setup split should apply exactly once")
  }
  editor.refresh()
  guard editor.get_proj_node() is Some(split) && split.children is [_, current] else {
    fail("expected an empty previous block")
  }

  match
    commit_portable_edit(
      editor,
      @md_edits.MarkdownEditOp::MergeWithPrevious(node_id=current.id()),
      0,
    ) {
    Ok(PortableCommitOutcome::Applied(commit)) => {
      assert_eq(commit.before(), "\n\nHello\n")
      assert_eq(commit.after(), "Hello\n")
      assert_eq(
        apply_span_edit(commit.before(), commit.transform()),
        commit.after(),
      )
      assert_false(commit.after().contains("\u{200B}"))
      assert_eq(editor.get_text(), "Hello\n")
    }
    _ => fail("expected one applied sentinel-free merge")
  }
}

///|
test "portable commit transaction keeps source equality distinct from history" {
  let editor = try! new_editor("portable-commit-same-source")
  editor.set_text("Same\n")
  editor.refresh()
  guard editor.get_proj_node() is Some(root) && root.children is [paragraph] else {
    fail("expected one projected paragraph")
  }
  let version_before = editor.get_version()

  match
    commit_portable_edit(
      editor,
      @md_edits.MarkdownEditOp::CommitEdit(
        node_id=paragraph.id(),
        new_text="Same",
      ),
      0,
    ) {
    Ok(PortableCommitOutcome::Unchanged(source~)) => {
      assert_eq(source, "Same\n")
      assert_true(editor.get_version() != version_before)
    }
    _ => fail("expected source-unchanged commit classification")
  }
}

///|
test "portable commit transaction preserves user-authored ZWSP" {
  let editor = try! new_editor("portable-commit-user-zwsp")
  editor.set_text("A\u{200B}B\n")
  editor.refresh()
  guard editor.get_proj_node() is Some(root) && root.children is [paragraph] else {
    fail("expected one projected paragraph")
  }

  match
    commit_portable_edit(
      editor,
      @md_edits.MarkdownEditOp::CommitEdit(
        node_id=paragraph.id(),
        new_text="A\u{200B}C",
      ),
      0,
    ) {
    Ok(PortableCommitOutcome::Applied(commit)) => {
      assert_eq(commit.before(), "A\u{200B}B\n")
      assert_eq(commit.after(), "A\u{200B}C\n")
      assert_eq(
        apply_span_edit(commit.before(), commit.transform()),
        commit.after(),
      )
    }
    _ => fail("expected user-authored ZWSP to remain portable")
  }
}

///|
test "portable commit transaction preserves UTF-16 text terminators" {
  let cases = [
    ("😀A\n", "😀B\n"),
    ("😀A\r\n", "😀B\r\n"),
    ("😀A\r", "😀B\r"),
    ("😀A", "😀B"),
  ]
  cases.eachi((index, case) => {
    let (before, expected_after) = case
    let editor = try! new_editor(
      "portable-commit-terminator-" + index.to_string(),
    )
    editor.set_text(before)
    editor.refresh()
    guard editor.get_proj_node() is Some(root) && root.children is [paragraph] else {
      fail("expected one projected paragraph")
    }

    match
      commit_portable_edit(
        editor,
        @md_edits.MarkdownEditOp::CommitEdit(
          node_id=paragraph.id(),
          new_text="😀B",
        ),
        0,
      ) {
      Ok(PortableCommitOutcome::Applied(commit)) => {
        assert_eq(commit.before(), before)
        assert_eq(commit.after(), expected_after)
        assert_eq(commit.transform().start, 0)
        assert_eq(commit.transform().delete_len, 3)
        assert_eq(
          apply_span_edit(commit.before(), commit.transform()),
          commit.after(),
        )
      }
      _ => fail("expected one portable terminator-preserving commit")
    }
  })
}

///|
test "portable commit interruption uses causal commit evidence" {
  let issue = PortableCommitIssue::RuntimeFailure(detail="parser failed")
  match
    classify_interrupted_portable_commit("Before\n", committed=true, issue) {
    Ok(PortableCommitOutcome::Committed(evidence~, issue~)) => {
      assert_eq(evidence.before(), "Before\n")
      assert_eq(evidence.after(), None)
      assert_eq(
        issue,
        PortableCommitIssue::RuntimeFailure(detail="parser failed"),
      )
    }
    _ => fail("a changed causal version must be reported as committed")
  }
  match
    classify_interrupted_portable_commit("Before\n", committed=false, issue) {
    Err(PortableCommitError::NotCommitted(issue~)) =>
      assert_eq(
        issue,
        PortableCommitIssue::RuntimeFailure(detail="parser failed"),
      )
    _ => fail("a stable causal version must remain not committed")
  }
}

///|
test "portable commit transaction preserves move identity and ordering" {
  let editor = try! new_editor("portable-commit-move")
  editor.set_text("1. A\n2. B\n3. C\n")
  editor.refresh()
  guard editor.get_proj_node() is Some(before) &&
    before.children is [list] &&
    list.children is [first, _, third] else {
    fail("expected one three-item ordered list")
  }

  match
    commit_portable_edit(
      editor,
      @md_edits.MarkdownEditOp::MoveBlock(
        source=third.id(),
        target=first.id(),
        position=@core.DropPosition::Before,
      ),
      0,
    ) {
    Ok(PortableCommitOutcome::Applied(commit)) => {
      assert_eq(commit.before(), "1. A\n2. B\n3. C\n")
      assert_eq(commit.after(), "1. C\n2. A\n3. B\n")
      assert_eq(
        apply_span_edit(commit.before(), commit.transform()),
        commit.after(),
      )
      guard editor.get_proj_node() is Some(after) &&
        after.children is [moved_list] &&
        moved_list.children is [moved, ..] else {
        fail("expected moved list after transaction refresh")
      }
      assert_eq(moved.id(), third.id())
    }
    _ => fail("expected one applied portable move")
  }
}

///|
test "portable commit transaction splits at a UTF-16 grapheme boundary" {
  let editor = try! new_editor("portable-commit-split")
  editor.set_text("😀x\n")
  editor.refresh()
  guard editor.get_proj_node() is Some(root) && root.children is [paragraph] else {
    fail("expected one projected paragraph")
  }

  match
    commit_portable_edit(
      editor,
      @md_edits.MarkdownEditOp::SplitBlock(node_id=paragraph.id(), offset=1),
      0,
    ) {
    Ok(PortableCommitOutcome::Applied(commit)) => {
      assert_eq(commit.before(), "😀x\n")
      assert_eq(commit.after(), "😀\n\nx\n")
      assert_eq(
        apply_span_edit(commit.before(), commit.transform()),
        commit.after(),
      )
    }
    _ => fail("expected one applied portable split")
  }
}

///|
test "portable commit transaction projects block deletion" {
  let editor = try! new_editor("portable-commit-delete")
  editor.set_text("# Title\n\nParagraph\n")
  editor.refresh()
  guard editor.get_proj_node() is Some(root) && root.children is [_, paragraph] else {
    fail("expected a heading and paragraph")
  }

  match
    commit_portable_edit(
      editor,
      @md_edits.MarkdownEditOp::Delete(node_id=paragraph.id()),
      0,
    ) {
    Ok(PortableCommitOutcome::Applied(commit)) => {
      assert_eq(commit.before(), "# Title\n\nParagraph\n")
      assert_eq(commit.after(), "# Title\n\n")
      assert_eq(
        apply_span_edit(commit.before(), commit.transform()),
        commit.after(),
      )
    }
    _ => fail("expected one applied portable deletion")
  }
}
