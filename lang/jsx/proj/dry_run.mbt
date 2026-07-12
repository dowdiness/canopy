///|
/// Pure fake DOM model for validating the existing DomPatch contract.
///
/// This model deliberately has no DOM or JavaScript dependency. It applies
/// the same patches that the imperative adapter applies, including releasing
/// nodes before evaluating insertion indexes. The model is session-owned by
/// the JSX adapter and is only advanced after a real DOM apply succeeds.
pub struct DryRunModel {
  priv children : Array[DryRunNode]
} derive(Debug, Eq)

///|
pub enum DryRunNode {
  Element(Int, String, Array[@jsx.JsxAttr], Array[DryRunNode])
  Text(Int, String)
  ExprSpan(Int, String)
} derive(Debug, Eq)

///|
pub fn DryRunModel::empty() -> DryRunModel {
  { children: [] }
}

///|
/// Normalize a string attribute exactly as the V1 DOM shell does.
pub fn normalize_dom_attribute_value(name : String, value : String) -> String {
  if name.has_prefix("data-genui-") {
    value
    .replace_all(old="&quot;", new="\"")
    .replace_all(old="&gt;", new=">")
    .replace_all(old="&lt;", new="<")
    .replace_all(old="&amp;", new="&")
  } else {
    value
  }
}

///|
/// Keep the dry-run attribute state aligned with the V1 DOM shell: string
/// values are materialized as-is, bare attributes become empty strings, and
/// opaque expression values are omitted because V1 does not evaluate them.
/// Duplicate names use the last applicable value, matching setAttribute.
fn dom_attrs(attrs : Array[@jsx.JsxAttr]) -> Array[@jsx.JsxAttr] {
  attrs.fold(init=[], fn(result, attr) {
    match normalize_dom_attr(attr) {
      None => result
      Some(normalized) =>
        match result.search_by(existing => existing.name == normalized.name) {
          Some(index) => {
            result[index] = normalized
            result
          }
          None => {
            result.push(normalized)
            result
          }
        }
    }
  })
}

///|
fn normalize_dom_attr(attr : @jsx.JsxAttr) -> @jsx.JsxAttr? {
  if attr.name == "data-node-id" {
    return None
  }
  match attr.value {
    @jsx.JsxAttrValue::StringLit(value) =>
      Some(
        @jsx.JsxAttr::JsxAttr(
          name=attr.name,
          value=@jsx.JsxAttrValue::StringLit(
            normalize_dom_attribute_value(attr.name, value),
          ),
        ),
      )
    @jsx.JsxAttrValue::Bare =>
      Some(
        @jsx.JsxAttr::JsxAttr(
          name=attr.name,
          value=@jsx.JsxAttrValue::StringLit(""),
        ),
      )
    @jsx.JsxAttrValue::ExprSpan(_) => None
  }
}

///|
/// Apply an existing DomPatch sequence without mutating the input model.
/// Release patches are processed first, matching `apply_patches_unchecked`.
pub fn DryRunModel::apply(
  self : DryRunModel,
  patches : Array[DomPatch],
) -> Result[DryRunModel, String] {
  let result = self.copy()
  for patch in patches {
    match patch {
      DomPatch::Release(node_id) =>
        ignore(remove_node(result.children, node_id))
      _ => ()
    }
  }
  for patch in patches {
    match patch {
      DomPatch::MakeElement(parent_id, node_id, tag, attrs, index) => {
        if contains_node(result.children, node_id) {
          return Err("duplicate node: " + node_id.to_string())
        }
        match
          insert_node(
            result.children,
            parent_id,
            DryRunNode::Element(node_id, tag, dom_attrs(attrs), []),
            index,
          ) {
          Ok(_) => ()
          Err(message) => return Err(message)
        }
      }
      DomPatch::MakeText(parent_id, node_id, value, index) => {
        if contains_node(result.children, node_id) {
          return Err("duplicate node: " + node_id.to_string())
        }
        match
          insert_node(
            result.children,
            parent_id,
            DryRunNode::Text(node_id, value),
            index,
          ) {
          Ok(_) => ()
          Err(message) => return Err(message)
        }
      }
      DomPatch::MakeExprSpan(parent_id, node_id, raw, index) => {
        if contains_node(result.children, node_id) {
          return Err("duplicate node: " + node_id.to_string())
        }
        match
          insert_node(
            result.children,
            parent_id,
            DryRunNode::ExprSpan(node_id, raw),
            index,
          ) {
          Ok(_) => ()
          Err(message) => return Err(message)
        }
      }
      DomPatch::SetText(node_id, value) =>
        if !update_node(result.children, node_id, DryRunUpdate::Text(value)) {
          return Err("missing text node: " + node_id.to_string())
        }
      DomPatch::SetExpr(node_id, raw) =>
        if !update_node(result.children, node_id, DryRunUpdate::ExprSpan(raw)) {
          return Err("missing expression node: " + node_id.to_string())
        }
      DomPatch::SetAttrs(node_id, attrs) =>
        if !update_node(
            result.children,
            node_id,
            DryRunUpdate::Attrs(dom_attrs(attrs)),
          ) {
          return Err("missing element node: " + node_id.to_string())
        }
      DomPatch::Release(_) => ()
    }
  }
  Ok(result)
}

///|
fn DryRunModel::copy(self : DryRunModel) -> DryRunModel {
  { children: self.children.map(copy_node) }
}

///|
priv enum DryRunUpdate {
  Text(String)
  ExprSpan(String)
  Attrs(Array[@jsx.JsxAttr])
}

///|
fn copy_node(node : DryRunNode) -> DryRunNode {
  match node {
    Element(node_id, tag, attrs, children) =>
      Element(node_id, tag, attrs.copy(), children.map(copy_node))
    Text(node_id, value) => Text(node_id, value)
    ExprSpan(node_id, raw) => ExprSpan(node_id, raw)
  }
}

///|
fn contains_node(children : Array[DryRunNode], node_id : Int) -> Bool {
  for child in children {
    match child {
      Element(id, _, _, nested) =>
        if id == node_id || contains_node(nested, node_id) {
          return true
        }
      Text(id, _) | ExprSpan(id, _) => if id == node_id { return true }
    }
  }
  false
}

///|
fn remove_node(children : Array[DryRunNode], node_id : Int) -> Bool {
  for index in 0..<children.length() {
    match children[index] {
      Element(id, _, _, nested) => {
        if id == node_id {
          ignore(children.remove(index))
          return true
        }
        if remove_node(nested, node_id) {
          return true
        }
      }
      Text(id, _) | ExprSpan(id, _) =>
        if id == node_id {
          ignore(children.remove(index))
          return true
        }
    }
  }
  false
}

///|
fn insert_node(
  children : Array[DryRunNode],
  parent_id : Int,
  node : DryRunNode,
  index : Int,
) -> Result[Unit, String] {
  if parent_id == -1 {
    return insert_at(children, node, index)
  }
  for child in children {
    match child {
      Element(node_id, _, _, nested) => {
        if node_id == parent_id {
          return insert_at(nested, node, index)
        }
        match insert_node(nested, parent_id, node, index) {
          Ok(_) => return Ok(())
          Err(_) => ()
        }
      }
      Text(_, _) | ExprSpan(_, _) => ()
    }
  }
  Err("missing parent node: " + parent_id.to_string())
}

///|
fn insert_at(
  children : Array[DryRunNode],
  node : DryRunNode,
  index : Int,
) -> Result[Unit, String] {
  if index < 0 {
    return Err("negative sibling index: " + index.to_string())
  }
  let position = index.min(children.length())
  children.insert(position, node)
  Ok(())
}

///|
fn update_node(
  children : Array[DryRunNode],
  node_id : Int,
  update : DryRunUpdate,
) -> Bool {
  for index in 0..<children.length() {
    match children[index] {
      Element(id, tag, _, nested) => {
        if id == node_id {
          match update {
            DryRunUpdate::Attrs(new_attrs) =>
              children[index] = DryRunNode::Element(
                id,
                tag,
                new_attrs.copy(),
                nested,
              )
            DryRunUpdate::Text(_) | DryRunUpdate::ExprSpan(_) => return false
          }
          return true
        }
        if update_node(nested, node_id, update) {
          return true
        }
      }
      Text(id, _) =>
        if id == node_id {
          match update {
            DryRunUpdate::Text(value) =>
              children[index] = DryRunNode::Text(id, value)
            DryRunUpdate::ExprSpan(_) | DryRunUpdate::Attrs(_) => return false
          }
          return true
        }
      ExprSpan(id, _) =>
        if id == node_id {
          match update {
            DryRunUpdate::ExprSpan(raw) =>
              children[index] = DryRunNode::ExprSpan(id, raw)
            DryRunUpdate::Text(_) | DryRunUpdate::Attrs(_) => return false
          }
          return true
        }
    }
  }
  false
}
