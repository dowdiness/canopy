///|
fn preview_block_attrs(block : @markdown.MarkdownBlockSnapshot) -> @html.Attrs {
  @html.Attrs::build()
  .data_set("loomark-block-id", block.key())
  .data_set("loomark-block-kind", block_kind_name(block.kind()))
}

///|
fn preview_heading(
  level : Int,
  block : @markdown.MarkdownBlockSnapshot,
) -> @rabbita_runtime.Html {
  let attrs = preview_block_attrs(block)
  let text = block.text()
  match level {
    1 => @rui.typography_h1(style=["text-align:start"], attrs~, text)
    2 => @rui.typography_h2(attrs~, text)
    3 => @rui.typography_h3(attrs~, text)
    4 => @rui.typography_h4(attrs~, text)
    5 =>
      @html.h5(
        style=["margin:0;font-size:1rem;line-height:1.5rem;font-weight:600"],
        attrs~,
        text,
      )
    _ =>
      @html.h6(
        style=[
          "margin:0;font-size:0.875rem;line-height:1.25rem;font-weight:600",
        ],
        attrs~,
        text,
      )
  }
}

///|
fn preview_raw_list_item(
  source : String,
  kind : String,
  block : @markdown.MarkdownBlockSnapshot,
) -> @rabbita_runtime.Html {
  let (start, end) = block.source_range()
  @html.pre(
    style=[
      "margin:0;overflow:auto;border-radius:var(--rui-radius,0.625rem);background:var(--rui-muted,oklch(0.97 0 0));padding:0.75rem 1rem",
    ],
    attrs=preview_block_attrs(block).data_set(
      "loomark-preview-raw-list-item", kind,
    ),
    source[start:end].to_owned(),
  )
}

///|
fn preview_block(
  source : String,
  block : @markdown.MarkdownBlockSnapshot,
) -> @rabbita_runtime.Html {
  let attrs = preview_block_attrs(block)
  match block.kind() {
    @markdown.Paragraph => @rui.typography_p(attrs~, block.text())
    @markdown.Heading(level~) => preview_heading(level, block)
    @markdown.UnorderedListItem =>
      preview_raw_list_item(source, "unordered", block)
    @markdown.OrderedListItem(..) =>
      preview_raw_list_item(source, "ordered", block)
    @markdown.CodeBlock(info~) => {
      let code_attrs = @html.Attrs::build().data_set("loomark-code-info", info)
      @html.pre(
        style=[
          "margin:0;overflow:auto;border-radius:var(--rui-radius,0.625rem);background:var(--rui-muted,oklch(0.97 0 0));padding:1rem",
        ],
        attrs~,
        @html.code(
          style=[
            "font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,\"Liberation Mono\",\"Courier New\",monospace;font-size:0.875rem;line-height:1.5rem",
          ],
          attrs=code_attrs,
          block.text(),
        ),
      )
    }
  }
}

///|
fn preview_surface(
  document : @markdown.MarkdownDocumentSnapshot,
) -> @rabbita_runtime.Html {
  let source = document.source()
  let blocks : Map[String, @rabbita_runtime.Html] = Map([])
  blocks["preview-scope-notice"] = @rui.typography_muted(
    attrs=@html.Attrs::build().data_set("loomark-preview-notice", ""),
    "Prototype preview shows supported top-level blocks. Use Raw for the complete source.",
  )
  for block in document.blocks().to_array() {
    blocks[block.key()] = preview_block(source, block)
  }
  @html.div(
    id="loomark-preview",
    attrs=@html.Attrs::build()
      .data_set("loomark-source", source)
      .tabindex(0)
      .aria_label("Markdown preview"),
    style=["display:grid;gap:1rem"],
    blocks,
  )
}
