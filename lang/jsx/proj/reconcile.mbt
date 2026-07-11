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
///| - Release(node_id)
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

fn in_set(id : Int, ids : Array[Int]) -> Bool {
  for i in ids { if i == id { return true } }
  false
}

fn walk(
  node : @core.ProjNode[@jsx.JsxNode],
  parent_id : Int,
  idx : Int,
  existing : Array[Int],
  patches : Array[DomPatch],
  reached : Array[Int],
) -> Unit {
  let id = node.node_id
  reached.push(id)
  let is_new = !in_set(id, existing)
  match node.kind {
    @jsx.JsxNode::Text(s) => {
      if is_new {
        patches.push(DomPatch::MakeText(parent_id, id, s, idx))
      } else {
        patches.push(DomPatch::SetText(id, s))
      }
    }
    @jsx.JsxNode::ExprSpan(raw~) => {
      if is_new {
        patches.push(DomPatch::MakeExprSpan(parent_id, id, raw, idx))
      } else {
        patches.push(DomPatch::SetExpr(id, raw))
      }
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
    @jsx.JsxNode::Root(..) | @jsx.JsxNode::Fragment(..) => {
      for i in 0..<node.children.length() {
        walk(node.children[i], id, i, existing, patches, reached)
      }
    }
    @jsx.JsxNode::Error(_) => ()
  }
}

///|
/// Serialize DomPatch[] to JSON string for the JS-side apply_patches.
pub fn dom_patches_to_json(patches : Array[DomPatch]) -> String {
  let parts : Array[String] = []
  for p in patches {
    parts.push(patch_to_json(p))
  }
  "[" + parts.join(",") + "]"
}

fn patch_to_json(p : DomPatch) -> String {
  match p {
    DomPatch::MakeElement(parent_id, node_id, tag, attrs, idx) => {
      let attrs_json = jsx_attrs_to_json(attrs)
      "{\"$tag\":\"MakeElement\",\"_0\":[" + parent_id.to_string() + "," + node_id.to_string() + ",\"" + escape_json(tag) + "\"," + attrs_json + "," + idx.to_string() + "]}"
    }
    DomPatch::MakeText(parent_id, node_id, text, idx) =>
      "{\"$tag\":\"MakeText\",\"_0\":[" + parent_id.to_string() + "," + node_id.to_string() + ",\"" + escape_json(text) + "\"," + idx.to_string() + "]}"
    DomPatch::MakeExprSpan(parent_id, node_id, raw, idx) =>
      "{\"$tag\":\"MakeExprSpan\",\"_0\":[" + parent_id.to_string() + "," + node_id.to_string() + ",\"" + escape_json(raw) + "\"," + idx.to_string() + "]}"
    DomPatch::SetText(node_id, text) =>
      "{\"$tag\":\"SetText\",\"_0\":[" + node_id.to_string() + ",\"" + escape_json(text) + "\"]}"
    DomPatch::SetExpr(node_id, raw) =>
      "{\"$tag\":\"SetExpr\",\"_0\":[" + node_id.to_string() + ",\"" + escape_json(raw) + "\"]}"
    DomPatch::SetAttrs(node_id, attrs) => {
      let attrs_json = jsx_attrs_to_json(attrs)
      "{\"$tag\":\"SetAttrs\",\"_0\":[" + node_id.to_string() + "," + attrs_json + "]}"
    }
    DomPatch::Release(node_id) =>
      "{\"$tag\":\"Release\",\"_0\":[" + node_id.to_string() + "]}"
  }
}

fn jsx_attrs_to_json(attrs : Array[@jsx.JsxAttr]) -> String {
  let parts : Array[String] = []
  for a in attrs {
    let val_json = jsx_attr_value_to_json(a.value)
    parts.push("{\"name\":\"" + escape_json(a.name) + "\",\"value\":" + val_json + "}")
  }
  "[" + parts.join(",") + "]"
}

fn jsx_attr_value_to_json(value : @jsx.JsxAttrValue) -> String {
  match value {
    @jsx.JsxAttrValue::StringLit(s) => "\"" + escape_json(s) + "\""
    @jsx.JsxAttrValue::ExprSpan(raw~) => "{\"type\":\"expr-span\",\"raw\":\"" + escape_json(raw) + "\"}"
    @jsx.JsxAttrValue::Bare => "{\"type\":\"bare\"}"
  }
}
fn escape_json(s : String) -> String {
  s
    .replace(old="\\", new="\\\\")
    .replace(old="\"", new="\\\"")
    .replace(old="\n", new="\\n")
    .replace(old="\t", new="\\t")
}
