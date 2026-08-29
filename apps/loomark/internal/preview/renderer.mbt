///|
priv enum RenderPosition {
  Flow
  Phrasing
}

///|
fn plain_text(node : @markdown.MarkdownIR) -> String {
  match node.text_value() {
    Some(value) => return value
    None => ()
  }
  match node.view() {
    @markdown.Text(value~)
    | @markdown.InlineHtml(value~)
    | @markdown.Raw(value~) => value
    @markdown.Autolink(display~, ..) => display
    @markdown.InlineCode(value~) | @markdown.HtmlBlock(value~) => value
    @markdown.HardBreak(..) | @markdown.SoftBreak => "\n"
    @markdown.Unsupported(message~) => message
    @markdown.Recovered(value~) => value
    @markdown.ThematicBreak => ""
    @markdown.CodeBlock(value~, ..) => value
    @markdown.Document
    | @markdown.Heading(..)
    | @markdown.Paragraph
    | @markdown.BlockQuote
    | @markdown.UnorderedList(..)
    | @markdown.OrderedList(..)
    | @markdown.ListItem(..)
    | @markdown.OrderedListItem(..)
    | @markdown.Bold
    | @markdown.Italic
    | @markdown.Link(..)
    | @markdown.Image(..) => node.children().map(plain_text).join("")
  }
}

///|
fn link_form(form : @markdown.MarkdownIRLinkReferenceForm) -> String {
  match form {
    @markdown.InlineLinkForm => "inline"
    @markdown.FullReferenceLinkForm => "full-reference"
    @markdown.CollapsedReferenceLinkForm => "collapsed-reference"
    @markdown.ShortcutReferenceLinkForm => "shortcut-reference"
  }
}

///|
fn unordered_marker(marker : @markdown.UnorderedListMarker?) -> String {
  match marker {
    Some(@markdown.Dash) => "-"
    Some(@markdown.Star) => "*"
    Some(@markdown.Plus) => "+"
    None => ""
  }
}

///|
fn ordered_marker(marker : @markdown.OrderedListMarker?) -> String {
  match marker {
    Some(marker) => marker.text()
    None => ""
  }
}

///|
const FORBIDDEN_URL_CHARS = "\u0000\u0001\u0002\u0003\u0004\u0005\u0006\u0007\u0008\u0009\u000A\u000B\u000C\u000D\u000E\u000F\u0010\u0011\u0012\u0013\u0014\u0015\u0016\u0017\u0018\u0019\u001A\u001B\u001C\u001D\u001E\u001F\u007F"

///|
fn safe_destination(destination : String, image~ : Bool) -> String? {
  let trimmed = destination.trim().to_owned()
  if trimmed != destination ||
    destination.contains_any(chars=FORBIDDEN_URL_CHARS) {
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
      match lowercase[:scheme_end].to_owned() {
        "http" | "https" => Some(destination)
        "mailto" if !image => Some(destination)
        _ => None
      }
    }
  }
}

///|
fn render_children(
  node : @markdown.MarkdownIR,
  position : RenderPosition,
) -> Array[@rabbita.Html] {
  node.children().map(child => render_node(child, position~))
}

///|
fn render_opaque_source(
  value : String,
  position : RenderPosition,
) -> @rabbita.Html {
  match position {
    Phrasing => @html.text(value)
    Flow =>
      @html.pre(class="m-0 whitespace-pre-wrap font-lm-ui text-inherit", value)
  }
}

///|
fn render_list_children(
  node : @markdown.MarkdownIR,
  parent_list_spread : Bool,
) -> Array[@rabbita.Html] {
  node
  .children()
  .map(child => {
    match child.view() {
      @markdown.ListItem(..) | @markdown.OrderedListItem(..) =>
        render_node(child, position=Flow, list_parent_spread=parent_list_spread)
      _ => render_node(child, position=Flow)
    }
  })
}

///|
fn render_list_item_children(
  node : @markdown.MarkdownIR,
  render_paragraphs : Bool,
  task : @markdown.MarkdownIRTask?,
) -> Array[@rabbita.Html] {
  let task_prefix = match task {
    Some(task) =>
      [
        @html.input(
          input_type=@html.Checkbox,
          checked=task.checked(),
          attrs=@html.Attrs::build()
            .disabled(true)
            .class(
              "mr-2 size-4 align-[-0.125em] accent-lm-accent disabled:opacity-100",
            )
            .data_set("loomark-task-checkbox", ""),
        ),
        @html.text(" "),
      ]
    None => []
  }
  node
  .children()
  .mapi((index, child) => {
    match child.view() {
      @markdown.Paragraph => {
        let children = render_children(child, Phrasing)
        let children = if index == 0 && task is Some(_) {
          let prefixed = task_prefix.copy()
          prefixed.append(children)
          prefixed
        } else {
          children
        }
        if render_paragraphs {
          @html.p(children)
        } else {
          @html.fragment(children)
        }
      }
      _ => render_node(child, position=Flow)
    }
  })
}

///|
fn render_heading(
  depth : Int,
  children : Array[@rabbita.Html],
) -> @rabbita.Html {
  match depth {
    1 => @html.h1(children)
    2 => @html.h2(children)
    3 => @html.h3(children)
    4 => @html.h4(children)
    5 => @html.h5(children)
    _ => @html.h6(children)
  }
}

///|
fn render_node(
  node : @markdown.MarkdownIR,
  position? : RenderPosition = Flow,
  list_parent_spread? : Bool = false,
  unwrap_list_item_paragraph? : Bool = false,
) -> @rabbita.Html {
  let node_view = node.view()
  let children = match node_view {
    @markdown.Document | @markdown.BlockQuote => render_children(node, Flow)
    @markdown.UnorderedList(spread~, ..) | @markdown.OrderedList(spread~, ..) =>
      render_list_children(node, spread)
    @markdown.ListItem(spread~, task~, ..)
    | @markdown.OrderedListItem(spread~, task~, ..) =>
      render_list_item_children(node, spread || list_parent_spread, task)
    @markdown.Heading(..)
    | @markdown.Paragraph
    | @markdown.Bold
    | @markdown.Italic
    | @markdown.Link(..) => render_children(node, Phrasing)
    @markdown.Image(..)
    | @markdown.CodeBlock(..)
    | @markdown.HtmlBlock(..)
    | @markdown.ThematicBreak
    | @markdown.Text(..)
    | @markdown.InlineCode(..)
    | @markdown.Autolink(..)
    | @markdown.InlineHtml(..)
    | @markdown.SoftBreak
    | @markdown.HardBreak(..)
    | @markdown.Unsupported(..)
    | @markdown.Raw(..)
    | @markdown.Recovered(..) => []
  }
  match node_view {
    @markdown.Document => @html.fragment(children)
    @markdown.Heading(depth~) => render_heading(depth, children)
    @markdown.Paragraph =>
      if unwrap_list_item_paragraph {
        @html.fragment(children)
      } else {
        @html.p(children)
      }
    @markdown.BlockQuote => @html.blockquote(children)
    @markdown.UnorderedList(spread~, marker~) =>
      @html.ul(
        attrs=@html.Attrs::build()
          .data_set("loomark-list-spread", spread.to_string())
          .data_set("loomark-list-marker", unordered_marker(marker)),
        children,
      )
    @markdown.OrderedList(spread~, marker~) => {
      let attrs = @html.Attrs::build()
        .data_set("loomark-list-spread", spread.to_string())
        .data_set("loomark-list-marker", ordered_marker(marker))
      match marker {
        Some(marker) => @html.ol(start=marker.start(), attrs~, children)
        None => @html.ol(attrs~, children)
      }
    }
    @markdown.ListItem(spread~, marker~, ..) =>
      @html.li(
        attrs=@html.Attrs::build()
          .data_set(
            "loomark-list-item-spread",
            (spread || list_parent_spread).to_string(),
          )
          .data_set("loomark-list-marker", unordered_marker(marker)),
        children,
      )
    @markdown.OrderedListItem(spread~, marker~, ..) =>
      @html.li(
        attrs=@html.Attrs::build()
          .data_set(
            "loomark-list-item-spread",
            (spread || list_parent_spread).to_string(),
          )
          .data_set("loomark-list-marker", ordered_marker(marker)),
        children,
      )
    @markdown.CodeBlock(info~, value~) =>
      @html.pre(
        @html.code(
          attrs=@html.Attrs::build().data_set("loomark-code-info", info),
          value,
        ),
      )
    @markdown.HtmlBlock(value~) =>
      @html.pre(
        attrs=@html.Attrs::build().data_set("loomark-preview-html", "block"),
        value,
      )
    @markdown.ThematicBreak => @html.hr()
    @markdown.Text(value~) => @html.text(value)
    @markdown.Bold => @html.strong(children)
    @markdown.Italic => @html.em(children)
    @markdown.InlineCode(value~) => @html.code(value)
    @markdown.Link(destination~, title~, surface~) =>
      match safe_destination(destination, image=false) {
        Some(destination) =>
          @html.a(
            href=destination,
            target=@html.Blank,
            rel="noopener noreferrer",
            escape=true,
            title?,
            attrs=@html.Attrs::build().data_set(
              "loomark-link-reference-form",
              link_form(surface.form),
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
    @markdown.Image(destination~, title~, surface=image_surface) => {
      let alt = plain_text(node)
      match safe_destination(destination, image=true) {
        Some(destination) =>
          @html.img(
            src=destination,
            alt~,
            title?,
            attrs=@html.Attrs::build().data_set(
              "loomark-image-reference-form",
              link_form(image_surface.form),
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
    @markdown.Autolink(kind~, display~, destination~, ..) =>
      match safe_destination(destination, image=false) {
        Some(destination) =>
          @html.a(
            href=destination,
            target=@html.Blank,
            rel="noopener noreferrer",
            escape=true,
            attrs=@html.Attrs::build().data_set(
              "loomark-autolink-kind",
              match kind {
                @markdown.UriAutolink => "uri"
                @markdown.EmailAutolink => "email"
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
    @markdown.InlineHtml(value~) =>
      @html.span(
        attrs=@html.Attrs::build().data_set("loomark-preview-html", "inline"),
        value,
      )
    @markdown.SoftBreak => @html.text("\n")
    @markdown.HardBreak(surface~) =>
      @html.br(
        attrs=@html.Attrs::build().data_set(
          "loomark-hard-break-form",
          match surface {
            @markdown.TrailingSpaces(_) => "trailing-spaces"
            @markdown.Backslash => "backslash"
          },
        ),
      )
    @markdown.Unsupported(message~) =>
      @html.div(
        attrs=@html.Attrs::build().data_set(
          "loomark-preview-fallback", "unsupported",
        ),
        "Unsupported Markdown: " + message,
      )
    @markdown.Raw(value~) => render_opaque_source(value, position)
    @markdown.Recovered(value~) => render_opaque_source(value, position)
  }
}

///|
/// Render one owning semantic Markdown document as typed Rabbita Html.
pub fn render(document : @markdown.MarkdownIR) -> @rabbita.Html {
  render_node(document)
}

///|
/// Render a parser-bound semantic publication while preserving unchanged
/// top-level virtual DOM subtrees.
fn render_publication(
  publication : @markdown.MarkdownSemanticPublication,
) -> @rabbita.Html {
  let document = publication.document()
  let children = document.children()
  let keys = publication.top_level_revision_keys()
  guard children.length() == keys.length() else {
    abort("Markdown publication renderer key count mismatch")
  }
  @html.fragment(
    children.mapi((index, child) => {
      @html.lazy(keys[index], () => render_node(child))
    }),
  )
}

///|
/// Report whether a semantic document has no renderable top-level children.
pub fn is_empty(document : @markdown.MarkdownIR) -> Bool {
  document.children().is_empty()
}
