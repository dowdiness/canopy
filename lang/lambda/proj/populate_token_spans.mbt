// Lambda-specific token span extraction.
// Walks SyntaxNode and ProjNode trees in parallel to populate SourceMap token spans.

///|
using @core {type SourceMap}

///|
/// Populate token-level spans by walking a SyntaxNode tree in parallel
/// with a ProjNode tree.
pub fn populate_token_spans(
  source_map : SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : ProjNode[@ast.Term],
) -> Unit {
  collect_token_spans_source_file(source_map, syntax_root, proj_root)
}

///|
/// Walk a SourceFile syntax node and its corresponding Module ProjNode.
/// Handles LetDef children at the top level and delegates expression
/// children to collect_token_spans_expr.
fn collect_token_spans_source_file(
  source_map : SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : ProjNode[@ast.Term],
) -> Unit {
  // For a Module ProjNode, children are: [LetDef_0, LetDef_1, ..., body]
  // The syntax_root has LetDef children and optionally a final expression child.
  match proj_root.kind {
    Module(defs, _) => {
      let syntax_children = syntax_root.children()
      let mut def_idx = 0
      let mut expr_seen = false
      for syn_child in syntax_children {
        if @parser.LetDefView::cast(syn_child) is Some(v) {
          if def_idx < defs.length() && def_idx < proj_root.children.length() {
            collect_token_spans_let_def(
              source_map,
              proj_root,
              def_idx,
              v,
              proj_root.children[def_idx],
            )
          }
          def_idx = def_idx + 1
        } else if !expr_seen {
          expr_seen = true
          // This is the final expression. If no source-file LetDefs were
          // consumed, a Module ProjNode here came from the expression itself
          // (for example a block `{ let x = ... }`), so walk the root Module.
          // Otherwise the final expression is the last child of the top-level
          // Module ProjNode.
          let body_proj = if def_idx == 0 {
            proj_root
          } else {
            proj_root.children[proj_root.children.length() - 1]
          }
          collect_token_spans_expr(source_map, syn_child, body_proj)
        }
      }
    }
    _ => {
      // Not a Module — the ProjNode is a single expression.
      // The syntax_root is a SourceFile; find the first non-LetDef child.
      let syntax_children = syntax_root.children()
      for syn_child in syntax_children {
        if @parser.LetDefView::cast(syn_child) is None {
          collect_token_spans_expr(source_map, syn_child, proj_root)
          break
        }
      }
    }
  }
}

///|
/// Record the binder-name token span for one LetDef row and recurse into its
/// initializer. The canonical span lives on the LetDef node; the module-level
/// `name:<i>` span remains as a migration fallback for older callers.
fn collect_token_spans_let_def(
  source_map : SourceMap,
  module_node : ProjNode[@ast.Term],
  def_index : Int,
  def_view : @parser.LetDefView,
  let_def_node : ProjNode[@ast.Term],
) -> Unit {
  let def_syn = def_view.syntax_node()
  source_map.set_span_from_token(
    let_def_node.id(),
    LET_DEF_NAME_ROLE,
    def_syn,
    @syntax.IdentToken.to_raw(),
  )
  source_map.set_span_from_token(
    module_node.id(),
    module_name_role(def_index),
    def_syn,
    @syntax.IdentToken.to_raw(),
  )
  guard def_view.init() is Some(init_syn) && let_def_node.children.length() > 0 else {
    return
  }
  let init_proj = let_def_node.children[0]
  let param_count = param_ident_tokens(def_syn).length()
  if param_count == 0 {
    collect_token_spans_expr(source_map, init_syn, init_proj)
  } else {
    collect_token_spans_lambda_params(source_map, def_syn, init_proj)
    match lambda_body_proj(init_proj, param_count) {
      Some(body_proj) =>
        collect_token_spans_expr(source_map, init_syn, body_proj)
      None => ()
    }
  }
}

///|
/// Walk flat CST children against a left-nested ProjNode spine.
/// AppExpr and BinaryExpr are flat in the CST but left-folded in the
/// projection tree: the first syntax node and first rest node live in the
/// innermost projection node, then each remaining syntax node maps to the
/// right child while walking back up the left spine. Keep this iterative so
/// long flat expressions do not add O(n) call-stack depth.
fn collect_token_spans_left_spine(
  source_map : SourceMap,
  first_syntax : @seam.SyntaxNode,
  rest_syntax : ArrayView[@seam.SyntaxNode],
  proj_node : ProjNode[@ast.Term],
) -> Unit {
  match rest_syntax {
    [] => collect_token_spans_expr(source_map, first_syntax, proj_node)
    _ => {
      let mut current_proj = proj_node
      let proj_chain : Array[ProjNode[@ast.Term]] = []
      proj_chain.push(current_proj)
      for _ in 0..<(rest_syntax.length() - 1) {
        if current_proj.children.length() >= 1 {
          current_proj = current_proj.children[0]
          proj_chain.push(current_proj)
        }
      }
      let innermost = proj_chain[proj_chain.length() - 1]
      if innermost.children.length() >= 2 {
        collect_token_spans_expr(
          source_map,
          first_syntax,
          innermost.children[0],
        )
        collect_token_spans_expr(
          source_map,
          rest_syntax[0],
          innermost.children[1],
        )
      }
      for i = proj_chain.length() - 2; i >= 0; i = i - 1 {
        let parent = proj_chain[i]
        let rest_idx = proj_chain.length() - 1 - i
        if rest_idx < rest_syntax.length() && parent.children.length() >= 2 {
          collect_token_spans_expr(
            source_map,
            rest_syntax[rest_idx],
            parent.children[1],
          )
        }
      }
    }
  }
}

///|
fn param_ident_tokens(node : @seam.SyntaxNode) -> Array[@seam.SyntaxToken] {
  let param_list = node
    .children()
    .iter()
    .find_first(child => {
      @syntax.SyntaxKind::from_raw(child.kind()) == @syntax.ParamList
    })
  match param_list {
    Some(params) => {
      let tokens : Array[@seam.SyntaxToken] = []
      let mut expect_param = true
      for elem in params.all_children() {
        match elem {
          @seam.SyntaxElement::Token(tok) => {
            let kind = @syntax.SyntaxKind::from_raw(tok.kind())
            if kind == @syntax.IdentToken && expect_param {
              tokens.push(tok)
              expect_param = false
            } else if kind == @syntax.CommaToken {
              expect_param = true
            }
          }
          _ => ()
        }
      }
      tokens
    }
    None => []
  }
}

///|
fn collect_token_spans_lambda_params(
  source_map : SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_node : ProjNode[@ast.Term],
) -> Unit {
  let tokens = param_ident_tokens(syntax_node)
  let mut current = proj_node
  for index, tok in tokens {
    source_map.set_token_span(
      current.id(),
      PARAM_ROLE,
      @loomcore.Range::new(tok.start(), tok.end()),
    )
    if index + 1 < tokens.length() {
      if current.children.length() == 0 {
        break
      }
      current = current.children[0]
    }
  }
}

///|
fn lambda_body_proj(
  proj_node : ProjNode[@ast.Term],
  param_count : Int,
) -> ProjNode[@ast.Term]? {
  let mut current = proj_node
  for _ in 0..<param_count {
    match current.kind {
      @ast.Term::Lam(_, _) =>
        if current.children.length() > 0 {
          current = current.children[0]
        } else {
          return None
        }
      _ => return None
    }
  }
  Some(current)
}

///|
/// Walk an expression-level syntax node alongside its ProjNode counterpart.
/// Extracts token spans for lambda params and recurses into children.
fn collect_token_spans_expr(
  source_map : SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_node : ProjNode[@ast.Term],
) -> Unit {
  if @parser.LambdaExprView::cast(syntax_node) is Some(v) {
    collect_token_spans_lambda_params(source_map, syntax_node, proj_node)
    if v.body() is Some(body_syn) {
      match
        lambda_body_proj(proj_node, param_ident_tokens(syntax_node).length()) {
        Some(body_proj) =>
          collect_token_spans_expr(source_map, body_syn, body_proj)
        None => ()
      }
    }
  } else if @parser.AppExprView::cast(syntax_node) is Some(v) {
    // AppExpr is flattened: syntax has [func, arg1, arg2, ...]
    // ProjNode is nested: App(App(func, arg1), arg2)
    match v.func() {
      Some(func_syn) =>
        collect_token_spans_left_spine(
          source_map,
          func_syn,
          v.args(),
          proj_node,
        )
      None => ()
    }
  } else if @parser.BinaryExprView::cast(syntax_node) is Some(v) {
    // BinaryExpr operands are flat in CST, nested in ProjNode.
    match v.operands() {
      [] => ()
      [first, .. rest] =>
        collect_token_spans_left_spine(source_map, first, rest, proj_node)
    }
  } else if @parser.IfExprView::cast(syntax_node) is Some(v) {
    if v.condition() is Some(cond) && proj_node.children.length() > 0 {
      collect_token_spans_expr(source_map, cond, proj_node.children[0])
    }
    if v.then_branch() is Some(then_) && proj_node.children.length() > 1 {
      collect_token_spans_expr(source_map, then_, proj_node.children[1])
    }
    if v.else_branch() is Some(else_) && proj_node.children.length() > 2 {
      collect_token_spans_expr(source_map, else_, proj_node.children[2])
    }
  } else if @parser.ParenExprView::cast(syntax_node) is Some(v) {
    // ParenExpr unwraps: ProjNode reuses inner's node_id and children
    if v.inner() is Some(inner) {
      collect_token_spans_expr(source_map, inner, proj_node)
    }
  } else if @parser.BlockExprView::cast(syntax_node) is Some(v) {
    match proj_node.kind {
      Module(defs, _) => {
        let mut def_idx = 0
        for def_view in v.defs() {
          if def_idx < defs.length() && def_idx < proj_node.children.length() {
            collect_token_spans_let_def(
              source_map,
              proj_node,
              def_idx,
              def_view,
              proj_node.children[def_idx],
            )
          }
          def_idx = def_idx + 1
        }
        if v.body() is Some(body_syn) {
          let body_idx = proj_node.children.length() - 1
          if body_idx >= 0 {
            collect_token_spans_expr(
              source_map,
              body_syn,
              proj_node.children[body_idx],
            )
          }
        }
      }
      _ =>
        if v.body() is Some(body_syn) {
          collect_token_spans_expr(source_map, body_syn, proj_node)
        }
    }
  }
  // IntLiteral, VarRef: leaf nodes, no token spans to extract
}
