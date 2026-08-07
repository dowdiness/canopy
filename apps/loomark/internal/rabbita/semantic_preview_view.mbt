///|
/// Collect image alternative text without depending on Loom's private helper.
/// This narrow renderer-local traversal keeps an image's semantic inline text
/// available to the typed HTML image constructor.
fn semantic_preview_plain_text(node : @md_markdown.MarkdownIR) -> String {
  match node.text_value() {
    Some(value) => return value
    None => ()
  }
  match node.view() {
    @md_markdown.Text(value~)
    | @md_markdown.InlineHtml(value~)
    | @md_markdown.Raw(value~) => value
    @md_markdown.Autolink(display~, ..) => display
    @md_markdown.InlineCode(value~) | @md_markdown.HtmlBlock(value~) => value
    @md_markdown.HardBreak(..) | @md_markdown.SoftBreak => "\n"
    @md_markdown.Unsupported(message~) | @md_markdown.Recovered(message~) =>
      message
    @md_markdown.ThematicBreak => ""
    @md_markdown.CodeBlock(value~, ..) => value
    @md_markdown.Document
    | @md_markdown.Heading(..)
    | @md_markdown.Paragraph
    | @md_markdown.BlockQuote
    | @md_markdown.UnorderedList(..)
    | @md_markdown.OrderedList(..)
    | @md_markdown.ListItem(..)
    | @md_markdown.OrderedListItem(..)
    | @md_markdown.Bold
    | @md_markdown.Italic
    | @md_markdown.Link(..)
    | @md_markdown.Image(..) =>
      node.children().map(semantic_preview_plain_text).join("")
  }
}

///|
fn semantic_preview_link_form(
  form : @md_markdown.MarkdownIRLinkReferenceForm,
) -> String {
  match form {
    @md_markdown.InlineLinkForm => "inline"
    @md_markdown.FullReferenceLinkForm => "full-reference"
    @md_markdown.CollapsedReferenceLinkForm => "collapsed-reference"
    @md_markdown.ShortcutReferenceLinkForm => "shortcut-reference"
  }
}

///|
fn semantic_preview_unordered_marker(
  marker : @md_markdown.UnorderedListMarker?,
) -> String {
  match marker {
    Some(@md_markdown.Dash) => "-"
    Some(@md_markdown.Star) => "*"
    Some(@md_markdown.Plus) => "+"
    None => ""
  }
}

///|
fn semantic_preview_ordered_marker(
  marker : @md_markdown.OrderedListMarker?,
) -> String {
  match marker {
    Some(marker) => marker.text()
    None => ""
  }
}

///|
/// Keep destinations deterministic and inert before passing them to typed
/// href/src attributes. Links allow http, https, and mailto; images exclude
/// mailto because it cannot identify a renderable image resource.
const SEMANTIC_PREVIEW_FORBIDDEN_URL_CHARS = "\u0000\u0001\u0002\u0003\u0004\u0005\u0006\u0007\u0008\u0009\u000A\u000B\u000C\u000D\u000E\u000F\u0010\u0011\u0012\u0013\u0014\u0015\u0016\u0017\u0018\u0019\u001A\u001B\u001C\u001D\u001E\u001F\u007F"

///|
fn semantic_preview_safe_destination(
  destination : String,
  image~ : Bool,
) -> String? {
  let trimmed = destination.trim().to_owned()
  if trimmed != destination ||
    destination.contains_any(chars=SEMANTIC_PREVIEW_FORBIDDEN_URL_CHARS) {
    return None
  }
  let lowercase = destination.to_lower()
  if lowercase.has_prefix("//") ||
    lowercase.has_prefix("/") ||
    lowercase.has_prefix("#") ||
    lowercase.has_prefix("?") {
    return Some(destination)
  }
  match lowercase.find(":") {
    None => Some(destination)
    Some(scheme_end) => {
      if (lowercase.find("/") is Some(separator) && separator < scheme_end) ||
        (lowercase.find("?") is Some(separator) && separator < scheme_end) ||
        (lowercase.find("#") is Some(separator) && separator < scheme_end) {
        return Some(destination)
      }
      let scheme = lowercase[:scheme_end].to_owned()
      match scheme {
        "http" | "https" => Some(destination)
        "mailto" if !image => Some(destination)
        _ => None
      }
    }
  }
}

///|
fn semantic_preview_diagnostics(
  node : @md_markdown.MarkdownIR,
) -> Array[@rabbita_runtime.Html] {
  node
  .diagnostics()
  .map(diagnostic => {
    @html.li(
      attrs=@html.Attrs::build().data_set("loomark-preview-diagnostic", ""),
      "Diagnostic: " + diagnostic.format(),
    )
  })
}

///|
fn semantic_preview_children(
  node : @md_markdown.MarkdownIR,
) -> Array[@rabbita_runtime.Html] {
  node.children().map(child => semantic_preview_node(child))
}

///|
/// Render direct list-item children with their parent's spread decision.
fn semantic_preview_list_children(
  node : @md_markdown.MarkdownIR,
  parent_list_spread : Bool,
) -> Array[@rabbita_runtime.Html] {
  node
  .children()
  .map(child => {
    match child.view() {
      @md_markdown.ListItem(..) | @md_markdown.OrderedListItem(..) =>
        semantic_preview_node(child, list_parent_spread=parent_list_spread)
      _ => semantic_preview_node(child)
    }
  })
}

///|
/// Unwrap only direct Paragraph children of a tight list item.
fn semantic_preview_list_item_children(
  node : @md_markdown.MarkdownIR,
  render_paragraphs : Bool,
) -> Array[@rabbita_runtime.Html] {
  node
  .children()
  .map(child => {
    match child.view() {
      @md_markdown.Paragraph =>
        semantic_preview_node(
          child,
          unwrap_list_item_paragraph=!render_paragraphs,
        )
      _ => semantic_preview_node(child)
    }
  })
}

///|
fn semantic_preview_heading(
  depth : Int,
  children : Array[@rabbita_runtime.Html],
) -> @rabbita_runtime.Html {
  match depth {
    1 => @rui.typography_h1(style=["text-align:start"], children)
    2 =>
      @rui.typography_h2(
        style=["border-bottom:none;padding-bottom:0"],
        children,
      )
    3 => @rui.typography_h3(children)
    4 => @rui.typography_h4(children)
    5 =>
      @html.h5(
        style=["margin:0;font-size:1rem;line-height:1.5rem;font-weight:600"],
        children,
      )
    _ =>
      @html.h6(
        style=[
          "margin:0;font-size:0.875rem;line-height:1.25rem;font-weight:600",
        ],
        children,
      )
  }
}

///|
/// Render all 24 current public MarkdownIR views without reparsing or
/// source-offset keys.
fn semantic_preview_node(
  node : @md_markdown.MarkdownIR,
  list_parent_spread? : Bool = false,
  unwrap_list_item_paragraph? : Bool = false,
) -> @rabbita_runtime.Html {
  let view = node.view()
  let children = match view {
    @md_markdown.UnorderedList(spread~, ..)
    | @md_markdown.OrderedList(spread~, ..) =>
      semantic_preview_list_children(node, spread)
    @md_markdown.ListItem(spread~, ..)
    | @md_markdown.OrderedListItem(spread~, ..) =>
      semantic_preview_list_item_children(node, spread || list_parent_spread)
    _ => semantic_preview_children(node)
  }
  match view {
    @md_markdown.Document => @html.fragment(children)
    @md_markdown.Heading(depth~) => semantic_preview_heading(depth, children)
    @md_markdown.Paragraph =>
      if unwrap_list_item_paragraph {
        @html.fragment(children)
      } else {
        @rui.typography_p(children)
      }
    @md_markdown.BlockQuote => @rui.typography_blockquote(children)
    @md_markdown.UnorderedList(spread~, marker~) =>
      @html.ul(
        attrs=@html.Attrs::build()
          .data_set("loomark-list-spread", spread.to_string())
          .data_set(
            "loomark-list-marker",
            semantic_preview_unordered_marker(marker),
          ),
        children,
      )
    @md_markdown.OrderedList(spread~, marker~) => {
      let attrs = @html.Attrs::build()
        .data_set("loomark-list-spread", spread.to_string())
        .data_set(
          "loomark-list-marker",
          semantic_preview_ordered_marker(marker),
        )
      match marker {
        Some(marker) => @html.ol(start=marker.start(), attrs~, children)
        None => @html.ol(attrs~, children)
      }
    }
    @md_markdown.ListItem(spread~, marker~) =>
      @html.li(
        attrs=@html.Attrs::build()
          .data_set(
            "loomark-list-item-spread",
            (spread || list_parent_spread).to_string(),
          )
          .data_set(
            "loomark-list-marker",
            semantic_preview_unordered_marker(marker),
          ),
        children,
      )
    @md_markdown.OrderedListItem(spread~, marker~) =>
      @html.li(
        attrs=@html.Attrs::build()
          .data_set(
            "loomark-list-item-spread",
            (spread || list_parent_spread).to_string(),
          )
          .data_set(
            "loomark-list-marker",
            semantic_preview_ordered_marker(marker),
          ),
        children,
      )
    @md_markdown.CodeBlock(info~, value~) =>
      @html.pre(
        style=[
          "margin:0;overflow:auto;border-radius:var(--rui-radius,0.625rem);background:var(--rui-muted,oklch(0.97 0 0));padding:1rem",
        ],
        @html.code(
          style=[
            "font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,\"Liberation Mono\",\"Courier New\",monospace;font-size:0.875rem;line-height:1.5rem",
          ],
          attrs=@html.Attrs::build().data_set("loomark-code-info", info),
          value,
        ),
      )
    @md_markdown.HtmlBlock(value~) =>
      @html.pre(
        attrs=@html.Attrs::build().data_set("loomark-preview-html", "block"),
        value,
      )
    @md_markdown.ThematicBreak => @html.hr()
    @md_markdown.Text(value~) => @html.text(value)
    @md_markdown.Bold => @html.strong(children)
    @md_markdown.Italic => @html.em(children)
    @md_markdown.InlineCode(value~) => @html.code(value)
    @md_markdown.Link(destination~, title~, surface=link_form) =>
      match semantic_preview_safe_destination(destination, image=false) {
        Some(destination) =>
          @html.a(
            href=destination,
            title?,
            attrs=@html.Attrs::build().data_set(
              "loomark-link-reference-form",
              semantic_preview_link_form(link_form.form),
            ),
            children,
          )
        None =>
          @html.span(
            attrs=@html.Attrs::build().data_set(
              "loomark-preview-url-rejected", "link",
            ),
            children,
          )
      }
    @md_markdown.Image(destination~, title~, surface=image_form) => {
      let alt = semantic_preview_plain_text(node)
      match semantic_preview_safe_destination(destination, image=true) {
        Some(destination) =>
          @html.img(
            src=destination,
            alt~,
            title?,
            attrs=@html.Attrs::build().data_set(
              "loomark-image-reference-form",
              semantic_preview_link_form(image_form.form),
            ),
          )
        None =>
          @html.span(
            attrs=@html.Attrs::build().data_set(
              "loomark-preview-url-rejected", "image",
            ),
            "Image URL rejected: " + alt,
          )
      }
    }
    @md_markdown.Autolink(kind~, display~, destination~, ..) =>
      match semantic_preview_safe_destination(destination, image=false) {
        Some(destination) =>
          @html.a(
            href=destination,
            attrs=@html.Attrs::build().data_set(
              "loomark-autolink-kind",
              match kind {
                @md_markdown.UriAutolink => "uri"
                @md_markdown.EmailAutolink => "email"
              },
            ),
            display,
          )
        None =>
          @html.span(
            attrs=@html.Attrs::build().data_set(
              "loomark-preview-url-rejected", "autolink",
            ),
            display,
          )
      }
    @md_markdown.InlineHtml(value~) =>
      @html.span(
        attrs=@html.Attrs::build().data_set("loomark-preview-html", "inline"),
        value,
      )
    @md_markdown.SoftBreak => @html.text("\n")
    @md_markdown.HardBreak(surface=break_form) =>
      @html.br(
        attrs=@html.Attrs::build().data_set(
          "loomark-hard-break-form",
          match break_form {
            @md_markdown.TrailingSpaces(_) => "trailing-spaces"
            @md_markdown.Backslash => "backslash"
          },
        ),
      )
    @md_markdown.Unsupported(message~) =>
      @html.div(
        attrs=@html.Attrs::build().data_set(
          "loomark-preview-fallback", "unsupported",
        ),
        "Unsupported Markdown: " + message,
      )
    @md_markdown.Raw(value~) =>
      @html.div(
        attrs=@html.Attrs::build().data_set("loomark-preview-fallback", "raw"),
        [
          @html.strong("Raw Markdown:"),
          @html.pre(value),
          @html.ul(semantic_preview_diagnostics(node)),
        ],
      )
    @md_markdown.Recovered(message~) =>
      @html.div(
        attrs=@html.Attrs::build().data_set(
          "loomark-preview-fallback", "recovered",
        ),
        [
          @html.strong("Recovered Markdown: " + message),
          @html.ul(semantic_preview_diagnostics(node)),
        ],
      )
  }
}

///|
fn semantic_preview_view(
  source : String,
  semantic_document : @md_markdown.MarkdownIR,
) -> @rabbita_runtime.Html {
  @html.div(
    id="loomark-preview",
    attrs=@html.Attrs::build()
      .data_set("loomark-source", source)
      .role("region")
      .tabindex(0)
      .aria_label("Markdown preview"),
    style=[
      "box-sizing:border-box;width:var(--lm-page-width);margin-inline:auto;display:grid;gap:1rem;grid-auto-rows:max-content;border-left:var(--lm-page-side-border-width) solid var(--rui-border);border-right:var(--lm-page-side-border-width) solid var(--rui-border);border-top:0;border-bottom:0;border-radius:0;background:transparent;padding:1rem var(--lm-page-x-padding);overflow-y:auto",
    ],
    semantic_preview_node(semantic_document),
  )
}
