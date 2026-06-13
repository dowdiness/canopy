// Lambda-specific projection builders.
// Moved from projection/proj_node.mbt to separate language code from framework.

///|
using @core {type ProjNode, type NodeId}

///|
fn error_node_with_span(
  message : String,
  start : Int,
  end : Int,
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  ProjNode::new(Error(message), start, end, @core.next_proj_node_id(counter), [])
}

///|
fn error_node_for_syntax(
  message : String,
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  ProjNode::leaf(Error(message), node, counter)
}

///|
fn app_node(
  left : ProjNode[@ast.Term],
  right : ProjNode[@ast.Term],
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  ProjNode::branch(
    App(left.kind, right.kind),
    @cmp.minimum(left.start, right.start),
    @cmp.maximum(left.end, right.end),
    [left, right],
    counter,
  )
}

///|
fn bop_node(
  op : @ast.Bop,
  left : ProjNode[@ast.Term],
  right : ProjNode[@ast.Term],
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  ProjNode::branch(
    Bop(op, left.kind, right.kind),
    @cmp.minimum(left.start, right.start),
    @cmp.maximum(left.end, right.end),
    [left, right],
    counter,
  )
}

///|
priv struct ProjectedLetDef {
  name : @ast.VarName
  node : ProjNode[@ast.Term]
  start : Int
}

///|
fn unit_node_at(pos : Int, counter : Ref[Int]) -> ProjNode[@ast.Term] {
  ProjNode::new(Unit, pos, pos, @core.next_proj_node_id(counter), [])
}

///|
fn block_inner_bounds(node : @seam.SyntaxNode) -> (Int, Int) {
  let start = match node.find_token(@syntax.LBraceToken.to_raw()) {
    Some(tok) => tok.end()
    None => node.start()
  }
  let end = match node.tokens_of_kind(@syntax.RBraceToken.to_raw()).last() {
    Some(tok) => tok.start()
    None => node.end()
  }
  (start, end)
}

///|
fn with_tight_syntax_range(
  proj : ProjNode[@ast.Term],
  syntax : @seam.SyntaxNode,
) -> ProjNode[@ast.Term] {
  let (start, end) = syntax.tight_span()
  ProjNode::new(proj.kind, start, end, proj.node_id, proj.children)
}

///|
fn project_function_body(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  match @parser.BlockExprView::cast(node) {
    Some(v) => {
      let defs = v.defs().map(fn(def) { project_let_def(def, counter) })
      let (_, inner_end) = block_inner_bounds(node)
      let body = match v.body() {
        Some(body_node) =>
          with_tight_syntax_range(
            syntax_to_proj_node(body_node, counter),
            body_node,
          )
        None => unit_node_at(inner_end, counter)
      }
      if defs.length() > 0 {
        let (inner_start, inner_end) = block_inner_bounds(node)
        module_node_from_defs(defs, body, inner_start, inner_end, counter)
      } else {
        body
      }
    }
    None => syntax_to_proj_node(node, counter)
  }
}

///|
fn wrap_params_as_lams(
  params : Array[String],
  param_starts : Array[Int],
  body : ProjNode[@ast.Term],
  start : Int,
  end : Int,
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  let mut result = body
  for i = params.length() - 1; i >= 0; i = i - 1 {
    let lam_start = if i == 0 || i >= param_starts.length() {
      start
    } else {
      param_starts[i]
    }
    result = ProjNode::branch(
      @ast.Term::Lam(params[i], result.kind),
      lam_start,
      end,
      [result],
      counter,
    )
  }
  result
}

///|
fn project_let_def(
  def : @parser.LetDefView,
  counter : Ref[Int],
) -> ProjectedLetDef {
  let def_node = def.syntax_node()
  let params = def.params()
  let init = match def.init() {
    Some(n) =>
      if params.is_empty() {
        syntax_to_proj_node(n, counter)
      } else {
        project_function_body(n, counter)
      }
    None =>
      error_node_for_syntax("missing let binding value", def_node, counter)
  }
  let param_tokens = param_ident_tokens(def_node)
  let init = wrap_params_as_lams(
    params,
    param_tokens.map(tok => tok.start()),
    init,
    def_node.start(),
    def_node.end(),
    counter,
  )
  let node = ProjNode::branch(
    @ast.Term::LetDef(def.name(), init.kind),
    def_node.start(),
    def_node.end(),
    [init],
    counter,
  )
  { name: def.name(), node, start: def_node.start() }
}

///|
fn module_node_from_defs(
  defs : Array[ProjectedLetDef],
  body : ProjNode[@ast.Term],
  start : Int,
  end : Int,
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  let children : Array[ProjNode[@ast.Term]] = defs.map(fn(d) { d.node })
  children.push(body)
  let term_defs : Array[(@ast.VarName, @ast.Term)] = defs.map(fn(d) {
    match d.node.kind {
      @ast.Term::LetDef(_, init) => (d.name, init)
      _ => (d.name, Error("malformed LetDef"))
    }
  })
  ProjNode::branch(Module(term_defs, body.kind), start, end, children, counter)
}

///|
pub fn syntax_to_proj_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  if @parser.IntLiteralView::cast(node) is Some(v) {
    let kind : @ast.Term = match v.value() {
      Some(n) => Int(n)
      None => Error("invalid integer literal")
    }
    ProjNode::leaf(kind, node, counter)
  } else if @parser.VarRefView::cast(node) is Some(v) {
    ProjNode::leaf(Var(v.name()), node, counter)
  } else if @parser.LambdaExprView::cast(node) is Some(v) {
    let body = match v.body() {
      Some(b) => syntax_to_proj_node(b, counter)
      None => error_node_for_syntax("missing lambda body", node, counter)
    }
    let params = v.params()
    if params.is_empty() {
      error_node_for_syntax("missing lambda parameter", node, counter)
    } else {
      let param_tokens = param_ident_tokens(node)
      wrap_params_as_lams(
        params,
        param_tokens.map(tok => tok.start()),
        body,
        node.start(),
        node.end(),
        counter,
      )
    }
  } else if @parser.AppExprView::cast(node) is Some(v) {
    match v.func() {
      None =>
        error_node_for_syntax("missing function in application", node, counter)
      Some(func_node) => {
        let mut result = syntax_to_proj_node(func_node, counter)
        for arg_node in v.args() {
          let arg = syntax_to_proj_node(arg_node, counter)
          result = app_node(result, arg, counter)
        }
        result
      }
    }
  } else if @parser.BinaryExprView::cast(node) is Some(v) {
    let operands = v.operands()
    let ops = v.ops()
    if operands.length() == 0 {
      error_node_for_syntax("empty BinaryExpr", node, counter)
    } else if operands.length() == 1 {
      syntax_to_proj_node(operands[0], counter)
    } else {
      // Fold n-ary syntax (`a + b + c`) into binary Term shape.
      // The parser emits operator+operand pairs, so `ops` and trailing
      // operands stay balanced; the Error branch guards malformed or
      // hand-built CSTs, not normal parser output. Check before recursing
      // so we neither re-overwrite Error nor traverse unreachable operands.
      let mut result = syntax_to_proj_node(operands[0], counter)
      let mut missing_at : Int? = None
      for i = 1; i < operands.length(); i = i + 1 {
        if i - 1 >= ops.length() {
          missing_at = Some(operands[i].start())
          break
        }
        let rhs = syntax_to_proj_node(operands[i], counter)
        result = bop_node(ops[i - 1], result, rhs, counter)
      }
      match missing_at {
        Some(end) =>
          error_node_with_span(
            "missing binary operator",
            result.start,
            end,
            counter,
          )
        None => result
      }
    }
  } else if @parser.IfExprView::cast(node) is Some(v) {
    let cond = match v.condition() {
      Some(n) => syntax_to_proj_node(n, counter)
      None => error_node_for_syntax("missing if condition", node, counter)
    }
    let then_ = match v.then_branch() {
      Some(n) => syntax_to_proj_node(n, counter)
      None => error_node_for_syntax("missing then branch", node, counter)
    }
    let else_ = match v.else_branch() {
      Some(n) => syntax_to_proj_node(n, counter)
      None => error_node_for_syntax("missing else branch", node, counter)
    }
    ProjNode::branch(
      If(cond.kind, then_.kind, else_.kind),
      node.start(),
      node.end(),
      [cond, then_, else_],
      counter,
    )
  } else if @parser.ParenExprView::cast(node) is Some(v) {
    match v.inner() {
      Some(inner) => {
        // Unwrap to inner Term (no Paren variant in Term), but keep
        // the outer ParenExpr span so positions on ( and ) are covered.
        let inner_node = syntax_to_proj_node(inner, counter)
        ProjNode::new(
          inner_node.kind,
          node.start(),
          node.end(),
          inner_node.node_id,
          inner_node.children,
        )
      }
      None => error_node_for_syntax("empty parentheses", node, counter)
    }
  } else if @parser.BlockExprView::cast(node) is Some(v) {
    // Block expression: { LetDef* Expression? } — same structure as SourceFile.
    // Collect defs + body, produce Module node (or unwrap single expression).
    let defs = v.defs().map(fn(def) { project_let_def(def, counter) })
    let result = match v.body() {
      Some(body) => syntax_to_proj_node(body, counter)
      None => unit_node_at(node.end(), counter)
    }
    if defs.length() > 0 {
      module_node_from_defs(defs, result, node.start(), node.end(), counter)
    } else {
      // Single expression block: unwrap like ParenExpr
      ProjNode::new(
        result.kind,
        node.start(),
        node.end(),
        result.node_id,
        result.children,
      )
    }
  } else if @parser.HoleLiteralView::cast(node) is Some(_) {
    ProjNode::leaf(Hole(0), node, counter)
  } else {
    error_node_for_syntax(
      "unknown node kind: " + node.kind().to_string(),
      node,
      counter,
    )
  }
}

///|
/// Convert a SourceFile SyntaxNode (LetDef* Expression?) to a ProjNode tree.
/// Collects LetDef children into a Module(defs, body) ProjNode whose children
/// are first-class LetDef rows followed by the body expression, mirroring
/// `syntax_node_to_term` while preserving spans and IDs.
pub fn to_proj_node(
  root : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  let defs : Array[ProjectedLetDef] = []
  let mut final_proj : ProjNode[@ast.Term]? = None
  for child in root.children() {
    if @parser.LetDefView::cast(child) is Some(v) {
      defs.push(project_let_def(v, counter))
    } else if final_proj is None {
      final_proj = Some(syntax_to_proj_node(child, counter))
    }
  }
  let mut result = match final_proj {
    Some(p) => p
    None => unit_node_at(root.end(), counter)
  }
  if defs.length() > 0 {
    result = module_node_from_defs(
      defs,
      result,
      defs[0].start,
      result.end,
      counter,
    )
  }
  result
}

///|
/// Rebuild a composite Term's embedded sub-terms from reconciled ProjNode children.
/// Reconstruct a Term kind from a shape and ProjNode children.
/// Delegates to @ast.rebuild_from — the structural source of truth
/// lives in loom/examples/lambda/src/ast/sym.mbt, not here.
pub fn rebuild_kind(
  shape : @ast.Term,
  children : Array[ProjNode[@ast.Term]],
) -> @ast.Term {
  let child_kinds = children.map(fn(c) { c.kind })
  @ast.rebuild_from(shape, child_kinds)
}

///|
/// Parse text and return a ProjNode tree.
/// Uses the unified source-file grammar for both single expressions and
/// multi-definition files.
pub fn parse_to_proj_node(
  text : String,
) -> (ProjNode[@ast.Term], Array[String]) raise @loomcore.LexError {
  let (cst, diagnostics) = @parser.parse_cst(text)
  let syntax_node = @seam.SyntaxNode::from_cst(cst)
  let errors = diagnostics.map(fn(d) { d.message })
  let root = to_proj_node(syntax_node, Ref(0))
  (root, errors)
}
