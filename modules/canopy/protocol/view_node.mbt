// ViewNode: Serializable view tree for the editor protocol.
// Flattens ProjNode[T] + SourceMap into a language-agnostic representation
// suitable for JSON transport to the UI layer.

///|
/// A coloured / labelled slice of a node's text. `role` is a CSS-class-style
/// tag (e.g. "keyword", "string", "identifier") and `start`/`end` are
/// half-open UTF-16 document code-unit offsets in the same coordinate space as
/// `ViewNode.text_range`.
#derive(Debug, Eq)
pub(all) struct TokenSpan {
  role : String
  start : Int32
  end : Int32
}

///|
pub fn TokenSpan::TokenSpan(
  role~ : String,
  start~ : Int32,
  end~ : Int32,
) -> TokenSpan {
  { role, start, end, }
}

///|
#derive(Debug, Eq)
pub(all) struct ViewAnnotation {
  kind : String
  label : String
  severity : String
}

///|
pub fn ViewAnnotation::ViewAnnotation(
  kind~ : String,
  label~ : String,
  severity~ : String = "info",
) -> ViewAnnotation {
  { kind, label, severity, }
}

///|
pub impl ToJson for ViewAnnotation with fn to_json(self) {
  let m : Map[String, Json] = Map([])
  m["kind"] = Json(self.kind)
  m["label"] = Json(self.label)
  m["severity"] = Json(self.severity)
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
#derive(Debug, Eq)
pub(all) struct ViewNode {
  id : @core.NodeId
  kind_tag : String
  label : String
  text : String?
  text_range : (Int32, Int32)
  token_spans : Array[TokenSpan]
  editable : Bool
  css_class : String
  children : Array[ViewNode]
  annotations : Array[ViewAnnotation]
}

///|
pub fn ViewNode::ViewNode(
  id~ : @core.NodeId,
  kind_tag~ : String,
  label~ : String,
  text? : String,
  text_range~ : (Int32, Int32),
  token_spans~ : Array[TokenSpan] = [],
  editable~ : Bool = false,
  css_class~ : String = "",
  children~ : Array[ViewNode] = [],
  annotations~ : Array[ViewAnnotation] = [],
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
  m["role"] = Json(self.role)
  m["start"] = Json(self.start)
  m["end"] = Json(self.end)
  Json::object(m)
}

///|
pub impl ToJson for ViewNode with fn to_json(self) {
  let m : Map[String, Json] = Map([])
  let NodeId(id_int) = self.id
  m["id"] = Json(id_int)
  m["kind_tag"] = Json(self.kind_tag)
  m["label"] = Json(self.label)
  m["text"] = match self.text {
    Some(t) => Json(t)
    None => Json::null()
  }
  let (range_start, range_end) = self.text_range
  m["text_range"] = Json::array([Json(range_start), Json(range_end)])
  m["token_spans"] = Json::array(
    self.token_spans.map(fn(ts) { ToJson::to_json(ts) }),
  )
  m["editable"] = Json(self.editable)
  m["css_class"] = Json(self.css_class)
  m["children"] = Json::array(self.children.map(fn(c) { ToJson::to_json(c) }))
  m["annotations"] = Json::array(
    self.annotations.map(fn(a) { ToJson::to_json(a) }),
  )
  Json::object(m)
}

///|
pub extend TokenSpan with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TokenSpan with Eq::{equal, not_equal}

///|
pub extend TokenSpan with ToJson::{to_json}

///|
pub extend ViewAnnotation with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ViewAnnotation with Eq::{equal, not_equal}

///|
pub extend ViewAnnotation with ToJson::{to_json}

///|
pub extend ViewNode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ViewNode with Eq::{equal, not_equal}

///|
pub extend ViewNode with ToJson::{to_json}
