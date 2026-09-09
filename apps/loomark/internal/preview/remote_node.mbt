///|
/// A detached semantic renderer node.  Its fields contain only validated
/// Markdown rendering data; it never contains the Markdown package's runtime
/// representation.
priv struct RemoteNode {
  view : @markdown.MarkdownNodeView
  children : Array[RemoteNode]
}

///|
fn RemoteNode::view(self : RemoteNode) -> @markdown.MarkdownNodeView {
  self.view
}

///|
fn RemoteNode::children(self : RemoteNode) -> Array[RemoteNode] {
  self.children.copy()
}

///|
fn remote_json_field(json : Json, name : String) -> Json raise {
  match json {
    Json::Object(fields) =>
      match fields.get(name) {
        Some(value) => value
        None => raise InvalidRemoteNode("missing field: " + name)
      }
    _ => raise InvalidRemoteNode("node is not an object")
  }
}

///|
fn remote_string(json : Json, name : String) -> String raise {
  match remote_json_field(json, name) {
    Json::String(value) => value
    _ => raise InvalidRemoteNode("field is not a string: " + name)
  }
}

///|
fn remote_bool(json : Json, name : String) -> Bool raise {
  match remote_json_field(json, name) {
    Json::True => true
    Json::False => false
    _ => raise InvalidRemoteNode("field is not a boolean: " + name)
  }
}

///|
fn remote_optional_string(json : Json, name : String) -> String? raise {
  match remote_json_field(json, name) {
    Json::Null => None
    Json::String(value) => Some(value)
    _ => raise InvalidRemoteNode("field is not a nullable string: " + name)
  }
}

///|
fn remote_int(json : Json, name : String) -> Int raise {
  match remote_json_field(json, name) {
    Json::Number(value, ..) => {
      let result = value.to_int()
      if result.to_double() != value {
        raise InvalidRemoteNode("field is not an integer: " + name)
      }
      result
    }
    _ => raise InvalidRemoteNode("field is not a number: " + name)
  }
}

///|
fn remote_optional_bool(json : Json, name : String) -> Bool? raise {
  match remote_json_field(json, name) {
    Json::Null => None
    Json::True => Some(true)
    Json::False => Some(false)
    _ => raise InvalidRemoteNode("field is not a nullable boolean: " + name)
  }
}

///|
fn remote_children(json : Json) -> Array[Json] raise {
  match remote_json_field(json, "children") {
    Json::Array(children) => children
    _ => raise InvalidRemoteNode("children is not an array")
  }
}

///|
fn remote_reference_form(json : Json) -> @markdown.MarkdownReferenceForm raise {
  match json {
    Json::String("inline") => @markdown.Inline
    Json::String("full-reference") => @markdown.FullReference
    Json::String("collapsed-reference") => @markdown.CollapsedReference
    Json::String("shortcut-reference") => @markdown.ShortcutReference
    _ => raise InvalidRemoteNode("invalid reference form")
  }
}

///|
fn remote_unordered_marker(json : Json) -> @markdown.UnorderedListMarker? raise {
  match json {
    Json::Null => None
    Json::String("-") => Some(@markdown.Dash)
    Json::String("*") => Some(@markdown.Star)
    Json::String("+") => Some(@markdown.Plus)
    _ => raise InvalidRemoteNode("invalid unordered marker")
  }
}

///|
fn remote_ordered_marker(json : Json) -> @markdown.OrderedListMarker? raise {
  match json {
    Json::Null => None
    Json::Object(fields) => {
      let start = match fields.get("start") {
        Some(Json::Number(value, ..)) => value.to_int()
        _ => raise InvalidRemoteNode("invalid ordered marker start")
      }
      if start < 0 {
        raise InvalidRemoteNode("invalid ordered marker start")
      }
      match fields.get("start") {
        Some(Json::Number(value, ..)) =>
          if start.to_double() != value {
            raise InvalidRemoteNode("invalid ordered marker start")
          }
        _ => raise InvalidRemoteNode("invalid ordered marker start")
      }
      let delimiter = match fields.get("delimiter") {
        Some(Json::String(".")) => @markdown.Period
        Some(Json::String(")")) => @markdown.Paren
        _ => raise InvalidRemoteNode("invalid ordered marker delimiter")
      }
      Some(@markdown.OrderedListMarker(start~, delimiter~))
    }
    _ => raise InvalidRemoteNode("invalid ordered marker")
  }
}

///|
fn remote_link_form(form : @markdown.MarkdownReferenceForm) -> Json {
  Json::string(
    match form {
      @markdown.Inline => "inline"
      @markdown.FullReference => "full-reference"
      @markdown.CollapsedReference => "collapsed-reference"
      @markdown.ShortcutReference => "shortcut-reference"
    },
  )
}

///|
fn remote_unordered_marker_json(
  marker : @markdown.UnorderedListMarker?,
) -> Json {
  match marker {
    Some(@markdown.Dash) => Json::string("-")
    Some(@markdown.Star) => Json::string("*")
    Some(@markdown.Plus) => Json::string("+")
    None => Json::null()
  }
}

///|
fn remote_ordered_marker_json(marker : @markdown.OrderedListMarker?) -> Json {
  match marker {
    None => Json::null()
    Some(marker) =>
      Json::object({
        "start": Json::number(marker.start().to_double()),
        "delimiter": Json::string(
          match marker.delimiter() {
            @markdown.Period => "."
            @markdown.Paren => ")"
          },
        ),
      })
  }
}

///|
fn remote_node_json(node : RenderNode) -> Json {
  let view = render_view(node)
  let children = render_children_nodes(node).map(remote_node_json)
  let fields : Map[String, Json] = { "children": Json::array(children) }
  match view {
    @markdown.Document => fields["kind"] = Json::string("document")
    @markdown.Heading(depth~) => {
      fields["kind"] = Json::string("heading")
      fields["depth"] = Json::number(depth.to_double())
    }
    @markdown.Paragraph => fields["kind"] = Json::string("paragraph")
    @markdown.BlockQuote => fields["kind"] = Json::string("blockquote")
    @markdown.UnorderedList(spread~, marker~) => {
      fields["kind"] = Json::string("unordered-list")
      fields["spread"] = Json::boolean(spread)
      fields["marker"] = remote_unordered_marker_json(marker)
    }
    @markdown.OrderedList(spread~, marker~) => {
      fields["kind"] = Json::string("ordered-list")
      fields["spread"] = Json::boolean(spread)
      fields["marker"] = remote_ordered_marker_json(marker)
    }
    @markdown.ListItem(spread~, marker~, task_checked~) => {
      fields["kind"] = Json::string("list-item")
      fields["spread"] = Json::boolean(spread)
      fields["marker"] = remote_unordered_marker_json(marker)
      fields["task"] = match task_checked {
        Some(value) => Json::boolean(value)
        None => Json::null()
      }
    }
    @markdown.OrderedListItem(spread~, marker~, task_checked~) => {
      fields["kind"] = Json::string("ordered-list-item")
      fields["spread"] = Json::boolean(spread)
      fields["marker"] = remote_ordered_marker_json(marker)
      fields["task"] = match task_checked {
        Some(value) => Json::boolean(value)
        None => Json::null()
      }
    }
    @markdown.CodeBlock(info~, value~) => {
      fields["kind"] = Json::string("code")
      fields["info"] = Json::string(info)
      fields["value"] = Json::string(value)
    }
    @markdown.HtmlBlock(value~) => {
      fields["kind"] = Json::string("html-block")
      fields["value"] = Json::string(value)
    }
    @markdown.ThematicBreak => fields["kind"] = Json::string("thematic-break")
    @markdown.Text(value~) => {
      fields["kind"] = Json::string("text")
      fields["value"] = Json::string(value)
    }
    @markdown.Strong => fields["kind"] = Json::string("strong")
    @markdown.Emphasis => fields["kind"] = Json::string("emphasis")
    @markdown.InlineCode(value~) => {
      fields["kind"] = Json::string("inline-code")
      fields["value"] = Json::string(value)
    }
    @markdown.Link(destination~, title~, reference_form~) => {
      fields["kind"] = Json::string("link")
      fields["destination"] = Json::string(destination)
      fields["title"] = match title {
        Some(value) => Json::string(value)
        None => Json::null()
      }
      fields["reference"] = remote_link_form(reference_form)
    }
    @markdown.Image(destination~, title~, reference_form~) => {
      fields["kind"] = Json::string("image")
      fields["destination"] = Json::string(destination)
      fields["title"] = match title {
        Some(value) => Json::string(value)
        None => Json::null()
      }
      fields["reference"] = remote_link_form(reference_form)
    }
    @markdown.Autolink(kind~, display~, destination~) => {
      fields["kind"] = Json::string("autolink")
      fields["autolink"] = Json::string(
        match kind {
          @markdown.Uri => "uri"
          @markdown.Email => "email"
        },
      )
      fields["display"] = Json::string(display)
      fields["destination"] = Json::string(destination)
    }
    @markdown.InlineHtml(value~) => {
      fields["kind"] = Json::string("html-inline")
      fields["value"] = Json::string(value)
    }
    @markdown.SoftBreak => fields["kind"] = Json::string("soft-break")
    @markdown.HardBreak(form~) => {
      fields["kind"] = Json::string("hard-break")
      fields["form"] = match form {
        @markdown.TrailingSpaces(count) => Json::number(count.to_double())
        @markdown.Backslash => Json::string("backslash")
      }
    }
    @markdown.Unsupported(message~) => {
      fields["kind"] = Json::string("unsupported")
      fields["value"] = Json::string(message)
    }
    @markdown.Raw(value~) => {
      fields["kind"] = Json::string("raw")
      fields["value"] = Json::string(value)
    }
    @markdown.Recovered(value~) => {
      fields["kind"] = Json::string("recovered")
      fields["value"] = Json::string(value)
    }
  }
  Json::object(fields)
}

///|
fn encode_node(node : @markdown.MarkdownNode) -> Json {
  remote_node_json(Local(node))
}

///|
priv suberror InvalidRemoteNode {
  InvalidRemoteNode(String)
  RemoteNodeLimit
}

///|
fn decode_remote_node(
  json : Json,
  depth : Int,
  count : Ref[Int],
) -> RemoteNode raise {
  if depth > 256 {
    raise InvalidRemoteNode::RemoteNodeLimit
  }
  count.val = count.val + 1
  if count.val > 10000 {
    raise InvalidRemoteNode::RemoteNodeLimit
  }
  let kind = remote_string(json, "kind")
  let view : @markdown.MarkdownNodeView = match kind {
    "document" => @markdown.Document
    "heading" => {
      let depth = remote_int(json, "depth")
      if depth < 1 || depth > 6 {
        raise InvalidRemoteNode("invalid heading depth")
      }
      @markdown.Heading(depth~)
    }
    "paragraph" => @markdown.Paragraph
    "blockquote" => @markdown.BlockQuote
    "unordered-list" =>
      @markdown.UnorderedList(
        spread=remote_bool(json, "spread"),
        marker=remote_unordered_marker(remote_json_field(json, "marker")),
      )
    "ordered-list" =>
      @markdown.OrderedList(
        spread=remote_bool(json, "spread"),
        marker=remote_ordered_marker(remote_json_field(json, "marker")),
      )
    "list-item" =>
      @markdown.ListItem(
        spread=remote_bool(json, "spread"),
        marker=remote_unordered_marker(remote_json_field(json, "marker")),
        task_checked=remote_optional_bool(json, "task"),
      )
    "ordered-list-item" =>
      @markdown.OrderedListItem(
        spread=remote_bool(json, "spread"),
        marker=remote_ordered_marker(remote_json_field(json, "marker")),
        task_checked=remote_optional_bool(json, "task"),
      )
    "code" =>
      @markdown.CodeBlock(
        info=remote_string(json, "info"),
        value=remote_string(json, "value"),
      )
    "html-block" => @markdown.HtmlBlock(value=remote_string(json, "value"))
    "thematic-break" => @markdown.ThematicBreak
    "text" => @markdown.Text(value=remote_string(json, "value"))
    "strong" => @markdown.Strong
    "emphasis" => @markdown.Emphasis
    "inline-code" => @markdown.InlineCode(value=remote_string(json, "value"))
    "link" =>
      @markdown.Link(
        destination=remote_string(json, "destination"),
        title=remote_optional_string(json, "title"),
        reference_form=remote_reference_form(
          remote_json_field(json, "reference"),
        ),
      )
    "image" =>
      @markdown.Image(
        destination=remote_string(json, "destination"),
        title=remote_optional_string(json, "title"),
        reference_form=remote_reference_form(
          remote_json_field(json, "reference"),
        ),
      )
    "autolink" => {
      let autolink_kind = match remote_string(json, "autolink") {
        "uri" => @markdown.Uri
        "email" => @markdown.Email
        _ => raise InvalidRemoteNode("invalid autolink kind")
      }
      @markdown.Autolink(
        kind=autolink_kind,
        display=remote_string(json, "display"),
        destination=remote_string(json, "destination"),
      )
    }
    "html-inline" => @markdown.InlineHtml(value=remote_string(json, "value"))
    "soft-break" => @markdown.SoftBreak
    "hard-break" => {
      let form = match remote_json_field(json, "form") {
        Json::String("backslash") => @markdown.MarkdownHardBreakForm::Backslash
        Json::Number(value, ..) => {
          let count = value.to_int()
          if count < 1 || count.to_double() != value {
            raise InvalidRemoteNode("invalid hard break count")
          }
          @markdown.MarkdownHardBreakForm::TrailingSpaces(count)
        }
        _ => raise InvalidRemoteNode("invalid hard break form")
      }
      @markdown.HardBreak(form~)
    }
    "unsupported" => @markdown.Unsupported(message=remote_string(json, "value"))
    "raw" => @markdown.Raw(value=remote_string(json, "value"))
    "recovered" => @markdown.Recovered(value=remote_string(json, "value"))
    _ => raise InvalidRemoteNode("unknown node kind: " + kind)
  }
  let children = remote_children(json).map(child => {
    decode_remote_node(child, depth + 1, count)
  })
  { view, children }
}

///|
fn decode_node(json : Json) -> RemoteNode raise {
  decode_remote_node(json, 0, Ref(0))
}

///|
fn render_remote_node(root : RemoteNode) -> @rabbita.Html {
  render_node(Remote(root))
}
