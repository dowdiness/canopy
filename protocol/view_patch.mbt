// ViewPatch: Incremental patches for the editor protocol.

///|
/// Visual decoration applied to a half-open text range `[from, to)` in the
/// editor's source view.
///
/// `css_class` is the CSS class the frontend should attach to the range;
/// `widget` indicates that the decoration replaces the range with an inline
/// widget rather than overlaying its character cells. `data` is an opaque
/// string the frontend may use to discriminate between decorations of the
/// same class (e.g. a kind tag for a hover popover).
pub(all) struct Decoration {
  from : Int
  to : Int
  css_class : String
  data : String?
  widget : Bool
} derive(Debug, Eq)

///|
pub fn Decoration::Decoration(
  from~ : Int,
  to~ : Int,
  css_class~ : String,
  data? : String,
  widget? : Bool = false,
) -> Decoration {
  { from, to, css_class, data, widget }
}

///|
/// Severity level for a `Diagnostic`. Serialised as the lowercase strings
/// `"error" | "warning" | "info" | "hint"` for frontend consumers.
pub(all) enum Severity {
  SevError
  SevWarning
  SevInfo
  SevHint
} derive(Debug, Eq)

///|
pub impl ToJson for Severity with to_json(self) {
  match self {
    SevError => "error".to_json()
    SevWarning => "warning".to_json()
    SevInfo => "info".to_json()
    SevHint => "hint".to_json()
  }
}

///|
/// A diagnostic message associated with a half-open text range `[from, to)`.
/// Used to surface compiler/linter findings to the editor frontend.
pub(all) struct Diagnostic {
  from : Int
  to : Int
  severity : Severity
  message : String
} derive(Debug, Eq)

///|
pub fn Diagnostic::Diagnostic(
  from~ : Int,
  to~ : Int,
  severity~ : Severity,
  message~ : String,
) -> Diagnostic {
  { from, to, severity, message }
}

///|
/// Incremental patches emitted by the editor and applied by the frontend.
///
/// A patch describes one change to the editor's view. Patches are JSON
/// serialisable; the canonical mapping is defined by `ToJson for ViewPatch`
/// below and consumed by `adapters/editor-adapter` on the TypeScript side.
/// Frontends must treat unknown variants as no-ops so the protocol can be
/// extended without a breaking change.
pub(all) enum ViewPatch {
  TextChange(from~ : Int, to~ : Int, insert~ : String)
  ReplaceNode(node_id~ : @core.NodeId, node~ : ViewNode)
  InsertChild(parent_id~ : @core.NodeId, index~ : Int, child~ : ViewNode)
  RemoveChild(parent_id~ : @core.NodeId, index~ : Int, child_id~ : @core.NodeId)
  UpdateNode(
    node_id~ : @core.NodeId,
    label~ : String,
    css_class~ : String,
    text~ : String?
  )
  SetDecorations(decorations~ : Array[Decoration])
  SetDiagnostics(diagnostics~ : Array[Diagnostic])
  SetSelection(anchor~ : Int, head~ : Int)
  SelectNode(node_id~ : @core.NodeId)
  FullTree(root~ : ViewNode?)
} derive(Debug, Eq)

///|
pub impl ToJson for Decoration with to_json(self) {
  let m : Map[String, Json] = {}
  m["from"] = self.from.to_json()
  m["to"] = self.to.to_json()
  m["css_class"] = self.css_class.to_json()
  m["data"] = match self.data {
    Some(d) => d.to_json()
    None => Json::null()
  }
  m["widget"] = self.widget.to_json()
  Json::object(m)
}

///|
pub impl ToJson for Diagnostic with to_json(self) {
  let m : Map[String, Json] = {}
  m["from"] = self.from.to_json()
  m["to"] = self.to.to_json()
  m["severity"] = self.severity.to_json()
  m["message"] = self.message.to_json()
  Json::object(m)
}

///|
pub impl ToJson for ViewPatch with to_json(self) {
  let m : Map[String, Json] = {}
  match self {
    TextChange(from~, to~, insert~) => {
      m["type"] = "TextChange".to_json()
      m["from"] = from.to_json()
      m["to"] = to.to_json()
      m["insert"] = insert.to_json()
    }
    ReplaceNode(node_id~, node~) => {
      m["type"] = "ReplaceNode".to_json()
      m["node_id"] = node_id.to_json()
      m["node"] = node.to_json()
    }
    InsertChild(parent_id~, index~, child~) => {
      m["type"] = "InsertChild".to_json()
      m["parent_id"] = parent_id.to_json()
      m["index"] = index.to_json()
      m["child"] = child.to_json()
    }
    RemoveChild(parent_id~, index~, child_id~) => {
      m["type"] = "RemoveChild".to_json()
      m["parent_id"] = parent_id.to_json()
      m["index"] = index.to_json()
      m["child_id"] = child_id.to_json()
    }
    UpdateNode(node_id~, label~, css_class~, text~) => {
      m["type"] = "UpdateNode".to_json()
      m["node_id"] = node_id.to_json()
      m["label"] = label.to_json()
      m["css_class"] = css_class.to_json()
      m["text"] = match text {
        Some(t) => t.to_json()
        None => Json::null()
      }
    }
    SetDecorations(decorations~) => {
      m["type"] = "SetDecorations".to_json()
      m["decorations"] = Json::array(decorations.map(fn(d) { d.to_json() }))
    }
    SetDiagnostics(diagnostics~) => {
      m["type"] = "SetDiagnostics".to_json()
      m["diagnostics"] = Json::array(diagnostics.map(fn(d) { d.to_json() }))
    }
    SetSelection(anchor~, head~) => {
      m["type"] = "SetSelection".to_json()
      m["anchor"] = anchor.to_json()
      m["head"] = head.to_json()
    }
    SelectNode(node_id~) => {
      m["type"] = "SelectNode".to_json()
      m["node_id"] = node_id.to_json()
    }
    FullTree(root~) => {
      m["type"] = "FullTree".to_json()
      m["root"] = match root {
        Some(r) => r.to_json()
        None => Json::null()
      }
    }
  }
  Json::object(m)
}
