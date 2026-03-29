// Lambda-specific token span extraction.
// Walks SyntaxNode and ProjNode trees in parallel to populate SourceMap token spans.

///|
using @core {type SourceMap}

///|
using @loomcore {type Range}

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
            let ident_token = syn_child.find_token(@syntax.IdentToken.to_raw())
            match ident_token {
              Some(tok) => {
                // Use index-based key for stability across renames
                let role = "name:" + def_idx.to_string()
                source_map.set_token_span(
                  proj_root.id(),
                  role,
                  Range::new(tok.start(), tok.end()),
                )
              }
              None => ()
            }
            // Recurse into the init expression
            match v.init() {
              Some(init_syn) =>
                collect_token_spans_expr(
                  source_map,
                  init_syn,
                  proj_root.children[def_idx],
                )
              None => ()
            }
          }
          def_idx = def_idx + 1
        } else if not(expr_seen) {
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
/// Walk an expression-level syntax node alongside its ProjNode counterpart.
/// Extracts token spans for lambda params and recurses into children.
fn collect_token_spans_expr(
  source_map : SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_node : ProjNode[@ast.Term],
) -> Unit {
  if @parser.LambdaExprView::cast(syntax_node) is Some(v) {
    // Extract param token span
    let ident_token = syntax_node.find_token(@syntax.IdentToken.to_raw())
    match ident_token {
      Some(tok) =>
        source_map.set_token_span(
          proj_node.id(),
          "param",
          Range::new(tok.start(), tok.end()),
        )
      None => ()
    }
    // Recurse into body
    match v.body() {
      Some(body_syn) =>
        if proj_node.children.length() > 0 {
          collect_token_spans_expr(source_map, body_syn, proj_node.children[0])
        }
      None => ()
    }
  } else if @parser.AppExprView::cast(syntax_node) is Some(v) {
    // AppExpr is flattened: syntax has [func, arg1, arg2, ...]
    // ProjNode is nested: App(App(func, arg1), arg2)
    // We need to walk the nested ProjNode tree matching the flat syntax.
    match v.func() {
      Some(func_syn) => {
        let args = v.args()
        if args.length() == 0 {
          // Single func, no args — just recurse
          collect_token_spans_expr(source_map, func_syn, proj_node)
        } else {
          // Navigate to the innermost App (leftmost) which contains func
          let mut current_proj = proj_node
          // Walk down left children to find the innermost
          let depth = args.length()
          let proj_chain : Array[ProjNode[@ast.Term]] = []
          proj_chain.push(current_proj)
          for i = 0; i < depth - 1; i = i + 1 {
            if current_proj.children.length() >= 1 {
              current_proj = current_proj.children[0]
              proj_chain.push(current_proj)
            }
          }
          // Now proj_chain[-1] is the innermost App(func, arg1)
          let innermost = proj_chain[proj_chain.length() - 1]
          if innermost.children.length() >= 2 {
            collect_token_spans_expr(
              source_map,
              func_syn,
              innermost.children[0],
            )
            collect_token_spans_expr(source_map, args[0], innermost.children[1])
          }
          // Walk back up: proj_chain[i]'s right child = args[chain_len - 1 - i]
          for i = proj_chain.length() - 2; i >= 0; i = i - 1 {
            let parent = proj_chain[i]
            let arg_idx = proj_chain.length() - 1 - i
            if arg_idx < args.length() && parent.children.length() >= 2 {
              collect_token_spans_expr(
                source_map,
                args[arg_idx],
                parent.children[1],
              )
            }
          }
        }
      }
      None => ()
    }
  } else if @parser.BinaryExprView::cast(syntax_node) is Some(v) {
    // BinaryExpr operands are flat in CST, nested in ProjNode
    let operands = v.operands()
    if operands.length() <= 1 {
      if operands.length() == 1 {
        collect_token_spans_expr(source_map, operands[0], proj_node)
      }
    } else {
      // Navigate nested Bop tree: Bop(Bop(a, b), c) for a + b + c
      let mut current_proj = proj_node
      let depth = operands.length() - 1
      let proj_chain : Array[ProjNode[@ast.Term]] = []
      proj_chain.push(current_proj)
      for i = 0; i < depth - 1; i = i + 1 {
        if current_proj.children.length() >= 1 {
          current_proj = current_proj.children[0]
          proj_chain.push(current_proj)
        }
      }
      // Innermost: Bop(operands[0], operands[1])
      let innermost = proj_chain[proj_chain.length() - 1]
      if innermost.children.length() >= 2 {
        collect_token_spans_expr(source_map, operands[0], innermost.children[0])
        collect_token_spans_expr(source_map, operands[1], innermost.children[1])
      }
      // BinaryExpr innermost eats operands[0] and operands[1],
      // so back-walk starts from operands[2]: op_idx = chain.length() - i
      for i = proj_chain.length() - 2; i >= 0; i = i - 1 {
        let parent = proj_chain[i]
        let op_idx = proj_chain.length() - i
        if op_idx < operands.length() && parent.children.length() >= 2 {
          collect_token_spans_expr(
            source_map,
            operands[op_idx],
            parent.children[1],
          )
        }
      }
    }
  } else if @parser.IfExprView::cast(syntax_node) is Some(v) {
    match v.condition() {
      Some(cond) =>
        if proj_node.children.length() > 0 {
          collect_token_spans_expr(source_map, cond, proj_node.children[0])
        }
      None => ()
    }
    match v.then_branch() {
      Some(then_) =>
        if proj_node.children.length() > 1 {
          collect_token_spans_expr(source_map, then_, proj_node.children[1])
        }
      None => ()
    }
    match v.else_branch() {
      Some(else_) =>
        if proj_node.children.length() > 2 {
          collect_token_spans_expr(source_map, else_, proj_node.children[2])
        }
      None => ()
    }
  } else if @parser.ParenExprView::cast(syntax_node) is Some(v) {
    // ParenExpr unwraps: ProjNode reuses inner's node_id and children
    match v.inner() {
      Some(inner) => collect_token_spans_expr(source_map, inner, proj_node)
      None => ()
    }
  }
  // IntLiteral, VarRef: leaf nodes, no token spans to extract
}
