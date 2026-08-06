///|
/// A post-structural-edit selection resolved against an immutable block view.
priv struct BlockSelection {
  key : String
  index : Int
  start : Int
  end : Int
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
fn block_allows_heading(kind : @markdown.MarkdownBlockKind) -> Bool {
  kind is @markdown.Paragraph || kind is @markdown.Heading(_)
}

///|
fn block_allows_list(kind : @markdown.MarkdownBlockKind) -> Bool {
  kind is @markdown.Paragraph ||
  kind is @markdown.UnorderedListItem ||
  kind is @markdown.OrderedListItem(..)
}

///|
/// Decode structural keys without reading the DOM or reconstructing Markdown.
fn block_structural_key_event(
  kind : @markdown.MarkdownBlockKind,
  node_id : @markdown.MarkdownNodeId,
  key : String,
  ctrl : Bool,
  shift : Bool,
  alt : Bool,
  meta : Bool,
  composing : Bool,
  repeated : Bool,
  selection : @dom_boundary.TextSelection,
  text_length : Int,
  has_previous : Bool,
  has_next : Bool,
  block_key : String,
  block_index : Int,
) -> DriverEvent? {
  guard !ctrl && !shift && !alt && !meta && !composing && !repeated else {
    return None
  }
  if key == "Enter" {
    if block_allows_heading(kind) {
      if selection.start() == selection.end() {
        return Some(BlockSplit(node_id~, offset=selection.start()))
      }
      return Some(
        BlockSelectionRejected(
          "block split requires a collapsed selection",
          Some({
            key: block_key,
            index: block_index,
            start: selection.start(),
            end: selection.end(),
          }),
        ),
      )
    }
    if block_allows_list(kind) {
      return Some(
        BlockSelectionRejected(
          "list structural editing is unavailable",
          Some({
            key: block_key,
            index: block_index,
            start: selection.start(),
            end: selection.end(),
          }),
        ),
      )
    }
  }
  guard selection.start() == selection.end() else { return None }
  match key {
    "Backspace" if block_allows_heading(kind) &&
      has_previous &&
      text_length == 0 &&
      selection.start() == 0 =>
      Some(
        BlockMerge(node_id~, selection={
          key: block_key,
          index: block_index,
          start: selection.start(),
          end: selection.end(),
        }),
      )
    "Backspace" if has_previous && selection.start() == 0 =>
      Some(BlockNavigate(key=block_key, direction=-1))
    "ArrowLeft" | "ArrowUp" if has_previous && selection.start() == 0 =>
      Some(BlockNavigate(key=block_key, direction=-1))
    "ArrowRight" | "ArrowDown" if has_next && selection.start() == text_length =>
      Some(BlockNavigate(key=block_key, direction=1))
    _ => None
  }
}

///|
fn block_key_uses_selection(key : String) -> Bool {
  match key {
    "Enter"
    | "Backspace"
    | "ArrowLeft"
    | "ArrowUp"
    | "ArrowRight"
    | "ArrowDown" => true
    _ => false
  }
}

///|
/// Decode a keyboard value without reading or mutating the DOM.
fn block_shortcut_event(
  key : String,
  ctrl : Bool,
  shift : Bool,
  alt : Bool,
  meta : Bool,
  composing : Bool,
  repeated : Bool,
) -> DriverEvent? {
  guard ctrl && !alt && !meta && !composing && !repeated else { return None }
  if shift {
    if key == "l" || key == "L" {
      Some(BlockToggleList(None))
    } else {
      None
    }
  } else {
    match key {
      "0" => Some(BlockHeading(0, None))
      "1" => Some(BlockHeading(1, None))
      "2" => Some(BlockHeading(2, None))
      "3" => Some(BlockHeading(3, None))
      "4" => Some(BlockHeading(4, None))
      "5" => Some(BlockHeading(5, None))
      "6" => Some(BlockHeading(6, None))
      _ => None
    }
  }
}

///|
fn block_selection_label(selection : BlockSelection) -> String {
  "block|" + selection.key + "|" + selection.start.to_string()
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
        return Some({ key: block.key(), index, start: offset, end: offset })
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
      if selection.start >= 0 &&
        selection.start <= selection.end &&
        selection.end <= end - start {
        return Some(selection.index)
      }
    }
  }
  None
}

///|
/// Resolve adjacent keyboard navigation against one immutable block snapshot.
fn block_navigation_selection(
  document : @markdown.MarkdownDocumentSnapshot,
  key : String,
  direction : Int,
) -> BlockSelection? {
  let blocks = document.blocks().to_array()
  let current = blocks.search_by(block => block.key() == key)
  guard current is Some(current) else { return None }
  let target_index = current + direction
  guard blocks.get(target_index) is Some(target) else { return None }
  let offset = if direction < 0 { target.text().length() } else { 0 }
  Some({ key: target.key(), index: target_index, start: offset, end: offset })
}

///|
fn block_input_label(kind : @markdown.MarkdownBlockKind, index : Int) -> String {
  let position = (index + 1).to_string()
  match kind {
    @markdown.Paragraph => "Paragraph block " + position
    @markdown.Heading(level~) =>
      "Heading " + level.to_string() + " block " + position
    @markdown.UnorderedListItem => "Unordered list item " + position
    @markdown.OrderedListItem(..) => "Ordered list item " + position
    @markdown.CodeBlock(info~) =>
      if info == "" {
        "Code block " + position
      } else {
        info + " code block " + position
      }
  }
}

///|
fn block_marker(kind : @markdown.MarkdownBlockKind) -> @html.Html {
  match kind {
    @markdown.UnorderedListItem =>
      @html.span(
        attrs=@html.Attrs::build()
          .aria_hidden("true")
          .data_set("loomark-block-marker", "unordered"),
        style=[
          "width:1.5rem;flex:0 0 1.5rem;padding-top:0.375rem;color:var(--rui-primary);font-weight:650;text-align:center;line-height:1.5rem",
        ],
        "•",
      )
    @markdown.OrderedListItem(start~, delimiter~) =>
      @html.span(
        attrs=@html.Attrs::build()
          .aria_hidden("true")
          .data_set("loomark-block-marker", "ordered"),
        style=[
          "width:1.5rem;flex:0 0 1.5rem;padding-top:0.375rem;color:var(--rui-primary);font-variant-numeric:tabular-nums;font-weight:650;text-align:right;line-height:1.5rem",
        ],
        start.to_string() + delimiter,
      )
    _ => @html.nothing
  }
}

///|
fn block_row_style(
  kind : @markdown.MarkdownBlockKind,
  active : Bool,
) -> Array[String] {
  let appearance = match kind {
    @markdown.CodeBlock(_) if active =>
      "border-color:color-mix(in oklch,var(--rui-primary) 32%,var(--rui-border));background:var(--rui-muted)"
    @markdown.CodeBlock(_) =>
      "border-color:var(--rui-border);background:var(--rui-muted)"
    _ if active =>
      "border-color:color-mix(in oklch,var(--rui-primary) 24%,transparent);background:color-mix(in oklch,var(--rui-primary) 5%,transparent)"
    _ => "border-color:transparent;background:transparent"
  }
  [
    "display:flex;min-width:0;align-items:flex-start;gap:0.25rem;border:1px solid transparent;border-radius:calc(var(--rui-radius) - 0.125rem);padding:0.125rem 0.375rem;transition:background 120ms ease,border-color 120ms ease",
    appearance,
  ]
}

///|
fn block_input_style(kind : @markdown.MarkdownBlockKind) -> Array[String] {
  let typography = match kind {
    @markdown.Heading(level~) =>
      match level {
        1 =>
          "font-size:2rem;font-weight:700;line-height:1.3;letter-spacing:-0.025em"
        2 =>
          "font-size:1.5rem;font-weight:650;line-height:1.35;letter-spacing:-0.018em"
        3 =>
          "font-size:1.25rem;font-weight:650;line-height:1.4;letter-spacing:-0.012em"
        4 => "font-size:1.125rem;font-weight:650;line-height:1.45"
        _ => "font-size:1rem;font-weight:650;line-height:1.5"
      }
    @markdown.CodeBlock(_) =>
      "font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,\"Liberation Mono\",\"Courier New\",monospace;font-size:0.875rem;line-height:1.6;tab-size:2;white-space:pre;overflow-x:auto"
    _ => "font-size:1rem;font-weight:400;line-height:1.65"
  }
  [
    "min-height:2.25rem;field-sizing:content;resize:none;overflow:hidden;--rui-control-base-border:transparent;--rui-control-base-shadow:none;--rui-control-base-bg:transparent;border-radius:0;background:transparent;padding:0.25rem 0.5rem",
    typography,
  ]
}

///|
fn block_input(
  block : @markdown.MarkdownBlockSnapshot,
  index : Int,
  count : Int,
  active : Bool,
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Html {
  let input_id = block_input_id(index)
  let attrs = @html.Attrs::build()
    .data_set("loomark-block-id", block.key())
    .data_set("loomark-block-kind", block_kind_name(block.kind()))
    .aria_label(block_input_label(block.kind(), index))
    .on_keydown(event => {
      let shortcut = block_shortcut_event(
        event.key(),
        event.ctrl_key(),
        event.shift_key(),
        event.alt_key(),
        event.meta_key(),
        event.is_composing(),
        event.repeat(),
      )
      match shortcut {
        Some(shortcut) => {
          let selection = @dom_boundary.read_text_selection_id(input_id) catch {
            error => return emit(EffectFailed(error.message()))
          }
          let selection = Some({
            key: block.key(),
            index,
            start: selection.start(),
            end: selection.end(),
          })
          let shortcut = match shortcut {
            BlockHeading(level, _) => BlockHeading(level, selection)
            BlockToggleList(_) => BlockToggleList(selection)
            shortcut => shortcut
          }
          event.prevent_default()
          emit(shortcut)
        }
        None if block_key_uses_selection(event.key()) => {
          let selection = @dom_boundary.read_text_selection_id(input_id) catch {
            error => return emit(EffectFailed(error.message()))
          }
          match
            block_structural_key_event(
              block.kind(),
              block.node_id(),
              event.key(),
              event.ctrl_key(),
              event.shift_key(),
              event.alt_key(),
              event.meta_key(),
              event.is_composing(),
              event.repeat(),
              selection,
              block.text().length(),
              index > 0,
              index + 1 < count,
              block.key(),
              index,
            ) {
            Some(structural) => {
              event.prevent_default()
              emit(structural)
            }
            None => @rabbita_runtime.none
          }
        }
        None => @rabbita_runtime.none
      }
    })
  let attrs = if active {
    attrs
  } else {
    attrs.on_focus(_ => emit(BlockFocused(block.key())))
  }
  let input = @rui.textarea(
    id=input_id,
    value=block.text(),
    rows=1,
    slot="block-editor-input",
    style=block_input_style(block.kind()),
    attrs~,
    on_input=@cmd.Emit(text => block_input_command(block, input_id, text, emit)),
  )
  @html.div(
    attrs=@html.Attrs::build()
      .data_set("loomark-block-row", block.key())
      .data_set("loomark-block-active", active.to_string()),
    style=block_row_style(block.kind(), active),
    [block_marker(block.kind()), input],
  )
}

///|
fn block_editor_view(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Html {
  let controls : Map[String, @rabbita_runtime.Html] = Map([])
  let blocks = model.document.blocks().to_array()
  for index, block in blocks {
    controls[block.key()] = block_input(
      block,
      index,
      blocks.length(),
      model.active_block_key == Some(block.key()),
      emit,
    )
  }
  @html.div(
    id="loomark-block",
    attrs=@html.Attrs::build().data_set(
      "loomark-source",
      model.document.source(),
    ),
    style=[
      "width:100%;min-width:0;display:flex;flex-direction:column;gap:0.25rem;padding:clamp(0.75rem,2vw,1rem)",
    ],
    controls,
  )
}
