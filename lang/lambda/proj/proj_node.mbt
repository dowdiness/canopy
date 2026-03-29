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
  error_node_with_span(message, node.start(), node.end(), counter)
}

///|
fn app_node(
  left : ProjNode[@ast.Term],
  right : ProjNode[@ast.Term],
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  ProjNode::new(
    App(left.kind, right.kind),
    @cmp.minimum(left.start, right.start),
    @cmp.maximum(left.end, right.end),
    @core.next_proj_node_id(counter),
    [left, right],
  )
}

///|
fn bop_node(
  op : @ast.Bop,
  left : ProjNode[@ast.Term],
  right : ProjNode[@ast.Term],
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  ProjNode::new(
    Bop(op, left.kind, right.kind),
    @cmp.minimum(left.start, right.start),
    @cmp.maximum(left.end, right.end),
    @core.next_proj_node_id(counter),
    [left, right],
  )
}

///|
pub fn syntax_to_proj_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  if @parser.IntLiteralView::cast(node) is Some(v) {
    ProjNode::new(
      Int(v.value().unwrap_or(0)),
      node.start(),
      node.end(),
      @core.next_proj_node_id(counter),
      [],
    )
  } else if @parser.VarRefView::cast(node) is Some(v) {
    ProjNode::new(
      Var(v.name()),
      node.start(),
      node.end(),
      @core.next_proj_node_id(counter),
      [],
    )
  } else if @parser.LambdaExprView::cast(node) is Some(v) {
    let body = match v.body() {
      Some(b) => syntax_to_proj_node(b, counter)
      None => error_node_for_syntax("missing lambda body", node, counter)
    }
    ProjNode::new(
      Lam(v.param(), body.kind),
      node.start(),
      node.end(),
      @core.next_proj_node_id(counter),
      [body],
    )
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
      let mut result = syntax_to_proj_node(operands[0], counter)
      for i = 1; i < operands.length(); i = i + 1 {
        let op = if i - 1 < ops.length() { ops[i - 1] } else { @ast.Bop::Plus }
        let rhs = syntax_to_proj_node(operands[i], counter)
        result = bop_node(op, result, rhs, counter)
      }
      result
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
    ProjNode::new(
      If(cond.kind, then_.kind, else_.kind),
      node.start(),
      node.end(),
      @core.next_proj_node_id(counter),
      [cond, then_, else_],
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
/// Collects LetDef children into a flat Module(defs, body) ProjNode,
/// mirroring `syntax_node_to_term` but preserving spans and IDs.
///
/// LetDef children are collected into a single Module node with flat children.
pub fn to_proj_node(
  root : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  let defs : Array[(String, ProjNode[@ast.Term], Int)] = []
  let mut final_proj : ProjNode[@ast.Term]? = None
  for child in root.children() {
    if @parser.LetDefView::cast(child) is Some(v) {
      let init = match v.init() {
        Some(n) => syntax_to_proj_node(n, counter)
        None =>
          error_node_for_syntax("missing let binding value", child, counter)
      }
      defs.push((v.name(), init, child.start()))
    } else if final_proj is None {
      final_proj = Some(syntax_to_proj_node(child, counter))
    }
  }
  let mut result = match final_proj {
    Some(p) => p
    None =>
      ProjNode::new(
        Unit,
        root.end(),
        root.end(),
        @core.next_proj_node_id(counter),
        [],
      )
  }
  if defs.length() > 0 {
    let children : Array[ProjNode[@ast.Term]] = defs.map(fn(d) { d.1 })
    children.push(result)
    let term_defs : Array[(@ast.VarName, @ast.Term)] = defs.map(fn(d) {
      (d.0, d.1.kind)
    })
    result = ProjNode::new(
      Module(term_defs, result.kind),
      defs[0].2,
      result.end,
      @core.next_proj_node_id(counter),
      children,
    )
  }
  result
}

///|
/// Rebuild a composite Term's embedded sub-terms from reconciled ProjNode children.
/// `shape` provides the constructor tag and scalar metadata (param name, op, let name).
/// `children` provides the updated sub-terms.
/// Leaf terms (Int, Var, Unit, Error) are returned unchanged.
pub fn rebuild_kind(
  shape : @ast.Term,
  children : Array[ProjNode[@ast.Term]],
) -> @ast.Term {
  fn child_kind(i : Int) -> @ast.Term {
    if i < children.length() {
      children[i].kind
    } else {
      Error("missing")
    }
  }

  match shape {
    Lam(param, _) => Lam(param, child_kind(0))
    App(_, _) => App(child_kind(0), child_kind(1))
    Bop(op, _, _) => Bop(op, child_kind(0), child_kind(1))
    If(_, _, _) => If(child_kind(0), child_kind(1), child_kind(2))
    Module(old_defs, _) =>
      if children.length() >= 1 {
        let new_defs : Array[(@ast.VarName, @ast.Term)] = []
        for i = 0; i < children.length() - 1; i = i + 1 {
          let name = if i < old_defs.length() { old_defs[i].0 } else { "_" }
          new_defs.push((name, children[i].kind))
        }
        Module(new_defs, children[children.length() - 1].kind)
      } else {
        Module([], child_kind(0))
      }
    _ => shape
  }
}

///|
/// Parse text and return a ProjNode tree.
/// Uses the unified source-file grammar for both single expressions and
/// multi-definition files.
pub fn parse_to_proj_node(
  text : String,
) -> (ProjNode[@ast.Term], Array[String]) {
  let (cst, diagnostics) = @parser.parse_cst(text) catch {
    _ => abort("parse failed")
  }
  let syntax_node = @seam.SyntaxNode::from_cst(cst)
  let errors = diagnostics.map(fn(d) { d.message })
  let root = to_proj_node(syntax_node, Ref::new(0))
  (root, errors)
}
