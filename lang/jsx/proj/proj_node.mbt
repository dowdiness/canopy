///| CST → ProjNode[@jsx.JsxNode] projection for JSX.
///
/// Uses CstFold to get a fully-populated JsxNode (element tags, attrs,
/// text, opaque expression spans). The ProjNode tree mirrors the AST's
/// own container/leaf split (see loom/examples/jsx/proj_traits.mbt
/// TreeNode::children): Root/Fragment/Element are containers, Text/
/// ExprSpan/Error are leaves.

///|
/// Convenience: parse source and project in one call (for tests and REPL).
pub fn parse_to_proj_node(
  text : String,
) -> (@core.ProjNode[@jsx.JsxNode], Array[String]) raise @loomcore.LexError {
  let (cst, diagnostics) = @jsx.parse_cst(text)
  let syntax_node = @seam.SyntaxNode::from_cst(cst)
  let errors = diagnostics.map(fn(d) { d.message })
  let root = syntax_to_proj_node(syntax_node, Ref(0))
  (root, errors)
}

///|
pub fn syntax_to_proj_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@jsx.JsxNode] {
  let fold = @loomcore.CstFold::new(@jsx.jsx_grammar.fold_node)
  let ast = fold.fold(node)
  build_proj_tree(node, ast, counter)
}

///|
/// Check if text is whitespace-only (newlines/indentation between elements).
/// Returns empty string for whitespace-only content (will be skipped by
/// build_container). Returns the original string unchanged otherwise —
/// text content like "Score: " must preserve its trailing space.
fn normalize_jsx_text(s : String) -> String {
  for ch in s.iter() {
    if ch != ' ' && ch != '\n' && ch != '\t' && ch != '\r' {
      return s
    }
  }
  ""
}

///|
fn build_proj_tree(
  syntax_node : @seam.SyntaxNode,
  ast : @jsx.JsxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@jsx.JsxNode] {
  match ast {
    Root(..) | Fragment(..) =>
      build_container(syntax_node, ast, syntax_node.children(), counter)
    Element(..) =>
      build_container(
        syntax_node,
        ast,
        element_content_children(syntax_node),
        counter,
      )
    Text(s) => {
      let normalized = normalize_jsx_text(s)
      let node_ast = if normalized.is_empty() || normalized == s {
        ast
      } else {
        @jsx.JsxNode::Text(normalized)
      }
      @core.ProjNode::leaf(node_ast, syntax_node, counter)
    }
    ExprSpan(..) | Error(_) => @core.ProjNode::leaf(ast, syntax_node, counter)
  }
}

///|
/// An Element's CST children interleave AttrNodes with its content
/// children — AttrNodes fold into the AST's `attrs` field, not `children`,
/// so they must be excluded here to keep the parallel walk aligned.
fn element_content_children(node : @seam.SyntaxNode) -> Array[@seam.SyntaxNode] {
  let attr_kind = @syntax.SyntaxKind::AttrNode.to_raw()
  node.children().filter(c => c.kind() != attr_kind)
}

///|
fn build_container(
  syntax_node : @seam.SyntaxNode,
  ast : @jsx.JsxNode,
  syntax_children : Array[@seam.SyntaxNode],
  counter : Ref[Int],
) -> @core.ProjNode[@jsx.JsxNode] {
  let ast_children = ast.children()
  let len = syntax_children.length().min(ast_children.length())
  let children : Array[@core.ProjNode[@jsx.JsxNode]] = []
  for i in 0..<len {
    let ast_child = ast_children[i]
    // Filter whitespace-only text (JSX spec §1.5 — insignificant whitespace)
    let is_ws = match ast_child {
      @jsx.JsxNode::Text(s) => normalize_jsx_text(s).is_empty()
      _ => false
    }
    if is_ws {
      continue
    }
    children.push(build_proj_tree(syntax_children[i], ast_child, counter))
  }
  @core.ProjNode::branch(
    ast,
    syntax_node.start(),
    syntax_node.end(),
    children,
    counter,
  )
}

///|
/// Prefer unchanged JSX subtrees when same-kind LCS has multiple alignments.
fn jsx_attr_key(attr : @jsx.JsxAttr) -> String {
  let value = match attr.value {
    @jsx.JsxAttrValue::StringLit(text) => "string:" + text
    @jsx.JsxAttrValue::ExprSpan(raw~) => "expr:" + raw
    @jsx.JsxAttrValue::Bare => "bare"
  }
  attr.name.length().to_string() +
  ":" +
  attr.name +
  value.length().to_string() +
  ":" +
  value
}

///|
fn jsx_exact_key(node : @jsx.JsxNode) -> String {
  match node {
    Root(..) => "Root"
    Fragment(..) => "Fragment"
    Element(tag~, attrs~, ..) => {
      let attrs_key = attrs
        .map(attr => {
          let key = jsx_attr_key(attr)
          key.length().to_string() + ":" + key
        })
        .join("")
      "Element:" +
      tag.length().to_string() +
      ":" +
      tag +
      "[" +
      attrs.length().to_string() +
      ":" +
      attrs_key +
      "]"
    }
    Text(text) => "Text:" + text
    ExprSpan(raw~) => "ExprSpan:" + raw
    Error(message) => "Error:" + message
  }
}

///|
fn reconcile_jsx_projection(
  old : @core.ProjNode[@jsx.JsxNode],
  new : @core.ProjNode[@jsx.JsxNode],
  counter : Ref[Int],
  trace_ref : Ref[Array[@core.ReconcileTraceEvent]]?,
) -> @core.ProjNode[@jsx.JsxNode] {
  @core.reconcile_with_exact_key(old, new, counter, jsx_exact_key, trace_ref~)
}

///|
/// Build the 3-memo pipeline (proj, registry, source_map) for the JSX
/// projection. Delegates to @core.build_projection_memos exactly per
/// ADDING_A_LANGUAGE.md Step 4, with JSX-specific exact-subtree matching.
pub fn build_jsx_projection_memos(
  parser : @loom.Parser[@jsx.JsxNode],
) -> (
  @incr.Derived[@core.ProjNode[@jsx.JsxNode]?],
  @incr.Derived[Map[@core.NodeId, @core.ProjNode[@jsx.JsxNode]]],
  @incr.Derived[@core.SourceMap],
) {
  @core.build_projection_memos(
    parser.runtime(),
    parser.syntax_tree(),
    syntax_to_proj_node,
    populate_token_spans,
    reconcile_node=reconcile_jsx_projection,
    label="jsx",
  )
}
