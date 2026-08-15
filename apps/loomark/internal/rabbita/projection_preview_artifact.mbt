///|
/// A portable source range. Both offsets are UTF-16 code-unit offsets in the
/// source retained beside the artifact by the Worker response.
type ProjectionPreviewRange = (Int, Int)

///|
priv enum ProjectionPreviewLinkForm {
  PreviewInlineLink
  PreviewFullReferenceLink
  PreviewCollapsedReferenceLink
  PreviewShortcutReferenceLink
} derive(Eq, Debug)

///|
priv enum ProjectionPreviewUnorderedMarker {
  PreviewDash
  PreviewStar
  PreviewPlus
} derive(Eq, Debug)

///|
priv struct ProjectionPreviewOrderedMarker {
  start : Int
  text : String
} derive(Eq, Debug)

///|
priv enum ProjectionPreviewAutolinkKind {
  PreviewUriAutolink
  PreviewEmailAutolink
} derive(Eq, Debug)

///|
priv enum ProjectionPreviewHardBreakForm {
  PreviewTrailingSpaces(Int)
  PreviewBackslash
} derive(Eq, Debug)

///|
/// This enum deliberately mirrors every public `MarkdownIRView` constructor.
/// It contains only values that can cross the Worker boundary.
priv enum ProjectionPreviewView {
  PreviewDocument
  PreviewHeading(Int)
  PreviewParagraph
  PreviewBlockQuote
  PreviewUnorderedList(Bool, ProjectionPreviewUnorderedMarker?)
  PreviewOrderedList(Bool, ProjectionPreviewOrderedMarker?)
  PreviewListItem(Bool, ProjectionPreviewUnorderedMarker?)
  PreviewOrderedListItem(Bool, ProjectionPreviewOrderedMarker?)
  PreviewCodeBlock(String, String)
  PreviewHtmlBlock(String)
  PreviewThematicBreak
  PreviewText(String)
  PreviewBold
  PreviewItalic
  PreviewInlineCode(String)
  PreviewLink(String, String?, ProjectionPreviewLinkForm)
  PreviewImage(String, String?, ProjectionPreviewLinkForm)
  PreviewAutolink(ProjectionPreviewAutolinkKind, String, String)
  PreviewInlineHtml(String)
  PreviewSoftBreak
  PreviewHardBreak(ProjectionPreviewHardBreakForm)
  PreviewUnsupported(String)
  PreviewRaw(String)
  PreviewRecovered(String)
} derive(Eq, Debug)

///|
priv struct ProjectionPreviewNode {
  origin : ProjectionPreviewRange
  view : ProjectionPreviewView
  diagnostics : Array[String]
  children : Array[ProjectionPreviewNode]
} derive(Eq, Debug)

///|
priv struct ProjectionPreviewArtifact {
  root : ProjectionPreviewNode
} derive(Eq, Debug)

///|
fn projection_preview_link_form_json(form : ProjectionPreviewLinkForm) -> Json {
  Json::string(
    match form {
      PreviewInlineLink => "inline"
      PreviewFullReferenceLink => "full-reference"
      PreviewCollapsedReferenceLink => "collapsed-reference"
      PreviewShortcutReferenceLink => "shortcut-reference"
    },
  )
}

///|
fn projection_preview_link_form_from_json(
  value : Json,
) -> ProjectionPreviewLinkForm raise {
  match value {
    Json::String("inline") => PreviewInlineLink
    Json::String("full-reference") => PreviewFullReferenceLink
    Json::String("collapsed-reference") => PreviewCollapsedReferenceLink
    Json::String("shortcut-reference") => PreviewShortcutReferenceLink
    _ => projection_preview_decode_fail("link form must be a known string")
  }
}

///|
fn projection_preview_unordered_marker_json(
  marker : ProjectionPreviewUnorderedMarker,
) -> Json {
  Json::string(
    match marker {
      PreviewDash => "dash"
      PreviewStar => "star"
      PreviewPlus => "plus"
    },
  )
}

///|
fn projection_preview_unordered_marker_from_json(
  value : Json,
) -> ProjectionPreviewUnorderedMarker raise {
  match value {
    Json::String("dash") => PreviewDash
    Json::String("star") => PreviewStar
    Json::String("plus") => PreviewPlus
    _ =>
      projection_preview_decode_fail("unordered marker must be a known string")
  }
}

///|
fn projection_preview_ordered_marker_json(
  marker : ProjectionPreviewOrderedMarker,
) -> Json {
  Json::object({
    "start": Json::number(marker.start.to_double()),
    "text": Json::string(marker.text),
  })
}

///|
fn projection_preview_autolink_kind_json(
  kind : ProjectionPreviewAutolinkKind,
) -> Json {
  Json::string(
    match kind {
      PreviewUriAutolink => "uri"
      PreviewEmailAutolink => "email"
    },
  )
}

///|
fn projection_preview_autolink_kind_from_json(
  value : Json,
) -> ProjectionPreviewAutolinkKind raise {
  match value {
    Json::String("uri") => PreviewUriAutolink
    Json::String("email") => PreviewEmailAutolink
    _ => projection_preview_decode_fail("autolink kind must be a known string")
  }
}

///|
fn projection_preview_hard_break_form_json(
  form : ProjectionPreviewHardBreakForm,
) -> Json {
  match form {
    PreviewTrailingSpaces(count) =>
      Json::object({
        "kind": Json::string("trailing-spaces"),
        "count": Json::number(count.to_double()),
      })
    PreviewBackslash => Json::object({ "kind": Json::string("backslash") })
  }
}

///|
fn projection_preview_json_int(value : Json) -> Int? {
  match value {
    Json::Number(number, ..) => {
      let integer = number.to_int()
      if number == integer.to_double() {
        Some(integer)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn projection_preview_range_json(range : ProjectionPreviewRange) -> Json {
  Json::array([
    Json::number(range.0.to_double()),
    Json::number(range.1.to_double()),
  ])
}

///|
fn projection_preview_range_from_json(
  value : Json,
) -> ProjectionPreviewRange raise {
  match value {
    Json::Array(values) => {
      guard values.length() == 2 else {
        projection_preview_decode_fail(
          "origin must contain exactly two offsets",
        )
      }
      guard projection_preview_json_int(values[0]) is Some(start) else {
        projection_preview_decode_fail("origin start must be an integer")
      }
      guard projection_preview_json_int(values[1]) is Some(end) else {
        projection_preview_decode_fail("origin end must be an integer")
      }
      guard start >= 0 && end >= start else {
        projection_preview_decode_fail(
          "origin must be non-negative and ordered",
        )
      }
      (start, end)
    }
    _ => projection_preview_decode_fail("origin must be an array")
  }
}

///|
fn projection_preview_optional_string_json(value : String?) -> Json {
  match value {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

///|
fn[T] projection_preview_decode_fail(message : String) -> T raise {
  raise Failure::Failure(message)
}

///|
fn projection_preview_required_string(
  fields : Map[String, Json],
  name : String,
) -> String raise {
  match fields.get(name) {
    Some(Json::String(value)) => value
    _ => projection_preview_decode_fail(name + " must be a string")
  }
}

///|
fn projection_preview_required_int(
  fields : Map[String, Json],
  name : String,
) -> Int raise {
  match fields.get(name) {
    Some(value) =>
      match projection_preview_json_int(value) {
        Some(number) => number
        None => projection_preview_decode_fail(name + " must be an integer")
      }
    None => projection_preview_decode_fail(name + " is missing")
  }
}

///|
fn projection_preview_required_bool(
  fields : Map[String, Json],
  name : String,
) -> Bool raise {
  match fields.get(name) {
    Some(Json::True) => true
    Some(Json::False) => false
    _ => projection_preview_decode_fail(name + " must be a boolean")
  }
}

///|
fn projection_preview_optional_string(
  fields : Map[String, Json],
  name : String,
) -> String? raise {
  match fields.get(name) {
    Some(Json::Null) => None
    Some(Json::String(value)) => Some(value)
    _ => projection_preview_decode_fail(name + " must be a string or null")
  }
}

///|
fn projection_preview_has_only_fields(
  fields : Map[String, Json],
  allowed : String,
) -> Unit raise {
  for key, _ in fields {
    if !("|" + allowed + "|").contains("|" + key + "|") {
      projection_preview_decode_fail("unknown field: " + key)
    }
  }
}

///|
fn projection_preview_require_field(
  fields : Map[String, Json],
  name : String,
) -> Unit raise {
  if fields.get(name) is None {
    projection_preview_decode_fail(name + " is missing")
  }
}

///|
fn projection_preview_optional_unordered_marker_json(
  marker : ProjectionPreviewUnorderedMarker?,
) -> Json {
  match marker {
    Some(value) => projection_preview_unordered_marker_json(value)
    None => Json::null()
  }
}

///|
fn projection_preview_optional_unordered_marker_from_json(
  value : Json,
) -> ProjectionPreviewUnorderedMarker? raise {
  match value {
    Json::Null => None
    _ => Some(projection_preview_unordered_marker_from_json(value))
  }
}

///|
fn projection_preview_optional_ordered_marker_json(
  marker : ProjectionPreviewOrderedMarker?,
) -> Json {
  match marker {
    Some(value) => projection_preview_ordered_marker_json(value)
    None => Json::null()
  }
}

///|
fn projection_preview_ordered_marker_from_json(
  value : Json,
) -> ProjectionPreviewOrderedMarker raise {
  match value {
    Json::Object(fields) => {
      projection_preview_has_only_fields(fields, "start|text")
      let start = projection_preview_required_int(fields, "start")
      guard start >= 1 else {
        projection_preview_decode_fail("ordered marker start must be positive")
      }
      let text = projection_preview_required_string(fields, "text")
      { start, text }
    }
    _ => projection_preview_decode_fail("ordered marker must be an object")
  }
}

///|
fn projection_preview_optional_ordered_marker_from_json(
  value : Json,
) -> ProjectionPreviewOrderedMarker? raise {
  match value {
    Json::Null => None
    _ => Some(projection_preview_ordered_marker_from_json(value))
  }
}

///|
fn projection_preview_hard_break_form_from_json(
  value : Json,
) -> ProjectionPreviewHardBreakForm raise {
  match value {
    Json::Object(fields) => {
      projection_preview_has_only_fields(fields, "kind|count")
      let kind = projection_preview_required_string(fields, "kind")
      match kind {
        "backslash" => {
          guard fields.length() == 1 else {
            projection_preview_decode_fail(
              "backslash hard break has no extra fields",
            )
          }
          PreviewBackslash
        }
        "trailing-spaces" => {
          let count = projection_preview_required_int(fields, "count")
          guard count > 0 else {
            projection_preview_decode_fail(
              "trailing-spaces count must be positive",
            )
          }
          PreviewTrailingSpaces(count)
        }
        _ => projection_preview_decode_fail("unknown hard break form")
      }
    }
    _ => projection_preview_decode_fail("hard break form must be an object")
  }
}

///|
fn projection_preview_view_json(view : ProjectionPreviewView) -> Json {
  match view {
    PreviewDocument => Json::object({ "kind": Json::string("document") })
    PreviewHeading(level) =>
      Json::object({
        "kind": Json::string("heading"),
        "level": Json::number(level.to_double()),
      })
    PreviewParagraph => Json::object({ "kind": Json::string("paragraph") })
    PreviewBlockQuote => Json::object({ "kind": Json::string("blockquote") })
    PreviewUnorderedList(spread, marker) =>
      Json::object({
        "kind": Json::string("unordered-list"),
        "spread": Json::boolean(spread),
        "marker": projection_preview_optional_unordered_marker_json(marker),
      })
    PreviewOrderedList(spread, marker) =>
      Json::object({
        "kind": Json::string("ordered-list"),
        "spread": Json::boolean(spread),
        "marker": projection_preview_optional_ordered_marker_json(marker),
      })
    PreviewListItem(spread, marker) =>
      Json::object({
        "kind": Json::string("list-item"),
        "spread": Json::boolean(spread),
        "marker": projection_preview_optional_unordered_marker_json(marker),
      })
    PreviewOrderedListItem(spread, marker) =>
      Json::object({
        "kind": Json::string("ordered-list-item"),
        "spread": Json::boolean(spread),
        "marker": projection_preview_optional_ordered_marker_json(marker),
      })
    PreviewCodeBlock(info, value) =>
      Json::object({
        "kind": Json::string("code-block"),
        "info": Json::string(info),
        "value": Json::string(value),
      })
    PreviewHtmlBlock(value) =>
      Json::object({
        "kind": Json::string("html-block"),
        "value": Json::string(value),
      })
    PreviewThematicBreak =>
      Json::object({ "kind": Json::string("thematic-break") })
    PreviewText(value) =>
      Json::object({
        "kind": Json::string("text"),
        "value": Json::string(value),
      })
    PreviewBold => Json::object({ "kind": Json::string("bold") })
    PreviewItalic => Json::object({ "kind": Json::string("italic") })
    PreviewInlineCode(value) =>
      Json::object({
        "kind": Json::string("inline-code"),
        "value": Json::string(value),
      })
    PreviewLink(destination, title, form) =>
      Json::object({
        "kind": Json::string("link"),
        "destination": Json::string(destination),
        "title": projection_preview_optional_string_json(title),
        "form": projection_preview_link_form_json(form),
      })
    PreviewImage(destination, title, form) =>
      Json::object({
        "kind": Json::string("image"),
        "destination": Json::string(destination),
        "title": projection_preview_optional_string_json(title),
        "form": projection_preview_link_form_json(form),
      })
    PreviewAutolink(kind, display, destination) =>
      Json::object({
        "kind": Json::string("autolink"),
        "autolink_kind": projection_preview_autolink_kind_json(kind),
        "display": Json::string(display),
        "destination": Json::string(destination),
      })
    PreviewInlineHtml(value) =>
      Json::object({
        "kind": Json::string("inline-html"),
        "value": Json::string(value),
      })
    PreviewSoftBreak => Json::object({ "kind": Json::string("soft-break") })
    PreviewHardBreak(form) =>
      Json::object({
        "kind": Json::string("hard-break"),
        "form": projection_preview_hard_break_form_json(form),
      })
    PreviewUnsupported(message) =>
      Json::object({
        "kind": Json::string("unsupported"),
        "message": Json::string(message),
      })
    PreviewRaw(value) =>
      Json::object({ "kind": Json::string("raw"), "value": Json::string(value) })
    PreviewRecovered(message) =>
      Json::object({
        "kind": Json::string("recovered"),
        "message": Json::string(message),
      })
  }
}

///|
fn projection_preview_view_from_json(
  value : Json,
) -> ProjectionPreviewView raise {
  match value {
    Json::Object(fields) => {
      let kind = projection_preview_required_string(fields, "kind")
      match kind {
        "document" => {
          projection_preview_has_only_fields(fields, "kind")
          PreviewDocument
        }
        "heading" => {
          projection_preview_has_only_fields(fields, "kind|level")
          let level = projection_preview_required_int(fields, "level")
          guard level >= 1 && level <= 6 else {
            projection_preview_decode_fail(
              "heading level must be between 1 and 6",
            )
          }
          PreviewHeading(level)
        }
        "paragraph" => {
          projection_preview_has_only_fields(fields, "kind")
          PreviewParagraph
        }
        "blockquote" => {
          projection_preview_has_only_fields(fields, "kind")
          PreviewBlockQuote
        }
        "unordered-list" => {
          projection_preview_has_only_fields(fields, "kind|spread|marker")
          let spread = projection_preview_required_bool(fields, "spread")
          let marker = match fields.get("marker") {
            Some(value) =>
              projection_preview_optional_unordered_marker_from_json(value)
            None => projection_preview_decode_fail("marker is missing")
          }
          PreviewUnorderedList(spread, marker)
        }
        "ordered-list" => {
          projection_preview_has_only_fields(fields, "kind|spread|marker")
          let spread = projection_preview_required_bool(fields, "spread")
          let marker = match fields.get("marker") {
            Some(value) =>
              projection_preview_optional_ordered_marker_from_json(value)
            None => projection_preview_decode_fail("marker is missing")
          }
          PreviewOrderedList(spread, marker)
        }
        "list-item" => {
          projection_preview_has_only_fields(fields, "kind|spread|marker")
          let spread = projection_preview_required_bool(fields, "spread")
          let marker = match fields.get("marker") {
            Some(value) =>
              projection_preview_optional_unordered_marker_from_json(value)
            None => projection_preview_decode_fail("marker is missing")
          }
          PreviewListItem(spread, marker)
        }
        "ordered-list-item" => {
          projection_preview_has_only_fields(fields, "kind|spread|marker")
          let spread = projection_preview_required_bool(fields, "spread")
          let marker = match fields.get("marker") {
            Some(value) =>
              projection_preview_optional_ordered_marker_from_json(value)
            None => projection_preview_decode_fail("marker is missing")
          }
          PreviewOrderedListItem(spread, marker)
        }
        "code-block" => {
          projection_preview_has_only_fields(fields, "kind|info|value")
          let info = projection_preview_required_string(fields, "info")
          let value = projection_preview_required_string(fields, "value")
          PreviewCodeBlock(info, value)
        }
        "html-block" => {
          projection_preview_has_only_fields(fields, "kind|value")
          PreviewHtmlBlock(projection_preview_required_string(fields, "value"))
        }
        "thematic-break" => {
          projection_preview_has_only_fields(fields, "kind")
          PreviewThematicBreak
        }
        "text" => {
          projection_preview_has_only_fields(fields, "kind|value")
          PreviewText(projection_preview_required_string(fields, "value"))
        }
        "bold" => {
          projection_preview_has_only_fields(fields, "kind")
          PreviewBold
        }
        "italic" => {
          projection_preview_has_only_fields(fields, "kind")
          PreviewItalic
        }
        "inline-code" => {
          projection_preview_has_only_fields(fields, "kind|value")
          PreviewInlineCode(projection_preview_required_string(fields, "value"))
        }
        "link" | "image" => {
          projection_preview_has_only_fields(
            fields, "kind|destination|title|form",
          )
          let destination = projection_preview_required_string(
            fields, "destination",
          )
          let title = projection_preview_optional_string(fields, "title")
          let form = match fields.get("form") {
            Some(value) => projection_preview_link_form_from_json(value)
            None => projection_preview_decode_fail("form is missing")
          }
          if kind == "link" {
            PreviewLink(destination, title, form)
          } else {
            PreviewImage(destination, title, form)
          }
        }
        "autolink" => {
          projection_preview_has_only_fields(
            fields, "kind|autolink_kind|display|destination",
          )
          let link_kind = match fields.get("autolink_kind") {
            Some(value) => projection_preview_autolink_kind_from_json(value)
            None => projection_preview_decode_fail("autolink_kind is missing")
          }
          let display = projection_preview_required_string(fields, "display")
          let destination = projection_preview_required_string(
            fields, "destination",
          )
          PreviewAutolink(link_kind, display, destination)
        }
        "inline-html" => {
          projection_preview_has_only_fields(fields, "kind|value")
          PreviewInlineHtml(projection_preview_required_string(fields, "value"))
        }
        "soft-break" => {
          projection_preview_has_only_fields(fields, "kind")
          PreviewSoftBreak
        }
        "hard-break" => {
          projection_preview_has_only_fields(fields, "kind|form")
          let form = match fields.get("form") {
            Some(value) => projection_preview_hard_break_form_from_json(value)
            None => projection_preview_decode_fail("form is missing")
          }
          PreviewHardBreak(form)
        }
        "unsupported" => {
          projection_preview_has_only_fields(fields, "kind|message")
          PreviewUnsupported(
            projection_preview_required_string(fields, "message"),
          )
        }
        "raw" => {
          projection_preview_has_only_fields(fields, "kind|value")
          PreviewRaw(projection_preview_required_string(fields, "value"))
        }
        "recovered" => {
          projection_preview_has_only_fields(fields, "kind|message")
          PreviewRecovered(
            projection_preview_required_string(fields, "message"),
          )
        }
        _ => projection_preview_decode_fail("unknown preview view kind")
      }
    }
    _ => projection_preview_decode_fail("view must be an object")
  }
}

///|
fn projection_preview_node_json(node : ProjectionPreviewNode) -> Json {
  Json::object({
    "origin": projection_preview_range_json(node.origin),
    "view": projection_preview_view_json(node.view),
    "diagnostics": Json::array(node.diagnostics.map(Json::string)),
    "children": Json::array(node.children.map(projection_preview_node_json)),
  })
}

///|
fn projection_preview_diagnostics_from_json(
  value : Json,
) -> Array[String] raise {
  match value {
    Json::Array(values) => {
      let diagnostics : Array[String] = []
      for value in values {
        match value {
          Json::String(text) => diagnostics.push(text)
          _ =>
            projection_preview_decode_fail("diagnostics must contain strings")
        }
      }
      diagnostics
    }
    _ => projection_preview_decode_fail("diagnostics must be an array")
  }
}

///|
fn projection_preview_children_from_json(
  value : Json,
  parent_origin : ProjectionPreviewRange,
) -> Array[ProjectionPreviewNode] raise {
  match value {
    Json::Array(values) => {
      let children : Array[ProjectionPreviewNode] = []
      for value in values {
        let child = projection_preview_node_from_json(value)
        guard child.origin.0 >= parent_origin.0 &&
          child.origin.1 <= parent_origin.1 else {
          projection_preview_decode_fail(
            "child origin must be contained by parent origin",
          )
        }
        children.push(child)
      }
      children
    }
    _ => projection_preview_decode_fail("children must be an array")
  }
}

///|
fn projection_preview_node_from_json(
  value : Json,
) -> ProjectionPreviewNode raise {
  match value {
    Json::Object(fields) => {
      projection_preview_has_only_fields(
        fields, "origin|view|diagnostics|children",
      )
      projection_preview_require_field(fields, "origin")
      projection_preview_require_field(fields, "view")
      projection_preview_require_field(fields, "diagnostics")
      projection_preview_require_field(fields, "children")
      let origin = projection_preview_range_from_json(fields["origin"])
      let view = projection_preview_view_from_json(fields["view"])
      let diagnostics = projection_preview_diagnostics_from_json(
        fields["diagnostics"],
      )
      let children = projection_preview_children_from_json(
        fields["children"],
        origin,
      )
      { origin, view, diagnostics, children }
    }
    _ => projection_preview_decode_fail("preview node must be an object")
  }
}

///|
fn projection_preview_artifact_json(
  artifact : ProjectionPreviewArtifact,
) -> Json {
  Json::object({ "root": projection_preview_node_json(artifact.root) })
}

///|
fn projection_preview_artifact_from_json(
  value : Json,
) -> Result[ProjectionPreviewArtifact, String] {
  try {
    match value {
      Json::Object(fields) => {
        projection_preview_has_only_fields(fields, "root")
        projection_preview_require_field(fields, "root")
        Ok({ root: projection_preview_node_from_json(fields["root"]) })
      }
      _ => Err("preview artifact must be an object")
    }
  } catch {
    error => Err(error.to_string())
  }
}

///|
fn projection_preview_link_form_from_markdown(
  form : @md_markdown.MarkdownIRLinkReferenceForm,
) -> ProjectionPreviewLinkForm {
  match form {
    @md_markdown.InlineLinkForm => PreviewInlineLink
    @md_markdown.FullReferenceLinkForm => PreviewFullReferenceLink
    @md_markdown.CollapsedReferenceLinkForm => PreviewCollapsedReferenceLink
    @md_markdown.ShortcutReferenceLinkForm => PreviewShortcutReferenceLink
  }
}

///|
fn projection_preview_unordered_marker_from_markdown(
  marker : @md_markdown.UnorderedListMarker?,
) -> ProjectionPreviewUnorderedMarker? {
  match marker {
    Some(@md_markdown.Dash) => Some(PreviewDash)
    Some(@md_markdown.Star) => Some(PreviewStar)
    Some(@md_markdown.Plus) => Some(PreviewPlus)
    None => None
  }
}

///|
fn projection_preview_ordered_marker_from_markdown(
  marker : @md_markdown.OrderedListMarker?,
) -> ProjectionPreviewOrderedMarker? {
  marker.map(value => { start: value.start(), text: value.text() })
}

///|
fn projection_preview_autolink_kind_from_markdown(
  kind : @md_markdown.MarkdownIRAutolinkKind,
) -> ProjectionPreviewAutolinkKind {
  match kind {
    @md_markdown.UriAutolink => PreviewUriAutolink
    @md_markdown.EmailAutolink => PreviewEmailAutolink
  }
}

///|
fn projection_preview_hard_break_form_from_markdown(
  form : @md_markdown.MarkdownIRHardBreakSurface,
) -> ProjectionPreviewHardBreakForm {
  match form {
    @md_markdown.TrailingSpaces(count) => PreviewTrailingSpaces(count)
    @md_markdown.Backslash => PreviewBackslash
  }
}

///|
fn projection_preview_node_from_markdown_ir(
  node : @md_markdown.MarkdownIR,
) -> ProjectionPreviewNode {
  let view = match node.view() {
    @md_markdown.Document => PreviewDocument
    @md_markdown.Heading(depth~) => PreviewHeading(depth)
    @md_markdown.Paragraph => PreviewParagraph
    @md_markdown.BlockQuote => PreviewBlockQuote
    @md_markdown.UnorderedList(spread~, marker~) =>
      PreviewUnorderedList(
        spread,
        projection_preview_unordered_marker_from_markdown(marker),
      )
    @md_markdown.OrderedList(spread~, marker~) =>
      PreviewOrderedList(
        spread,
        projection_preview_ordered_marker_from_markdown(marker),
      )
    @md_markdown.ListItem(spread~, marker~) =>
      PreviewListItem(
        spread,
        projection_preview_unordered_marker_from_markdown(marker),
      )
    @md_markdown.OrderedListItem(spread~, marker~) =>
      PreviewOrderedListItem(
        spread,
        projection_preview_ordered_marker_from_markdown(marker),
      )
    @md_markdown.CodeBlock(info~, value~) => PreviewCodeBlock(info, value)
    @md_markdown.HtmlBlock(value~) => PreviewHtmlBlock(value)
    @md_markdown.ThematicBreak => PreviewThematicBreak
    @md_markdown.Text(value~) => PreviewText(value)
    @md_markdown.Bold => PreviewBold
    @md_markdown.Italic => PreviewItalic
    @md_markdown.InlineCode(value~) => PreviewInlineCode(value)
    @md_markdown.Link(destination~, title~, surface=form) =>
      PreviewLink(
        destination,
        title,
        projection_preview_link_form_from_markdown(form.form),
      )
    @md_markdown.Image(destination~, title~, surface=form) =>
      PreviewImage(
        destination,
        title,
        projection_preview_link_form_from_markdown(form.form),
      )
    @md_markdown.Autolink(kind~, display~, destination~, ..) =>
      PreviewAutolink(
        projection_preview_autolink_kind_from_markdown(kind),
        display,
        destination,
      )
    @md_markdown.InlineHtml(value~) => PreviewInlineHtml(value)
    @md_markdown.SoftBreak => PreviewSoftBreak
    @md_markdown.HardBreak(surface=form) =>
      PreviewHardBreak(projection_preview_hard_break_form_from_markdown(form))
    @md_markdown.Unsupported(message~) => PreviewUnsupported(message)
    @md_markdown.Raw(value~) => PreviewRaw(value)
    @md_markdown.Recovered(message~) => PreviewRecovered(message)
  }
  {
    origin: (node.origin().start(), node.origin().end()),
    view,
    diagnostics: node.diagnostics().map(diagnostic => diagnostic.format()),
    children: node.children().map(projection_preview_node_from_markdown_ir),
  }
}

///|
fn projection_preview_artifact_from_markdown_ir(
  document : @md_markdown.MarkdownIR,
) -> ProjectionPreviewArtifact {
  { root: projection_preview_node_from_markdown_ir(document) }
}
