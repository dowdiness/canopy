///| White-box compatibility test for SDEG Phase 0 Markdown edit path.

///|
struct HeadingEditPathObservation {
  id : @core.NodeId
  level : Int
  text : String
  text_span_text : String?
} derive(Eq, Debug)

///|
fn heading_edit_path_observation(
  node : @core.ProjNode[@markdown.Block],
  source : String,
  source_map : @core.SourceMap,
) -> HeadingEditPathObservation? {
  match node.kind {
    Heading(level, [Text(text)]) =>
      Some({
        id: node.id(),
        level,
        text,
        text_span_text: match source_map.get_token_span(node.id(), "text") {
          Some(span) => Some(source[span.start:span.end].to_owned())
          None => None
        },
      })
    _ => None
  }
}

///|
fn heading_edit_path_observations(
  editor : @editor.SyncEditor[@markdown.Block],
) -> Array[HeadingEditPathObservation] {
  let observations : Array[HeadingEditPathObservation] = []
  let root = editor.get_proj_node().unwrap()
  let source = editor.get_text()
  let source_map = editor.get_source_map()
  for child in root.children {
    match heading_edit_path_observation(child, source, source_map) {
      Some(obs) => observations.push(obs)
      None => ()
    }
  }
  observations
}

///|
fn first_heading_edit_path_observation(
  editor : @editor.SyncEditor[@markdown.Block],
) -> HeadingEditPathObservation {
  heading_edit_path_observations(editor)[0]
}

///|
test "sdeg phase0: heading rename goes through Markdown edit path" {
  let editor = try! new_markdown_editor("sdeg-edit-path")
  editor.set_text("# Alpha\n\nBody\n")
  editor.refresh()
  let before = first_heading_edit_path_observation(editor)

  let result = apply_markdown_edit(
    editor,
    @md_edits.MarkdownEditOp::CommitEdit(node_id=before.id, new_text="Alpha 2"),
    0,
  )
  editor.refresh()
  let after = first_heading_edit_path_observation(editor)

  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="# Alpha 2\n\nBody\n")
  inspect(before.text, content="Alpha")
  inspect(after.text, content="Alpha 2")
  inspect(after.level, content="1")
  inspect(before.id == after.id, content="true")
  inspect(before.text_span_text == Some("Alpha"), content="true")
  inspect(after.text_span_text == Some("Alpha 2"), content="true")
}

///|
test "sdeg phase0: markdown edit path swap is replacement, not reorder provenance" {
  let editor = try! new_markdown_editor("sdeg-edit-path-reorder")
  editor.set_text("# A\n# B\n")
  editor.refresh()
  let before = heading_edit_path_observations(editor)
  let a_before = before[0]
  let b_before = before[1]

  // Without using the explicit MoveBlock operation, the smallest existing
  // edit-path way to reach the swapped source is two text commits, which
  // records replacement-by-position rather than move provenance.
  let first_result = apply_markdown_edit(
    editor,
    @md_edits.MarkdownEditOp::CommitEdit(node_id=a_before.id, new_text="B"),
    0,
  )
  editor.refresh()
  let middle = heading_edit_path_observations(editor)
  let second_result = apply_markdown_edit(
    editor,
    @md_edits.MarkdownEditOp::CommitEdit(node_id=middle[1].id, new_text="A"),
    1,
  )
  editor.refresh()
  let after = heading_edit_path_observations(editor)

  inspect(first_result is Ok(_), content="true")
  inspect(second_result is Ok(_), content="true")
  inspect(editor.get_text(), content="# B\n# A\n")
  inspect(a_before.text, content="A")
  inspect(b_before.text, content="B")
  inspect(after[0].text, content="B")
  inspect(after[1].text, content="A")
  inspect(after[0].id == a_before.id, content="true")
  inspect(after[1].id == b_before.id, content="true")
  inspect(after[0].id == b_before.id, content="false")
  inspect(after[1].id == a_before.id, content="false")
}

///|
test "sdeg spike: explicit markdown block move preserves moved heading identity" {
  let editor = try! new_markdown_editor("sdeg-edit-path-explicit-move")
  editor.set_text("# A\n# B\n")
  editor.refresh()
  let before = heading_edit_path_observations(editor)
  let a_before = before[0]
  let b_before = before[1]

  let result = apply_markdown_edit(
    editor,
    @md_edits.MarkdownEditOp::MoveBlock(
      source=b_before.id,
      target=a_before.id,
      position=@core.DropPosition::Before,
    ),
    0,
  )
  editor.refresh()
  let after = heading_edit_path_observations(editor)

  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="# B\n# A\n")
  inspect(after[0].text, content="B")
  inspect(after[1].text, content="A")
  inspect(after[0].id == b_before.id, content="true")
  inspect(after[1].id == a_before.id, content="true")
}

///|
test "sdeg phase0: heading level change through edit path has fresh NodeId" {
  let editor = try! new_markdown_editor("sdeg-edit-path-level")
  editor.set_text("# Alpha\n\nBody\n")
  editor.refresh()
  let before = first_heading_edit_path_observation(editor)

  let result = apply_markdown_edit(
    editor,
    @md_edits.MarkdownEditOp::ChangeHeadingLevel(node_id=before.id, level=2),
    0,
  )
  editor.refresh()
  let after = first_heading_edit_path_observation(editor)

  inspect(result is Ok(_), content="true")
  inspect(editor.get_text(), content="## Alpha\n\nBody\n")
  inspect(before.text, content="Alpha")
  inspect(after.text, content="Alpha")
  inspect(after.level, content="2")
  inspect(before.id == after.id, content="false")
  inspect(before.text_span_text == Some("Alpha"), content="true")
  inspect(after.text_span_text == Some("Alpha"), content="true")
}
