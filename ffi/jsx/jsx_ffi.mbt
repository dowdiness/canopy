// FFI surface for the JSX parser demo. Exports:
//   jsx_parse_to_json(text)           — single parse
//   jsx_streaming_to_json(prefixes)    — incremental re-parse across NUL-separated
//                                       prefixes; demonstrates NodeId stability
// Phase 3 (bidirectional editing, DOM mounting) remains deferred.

///|
fn jsx_attr_value_to_json(value : @jsx_ast.JsxAttrValue) -> Json {
  match value {
    @jsx_ast.JsxAttrValue::StringLit(s) => Json::string(s)
    @jsx_ast.JsxAttrValue::ExprSpan(raw~) =>
      Json::object({
        "type": Json::string("expr-span"),
        "raw": Json::string(raw),
      })
    @jsx_ast.JsxAttrValue::Bare =>
      Json::object({ "type": Json::string("bare") })
  }
}

///|
fn jsx_attr_to_json(attr : @jsx_ast.JsxAttr) -> Json {
  Json::object({
    "name": Json::string(attr.name),
    "value": jsx_attr_value_to_json(attr.value),
  })
}

///|
fn kind_to_json(kind : @jsx_ast.JsxNode) -> Json {
  match kind {
    @jsx_ast.JsxNode::Root(children~) =>
      Json::object({
        "tag": Json::string("Root"),
        "children_count": Json::number(children.length().to_double()),
      })
    @jsx_ast.JsxNode::Element(tag~, attrs~, children~) =>
      Json::object({
        "tag": Json::string(tag),
        "attrs": Json::array(attrs.map(jsx_attr_to_json)),
        "children_count": Json::number(children.length().to_double()),
      })
    @jsx_ast.JsxNode::Fragment(children~) =>
      Json::object({
        "tag": Json::string("Fragment"),
        "children_count": Json::number(children.length().to_double()),
      })
    @jsx_ast.JsxNode::Text(s) =>
      Json::object({ "tag": Json::string("Text"), "value": Json::string(s) })
    @jsx_ast.JsxNode::ExprSpan(raw~) =>
      Json::object({
        "tag": Json::string("ExprSpan"),
        "value": Json::string(raw),
      })
    @jsx_ast.JsxNode::Error(s) =>
      Json::object({ "tag": Json::string("Error"), "value": Json::string(s) })
  }
}

///|
fn proj_node_to_json(node : @canopy_core.ProjNode[@jsx_ast.JsxNode]) -> Json {
  let children : Array[Json] = node.children.map(proj_node_to_json)
  let kind_tag = node.kind.kind_tag()
  Json::object({
    "node_id": Json::number(node.node_id.to_double()),
    "kind_tag": Json::string(kind_tag),
    "kind": kind_to_json(node.kind),
    "children": Json::array(children),
  })
}

///|
/// Parse JSX text and return the ProjNode tree as JSON.
/// The JSON includes node_ids, kind tags, and structural info so the demo
/// page can highlight stable-vs-new NodeIds across streaming re-parses.
pub fn jsx_parse_to_json(text : String) -> String {
  let (proj, errors) = @jsx_proj.parse_to_proj_node(text) catch {
    _ =>
      return Json::object({
        "success": Json::boolean(false),
        "error": Json::string("LexError"),
      }).stringify()
  }
  Json::object({
    "success": Json::boolean(true),
    "root": proj_node_to_json(proj),
    "errors": Json::array(errors.map(Json::string)),
  }).stringify()
}

///|
/// Parse NUL-separated prefixes with ONE shared parser, returning a JSON array
/// of trees. This demonstrates the generative-UI value proposition: NodeIds of
/// already-complete elements stay stable as the input grows.
///
/// Input: a single string with prefixes separated by '\0' (NUL byte).
/// Output: a JSON array of step objects, each with `prefix_index`, `success`,
/// `root`, and `errors`.
pub fn jsx_streaming_to_json(prefixes_input : String) -> String {
  let parts : Array[String] = [
    for sv in prefixes_input.split("\u0000") => sv.to_owned()
  ]
  if parts.is_empty() {
    return Json::array([]).stringify()
  }
  let parser = @loom.new_parser(parts[0], @jsx_ast.jsx_grammar)
  let (proj_memo, _, _) = @jsx_proj.build_jsx_projection_memos(parser)
  let results : Array[Json] = for i in 0..<parts.length(); acc = [] {
    let prefix = parts[i]
    if i > 0 {
      parser.set_source(prefix)
    }
    let errors : Array[String] = get_or_empty_errors(prefix)
    let step = match proj_memo.read_or_abort() {
      Some(proj) =>
        Json::object({
          "prefix_index": Json::number(i.to_double()),
          "success": Json::boolean(true),
          "root": proj_node_to_json(proj),
          "errors": Json::array(errors.map(Json::string)),
        })
      None =>
        Json::object({
          "prefix_index": Json::number(i.to_double()),
          "success": Json::boolean(true),
          "root": Json::null(),
          "errors": Json::array(errors.map(Json::string)),
        })
    }
    continue acc + [step]
  } nobreak {
    acc
  }
  Json::array(results).stringify()
}

///|
/// Parse text just to extract diagnostic errors (side-channel from the shared
/// parser's stream). Returns empty array on LexError.
fn get_or_empty_errors(text : String) -> Array[String] {
  try {
    let (_, errors) = @jsx_proj.parse_to_proj_node(text)
    errors
  } catch {
    _ => []
  }
}

///|
/// Parse JSX text, reconcile against existing NodeIds, apply patches to DOM.
/// `container_json` = JSON.stringify of the container DOM element.
/// `existing_json`  = JSON array of NodeIds from previous render (e.g. "[]").
/// Returns JSON array of NodeIds for the next render call.
pub fn jsx_parse_and_render(
  text : String,
  container_json : String,
  existing_json : String,
) -> String {
  let (proj, _errors) = @jsx_proj.parse_to_proj_node(text) catch {
    _ => return existing_json
  }
  let existing : Array[Int] = []
  let parsed = @js.parse(existing_json)
  let len : Int = parsed.get("length").cast()
  for i in 0..<len {
    let val : Int = parsed.at(i).cast()
    existing.push(val)
  }
  let (patches, _reached) = @jsx_proj.reconcile(proj, existing)
  let patches_json = @jsx_proj.dom_patches_to_json(patches)
  apply_patches(container_json, patches_json)
}
