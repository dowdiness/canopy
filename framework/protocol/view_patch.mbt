// ViewPatch: Incremental patches for the editor protocol.
// Emitted by ViewUpdater to describe what changed between two ViewNode trees.

///|
pub(all) struct Decoration {
  from : Int
  to : Int
  css_class : String
  data : String?
  widget : Bool

  fn new(
    from~ : Int,
    to~ : Int,
    css_class~ : String,
    data? : String,
    widget? : Bool,
  ) -> Decoration
} derive(Show, Eq)

///|
pub fn Decoration::new(
  from~ : Int,
  to~ : Int,
  css_class~ : String,
  data? : String,
  widget? : Bool = false,
) -> Decoration {
  { from, to, css_class, data, widget }
}

///|
pub(all) struct Diagnostic {
  from : Int
  to : Int
  severity : String
  message : String

  fn new(
    from~ : Int,
    to~ : Int,
    severity~ : String,
    message~ : String,
  ) -> Diagnostic
} derive(Show, Eq)

///|
pub fn Diagnostic::new(
  from~ : Int,
  to~ : Int,
  severity~ : String,
  message~ : String,
) -> Diagnostic {
  { from, to, severity, message }
}

///|
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
} derive(Show, Eq)

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
fn node_id_to_json(id : @core.NodeId) -> Json {
  let NodeId(n) = id
  n.to_json()
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
      m["node_id"] = node_id_to_json(node_id)
      m["node"] = node.to_json()
    }
    InsertChild(parent_id~, index~, child~) => {
      m["type"] = "InsertChild".to_json()
      m["parent_id"] = node_id_to_json(parent_id)
      m["index"] = index.to_json()
      m["child"] = child.to_json()
    }
    RemoveChild(parent_id~, index~, child_id~) => {
      m["type"] = "RemoveChild".to_json()
      m["parent_id"] = node_id_to_json(parent_id)
      m["index"] = index.to_json()
      m["child_id"] = node_id_to_json(child_id)
    }
    UpdateNode(node_id~, label~, css_class~, text~) => {
      m["type"] = "UpdateNode".to_json()
      m["node_id"] = node_id_to_json(node_id)
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
      m["node_id"] = node_id_to_json(node_id)
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
