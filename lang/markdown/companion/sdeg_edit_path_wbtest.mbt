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
fn first_heading_edit_path_observation(
  editor : @editor.SyncEditor[@markdown.Block],
) -> HeadingEditPathObservation {
  heading_edit_path_observation(
    editor.get_proj_node().unwrap().children[0],
    editor.get_text(),
    editor.get_source_map(),
  ).unwrap()
}

///|
test "sdeg phase0: heading rename goes through Markdown edit path" {
  let editor = new_markdown_editor("sdeg-edit-path")
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
test "sdeg phase0: heading level change through edit path has fresh NodeId" {
  let editor = new_markdown_editor("sdeg-edit-path-level")
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
