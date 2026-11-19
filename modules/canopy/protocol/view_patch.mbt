// ViewPatch: Incremental patches for the editor protocol.

///|
/// Visual decoration applied to a half-open UTF-16 document code-unit range
/// `[from, to)` in the editor's source view.
///
/// `css_class` is the CSS class the frontend should attach to the range;
/// `widget` indicates that the decoration replaces the range with an inline
/// widget rather than overlaying its character cells. `data` is an opaque
/// string the frontend may use to discriminate between decorations of the
/// same class (e.g. a kind tag for a hover popover).
#derive(Debug, Eq)
pub(all) struct Decoration {
  from : Int32
  to : Int32
  css_class : String
  data : String?
  widget : Bool
}

///|
pub fn Decoration::Decoration(
  from~ : Int32,
  to~ : Int32,
  css_class~ : String,
  data? : String,
  widget~ : Bool = false,
) -> Decoration {
  { from, to, css_class, data, widget, }
}

///|
/// Severity level for a `Diagnostic`. Serialised as the lowercase strings
/// `"error" | "warning" | "info" | "hint"` for frontend consumers.
#derive(Debug, Eq)
pub(all) enum Severity {
  SevError
  SevWarning
  SevInfo
  SevHint
}

///|
pub impl ToJson for Severity with fn to_json(self) {
  match self {
    SevError => Json("error")
    SevWarning => Json("warning")
    SevInfo => Json("info")
    SevHint => Json("hint")
  }
}

///|
/// Producer-neutral metadata for one registered diagnostic fix. The opaque
/// integer `id` is meaningful only with its diagnostic and snapshot IDs.
#derive(Debug, Eq)
pub(all) struct DiagnosticFixSummary {
  id : Int32
  title : String
  applicability : String
}

///|
pub fn DiagnosticFixSummary::DiagnosticFixSummary(
  id~ : Int32,
  title~ : String,
  applicability~ : String,
) -> DiagnosticFixSummary {
  { id, title, applicability, }
}

///|
/// A diagnostic message associated with a half-open UTF-16 document code-unit
/// range `[from, to)`. Used to surface compiler/linter findings to the editor
/// frontend.
#derive(Debug, Eq)
pub(all) struct Diagnostic {
  from : Int32
  to : Int32
  severity : Severity
  message : String
  code : String?
  snapshot_id : Int32?
  diagnostic_id : Int32?
  fixes : Array[DiagnosticFixSummary]
}

///|
pub fn Diagnostic::Diagnostic(
  from~ : Int32,
  to~ : Int32,
  severity~ : Severity,
  message~ : String,
  code? : String,
  snapshot_id? : Int32,
  diagnostic_id? : Int32,
  fixes~ : Array[DiagnosticFixSummary] = [],
) -> Diagnostic {
  {
    from,
    to,
    severity,
    message,
    code,
    snapshot_id,
    diagnostic_id,
    fixes: fixes.copy(),
  }
}

///|
/// Incremental patches emitted by the editor and applied by the frontend.
///
/// A patch describes one change to the editor's view. Patches are JSON
/// serialisable; the canonical mapping is defined by `ToJson for ViewPatch`
/// below and consumed by `adapters/editor` on the TypeScript side.
/// Frontends must treat unknown variants as no-ops so the protocol can be
/// extended without a breaking change.
#derive(Debug, Eq)
pub(all) enum ViewPatch {
  /// `from`/`to` are UTF-16 document code-unit offsets.
  TextChange(from~ : Int32, to~ : Int32, insert~ : String)
  ReplaceNode(node_id~ : @core.NodeId, node~ : ViewNode)
  InsertChild(parent_id~ : @core.NodeId, index~ : Int32, child~ : ViewNode)
  RemoveChild(
    parent_id~ : @core.NodeId,
    index~ : Int32,
    child_id~ : @core.NodeId,
  )
  UpdateNode(
    node_id~ : @core.NodeId,
    label~ : String,
    css_class~ : String,
    text~ : String?,
  )
  SetDecorations(decorations~ : Array[Decoration])
  SetDiagnostics(diagnostics~ : Array[Diagnostic])
  /// `anchor`/`head` are UTF-16 document code-unit offsets.
  SetSelection(anchor~ : Int32, head~ : Int32)
  SelectNode(node_id~ : @core.NodeId)
  FullTree(root~ : ViewNode?)
}

///|
pub impl ToJson for Decoration with fn to_json(self) {
  let m : Map[String, Json] = Map([])
  m["from"] = Json(self.from)
  m["to"] = Json(self.to)
  m["css_class"] = Json(self.css_class)
  m["data"] = match self.data {
    Some(d) => Json(d)
    None => Json::null()
  }
  m["widget"] = Json(self.widget)
  Json::object(m)
}

///|
pub impl ToJson for Diagnostic with fn to_json(self) {
  let m : Map[String, Json] = Map([])
  m["from"] = Json(self.from)
  m["to"] = Json(self.to)
  m["severity"] = ToJson::to_json(self.severity)
  m["message"] = Json(self.message)
  m["code"] = match self.code {
    Some(code) => Json(code)
    None => Json::null()
  }
  m["snapshot_id"] = match self.snapshot_id {
    Some(id) => Json(id)
    None => Json::null()
  }
  m["diagnostic_id"] = match self.diagnostic_id {
    Some(id) => Json(id)
    None => Json::null()
  }
  m["fixes"] = Json::array(self.fixes.map(fix => ToJson::to_json(fix)))
  Json::object(m)
}

///|
pub impl ToJson for DiagnosticFixSummary with fn to_json(self) {
  let m : Map[String, Json] = Map([])
  m["id"] = Json(self.id)
  m["title"] = Json(self.title)
  m["applicability"] = Json(self.applicability)
  Json::object(m)
}

///|
pub impl ToJson for ViewPatch with fn to_json(self) {
  let m : Map[String, Json] = Map([])
  match self {
    TextChange(from~, to~, insert~) => {
      m["type"] = Json("TextChange")
      m["from"] = Json(from)
      m["to"] = Json(to)
      m["insert"] = Json(insert)
    }
    ReplaceNode(node_id~, node~) => {
      m["type"] = Json("ReplaceNode")
      m["node_id"] = node_id.to_json()
      m["node"] = ToJson::to_json(node)
    }
    InsertChild(parent_id~, index~, child~) => {
      m["type"] = Json("InsertChild")
      m["parent_id"] = parent_id.to_json()
      m["index"] = Json(index)
      m["child"] = ToJson::to_json(child)
    }
    RemoveChild(parent_id~, index~, child_id~) => {
      m["type"] = Json("RemoveChild")
      m["parent_id"] = parent_id.to_json()
      m["index"] = Json(index)
      m["child_id"] = child_id.to_json()
    }
    UpdateNode(node_id~, label~, css_class~, text~) => {
      m["type"] = Json("UpdateNode")
      m["node_id"] = node_id.to_json()
      m["label"] = Json(label)
      m["css_class"] = Json(css_class)
      m["text"] = match text {
        Some(t) => Json(t)
        None => Json::null()
      }
    }
    SetDecorations(decorations~) => {
      m["type"] = Json("SetDecorations")
      m["decorations"] = Json::array(
        decorations.map(fn(d) { ToJson::to_json(d) }),
      )
    }
    SetDiagnostics(diagnostics~) => {
      m["type"] = Json("SetDiagnostics")
      m["diagnostics"] = Json::array(
        diagnostics.map(fn(d) { ToJson::to_json(d) }),
      )
    }
    SetSelection(anchor~, head~) => {
      m["type"] = Json("SetSelection")
      m["anchor"] = Json(anchor)
      m["head"] = Json(head)
    }
    SelectNode(node_id~) => {
      m["type"] = Json("SelectNode")
      m["node_id"] = node_id.to_json()
    }
    FullTree(root~) => {
      m["type"] = Json("FullTree")
      m["root"] = match root {
        Some(r) => ToJson::to_json(r)
        None => Json::null()
      }
    }
  }
  Json::object(m)
}

///|
pub extend Decoration with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Decoration with Eq::{equal, not_equal}

///|
pub extend Decoration with ToJson::{to_json}

///|
pub extend Diagnostic with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Diagnostic with ToJson::{to_json}

///|
pub extend DiagnosticFixSummary with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DiagnosticFixSummary with Eq::{equal, not_equal}

///|
pub extend DiagnosticFixSummary with ToJson::{to_json}

///|
pub extend Severity with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Severity with Eq::{equal, not_equal}

///|
pub extend Severity with ToJson::{to_json}

///|
pub extend ViewPatch with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ViewPatch with Eq::{equal, not_equal}

///|
pub extend ViewPatch with ToJson::{to_json}
