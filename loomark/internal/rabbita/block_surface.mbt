///|
/// A post-structural-edit selection resolved against an immutable block view.
priv struct BlockSelection {
  key : String
  index : Int
  offset : Int
}

///|
fn block_input_id(index : Int) -> String {
  if index == 0 {
    "loomark-block-input"
  } else {
    "loomark-block-input-" + index.to_string()
  }
}

///|
fn block_kind_name(kind : @markdown.MarkdownBlockKind) -> String {
  match kind {
    @markdown.Paragraph => "paragraph"
    @markdown.Heading(_) => "heading"
    @markdown.UnorderedListItem => "unordered-list-item"
    @markdown.OrderedListItem(..) => "ordered-list-item"
    @markdown.CodeBlock(_) => "code"
  }
}

///|
fn block_selection_label(selection : BlockSelection) -> String {
  "block|" + selection.key + "|" + selection.offset.to_string()
}

///|
/// Resolve the editor's typed node-relative selection against the new view.
fn block_selection_from_commit(
  document : @markdown.MarkdownDocumentSnapshot,
  selection : @markdown.MarkdownBlockSelection,
  offset? : Int = selection.offset(),
) -> BlockSelection? {
  for index, block in document.blocks().to_array() {
    if block.node_id() == selection.node_id() {
      let (start, end) = block.text_range()
      if offset >= 0 && offset <= end - start {
        return Some({ key: block.key(), index, offset })
      }
    }
  }
  None
}

///|
fn block_selection_target(
  document : @markdown.MarkdownDocumentSnapshot,
  selection : BlockSelection,
) -> Int? {
  let blocks = document.blocks().to_array()
  if selection.index >= 0 && selection.index < blocks.length() {
    let block = blocks[selection.index]
    if block.key() == selection.key {
      let (start, end) = block.text_range()
      if selection.offset >= 0 && selection.offset <= end - start {
        return Some(selection.index)
      }
    }
  }
  None
}

///|
fn block_input(
  block : @markdown.MarkdownBlockSnapshot,
  index : Int,
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Html {
  let input_id = block_input_id(index)
  let attrs = @html.Attrs::build()
    .data_set("loomark-block-id", block.key())
    .data_set("loomark-block-kind", block_kind_name(block.kind()))
  let input = @html.textarea(
    id=input_id,
    value=block.text(),
    rows=2,
    attrs~,
    on_input=@cmd.Emit(text => block_input_command(block, input_id, text, emit)),
    "",
  )
  let structure_controls = match block.kind() {
    @markdown.Paragraph | @markdown.Heading(_) => {
      let split = @html.button(
        attrs=@html.Attrs::build().data_set("loomark-block-split", block.key()),
        on_click=block_split_command(block, input_id, emit),
        "Split",
      )
      let merge = @html.button(
        attrs=@html.Attrs::build().data_set("loomark-block-merge", block.key()),
        on_click=emit(BlockMerge(node_id=block.node_id())),
        "Merge",
      )
      [split, merge]
    }
    _ => []
  }
  @html.div([input, ..structure_controls])
}

///|
fn block_surface(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Html {
  let controls : Map[String, @rabbita_runtime.Html] = Map([])
  for index, block in model.document.blocks().to_array() {
    controls[block.key()] = block_input(block, index, emit)
  }
  @html.div(
    id="loomark-block",
    attrs=@html.Attrs::build().data_set(
      "loomark-source",
      model.document.source(),
    ),
    controls,
  )
}
