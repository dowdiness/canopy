// ViewNode: Serializable view tree for the editor protocol.
// Flattens ProjNode[T] + SourceMap into a language-agnostic representation
// suitable for JSON transport to the UI layer.

///|
/// A coloured / labelled slice of a node's text. `role` is a CSS-class-style
/// tag (e.g. "keyword", "string", "identifier") and `start`/`end` are
/// half-open UTF-16 document code-unit offsets in the same coordinate space as
/// `ViewNode.text_range`.
pub(all) struct TokenSpan {
  role : String
  start : Int
  end : Int
} derive(Debug, Eq)

///|
pub fn TokenSpan::TokenSpan(
  role~ : String,
  start~ : Int,
  end~ : Int,
) -> TokenSpan {
  { role, start, end }
}

///|
pub(all) struct ViewAnnotation {
  kind : String
  label : String
  severity : String
} derive(Debug, Eq)

///|
pub fn ViewAnnotation::ViewAnnotation(
  kind~ : String,
  label~ : String,
  severity? : String = "info",
) -> ViewAnnotation {
  { kind, label, severity }
}

///|
pub impl ToJson for ViewAnnotation with fn to_json(self) {
  let m : Map[String, Json] = Map([])
  m["kind"] = self.kind.to_json()
  m["label"] = self.label.to_json()
  m["severity"] = self.severity.to_json()
  Json::object(m)
}

///|
/// Language-agnostic view of one projection node, JSON-serialised for the
/// frontend.
///
/// `ViewNode` flattens a `core.ProjNode[T]` plus its slice of the source map
/// into a uniform representation:
///
/// - `id` is the stable `NodeId` used to address the node in patches and
///   intents; it survives reparses.
/// - `kind_tag` is the AST variant name (lowercase, used by the frontend as a
///   discriminator).
/// - `label` is the short human-readable name shown in tree views.
/// - `text` is the rendered source for this subtree, when applicable.
/// - `text_range` is the half-open `[start, end)` range in the source
///   document the node occupies, expressed as UTF-16 document code-unit
///   offsets; consistent with `TokenSpan` offsets.
pub(all) struct ViewNode {
  id : @core.NodeId
  kind_tag : String
  label : String
  text : String?
  text_range : (Int, Int)
  token_spans : Array[TokenSpan]
  editable : Bool
  css_class : String
  children : Array[ViewNode]
  annotations : Array[ViewAnnotation]
} derive(Debug, Eq)

///|
pub fn ViewNode::ViewNode(
  id~ : @core.NodeId,
  kind_tag~ : String,
  label~ : String,
  text? : String,
  text_range~ : (Int, Int),
  token_spans? : Array[TokenSpan] = [],
  editable? : Bool = false,
  css_class? : String = "",
  children? : Array[ViewNode] = [],
  annotations? : Array[ViewAnnotation] = [],
) -> ViewNode {
  {
    id,
    kind_tag,
    label,
    text,
    text_range,
    token_spans,
    editable,
    css_class,
    children,
    annotations,
  }
}

///|
pub impl ToJson for TokenSpan with fn to_json(self) {
  let m : Map[String, Json] = Map([])
  m["role"] = self.role.to_json()
  m["start"] = self.start.to_json()
  m["end"] = self.end.to_json()
  Json::object(m)
}

///|
pub impl ToJson for ViewNode with fn to_json(self) {
  let m : Map[String, Json] = Map([])
  let NodeId(id_int) = self.id
  m["id"] = id_int.to_json()
  m["kind_tag"] = self.kind_tag.to_json()
  m["label"] = self.label.to_json()
  m["text"] = match self.text {
    Some(t) => t.to_json()
    None => Json::null()
  }
  let (range_start, range_end) = self.text_range
  m["text_range"] = Json::array([range_start.to_json(), range_end.to_json()])
  m["token_spans"] = Json::array(self.token_spans.map(fn(ts) { ts.to_json() }))
  m["editable"] = self.editable.to_json()
  m["css_class"] = self.css_class.to_json()
  m["children"] = Json::array(self.children.map(fn(c) { c.to_json() }))
  m["annotations"] = Json::array(self.annotations.map(fn(a) { a.to_json() }))
  Json::object(m)
}
