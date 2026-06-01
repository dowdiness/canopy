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
  // For a Module ProjNode, children are: [init_0, init_1, ..., body]
  // The syntax_root has LetDef children and optionally a final expression child.
  match proj_root.kind {
    Module(defs, _) => {
      let syntax_children = syntax_root.children()
      let mut def_idx = 0
      let mut expr_seen = false
      for syn_child in syntax_children {
        if @parser.LetDefView::cast(syn_child) is Some(v) {
          if def_idx < defs.length() && def_idx < proj_root.children.length() {
            // The ProjNode child at def_idx is the init expression, but
            // the LetDef's name token belongs to the LetDef itself.
            // We need a NodeId for the LetDef. In the current FlatProj model,
            // LetDef nodes don't have their own ProjNode — the Module node
            // owns the defs array. So we store the name span on the Module
            // node with a role like "name:0", "name:1", etc.
            // Use index-based key for stability across renames
            let role = module_name_role(def_idx)
            source_map.set_span_from_token(
              proj_root.id(),
              role,
              syn_child,
              @syntax.IdentToken.to_raw(),
            )
            // Recurse into the init expression
            if v.init() is Some(init_syn) {
              collect_token_spans_expr(
                source_map,
                init_syn,
                proj_root.children[def_idx],
              )
            }
          }
          def_idx = def_idx + 1
        } else if !expr_seen {
          expr_seen = true
          // This is the final expression — last child of Module ProjNode
          let body_idx = proj_root.children.length() - 1
          if body_idx >= 0 {
            collect_token_spans_expr(
              source_map,
              syn_child,
              proj_root.children[body_idx],
            )
          }
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
/// Walk an expression-level syntax node alongside its ProjNode counterpart.
/// Extracts token spans for lambda params and recurses into children.
fn collect_token_spans_expr(
  source_map : SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_node : ProjNode[@ast.Term],
) -> Unit {
  if @parser.LambdaExprView::cast(syntax_node) is Some(v) {
    // Extract param token span
    source_map.set_span_from_token(
      proj_node.id(),
      PARAM_ROLE,
      syntax_node,
      @syntax.IdentToken.to_raw(),
    )
    // Recurse into body
    if v.body() is Some(body_syn) && proj_node.children.length() > 0 {
      collect_token_spans_expr(source_map, body_syn, proj_node.children[0])
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
  }
  // IntLiteral, VarRef: leaf nodes, no token spans to extract
}
