///| A patch describing a single DOM operation for incremental reconciliation.

///| Pure data — no DOM, no Any. Testable with `moon test`.

///|

///| Field order is documented; construct and destructure positionally:

///| - MakeElement(parent_id, node_id, tag, attrs, index)

///| - MakeText(parent_id, node_id, text, index)

///| - MakeExprSpan(parent_id, node_id, raw, index)

///| - SetText(node_id, text)

///| - SetExpr(node_id, raw)

///| - SetAttrs(node_id, attrs)

///|
/// - Release(node_id)
pub(all) enum DomPatch {
  MakeElement(Int, Int, String, Array[@jsx.JsxAttr], Int)
  MakeText(Int, Int, String, Int)
  MakeExprSpan(Int, Int, String, Int)
  SetText(Int, String)
  SetExpr(Int, String)
  SetAttrs(Int, Array[@jsx.JsxAttr])
  Release(Int)
} derive(Debug, Eq)

///|
/// Walk `root`, compare against previously-known NodeIds, produce patches.
/// Returns `(patches, updated_ids)` for the next reconcile call.
pub fn reconcile(
  root : @core.ProjNode[@jsx.JsxNode],
  existing : Array[Int],
) -> (Array[DomPatch], Array[Int]) {
  let patches : Array[DomPatch] = []
  let reached : Array[Int] = []
  walk(root, -1, 0, existing, patches, reached)
  for id in existing {
    if !in_set(id, reached) {
      patches.push(DomPatch::Release(id))
    }
  }
  (patches, reached)
}

///|
fn in_set(id : Int, ids : Array[Int]) -> Bool {
  for i in ids {
    if i == id {
      return true
    }
  }
  false
}

///|
fn walk(
  node : @core.ProjNode[@jsx.JsxNode],
  parent_id : Int,
  idx : Int,
  existing : Array[Int],
  patches : Array[DomPatch],
  reached : Array[Int],
) -> Unit {
  match node.kind {
    @jsx.JsxNode::Element(tag="", ..) => {
      for i in 0..<node.children.length() {
        walk(node.children[i], parent_id, i, existing, patches, reached)
      }
      return
    }
    _ => ()
  }
  let id = node.node_id
  reached.push(id)
  let is_new = !in_set(id, existing)
  match node.kind {
    @jsx.JsxNode::Text(s) =>
      if is_new {
        patches.push(DomPatch::MakeText(parent_id, id, s, idx))
      } else {
        patches.push(DomPatch::SetText(id, s))
      }
    @jsx.JsxNode::ExprSpan(raw~) =>
      if is_new {
        patches.push(DomPatch::MakeExprSpan(parent_id, id, raw, idx))
      } else {
        patches.push(DomPatch::SetExpr(id, raw))
      }
    @jsx.JsxNode::Element(tag~, attrs~, ..) => {
      if is_new {
        patches.push(DomPatch::MakeElement(parent_id, id, tag, attrs, idx))
      } else {
        patches.push(DomPatch::SetAttrs(id, attrs))
      }
      for i in 0..<node.children.length() {
        walk(node.children[i], id, i, existing, patches, reached)
      }
    }
    @jsx.JsxNode::Root(..) | @jsx.JsxNode::Fragment(..) =>
      for i in 0..<node.children.length() {
        walk(node.children[i], parent_id, i, existing, patches, reached)
      }
    @jsx.JsxNode::Error(_) => ()
  }
}

///|
/// Serialize DomPatch[] to JSON using @json.Json.
pub fn dom_patches_to_json(patches : Array[DomPatch]) -> String {
  Json::array(patches.map(fn(p) { patch_to_json(p) })).stringify()
}

///|
fn patch_to_json(p : DomPatch) -> Json {
  let (tag, args) = match p {
    DomPatch::MakeElement(pid, nid, tag, attrs, idx) =>
      (
        "MakeElement",
        [
          Json::number(pid.to_double()),
          Json::number(nid.to_double()),
          Json::string(tag),
          jsx_attrs_to_json(attrs),
          Json::number(idx.to_double()),
        ],
      )
    DomPatch::MakeText(pid, nid, text, idx) =>
      (
        "MakeText",
        [
          Json::number(pid.to_double()),
          Json::number(nid.to_double()),
          Json::string(text),
          Json::number(idx.to_double()),
        ],
      )
    DomPatch::MakeExprSpan(pid, nid, raw, idx) =>
      (
        "MakeExprSpan",
        [
          Json::number(pid.to_double()),
          Json::number(nid.to_double()),
          Json::string(raw),
          Json::number(idx.to_double()),
        ],
      )
    DomPatch::SetText(nid, text) =>
      ("SetText", [Json::number(nid.to_double()), Json::string(text)])
    DomPatch::SetExpr(nid, raw) =>
      ("SetExpr", [Json::number(nid.to_double()), Json::string(raw)])
    DomPatch::SetAttrs(nid, attrs) =>
      ("SetAttrs", [Json::number(nid.to_double()), jsx_attrs_to_json(attrs)])
    DomPatch::Release(nid) => ("Release", [Json::number(nid.to_double())])
  }
  Json::object({ "$tag": Json::string(tag), "_0": Json::array(args) })
}

///|
fn jsx_attrs_to_json(attrs : Array[@jsx.JsxAttr]) -> Json {
  Json::array(attrs.map(fn(a) { jsx_attr_to_json(a) }))
}

///|
fn jsx_attr_to_json(attr : @jsx.JsxAttr) -> Json {
  Json::object({
    "name": Json::string(attr.name),
    "value": jsx_attr_value_to_json(attr.value),
  })
}

///|
fn jsx_attr_value_to_json(value : @jsx.JsxAttrValue) -> Json {
  match value {
    @jsx.JsxAttrValue::StringLit(s) => Json::string(s)
    @jsx.JsxAttrValue::ExprSpan(raw~) =>
      Json::object({
        "type": Json::string("expr-span"),
        "raw": Json::string(raw),
      })
    @jsx.JsxAttrValue::Bare => Json::object({ "type": Json::string("bare") })
  }
}
