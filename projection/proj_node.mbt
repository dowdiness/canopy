// ProjNode: Local node type for the projection package.
// Replaces the removed @ast.AstNode with a Term-based equivalent.
// ProjNode preserves node IDs and positions needed for projectional editing,
// while using @ast.Term as the structural kind.

///|
/// Local node type for the projection package.
/// Replaces the removed @ast.AstNode with a Term-based equivalent.
pub struct ProjNode {
  node_id : Int
  kind : @ast.Term
  children : Array[ProjNode]
  start : Int
  end : Int
} derive(Show)

///|
pub fn ProjNode::new(
  kind : @ast.Term,
  start : Int,
  end : Int,
  node_id : Int,
  children : Array[ProjNode],
) -> ProjNode {
  { node_id, kind, children, start, end }
}

///|
fn next_proj_node_id(counter : Ref[Int]) -> Int {
  let id = counter.val
  counter.val = counter.val + 1
  id
}

///|
fn min_int(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn max_int(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn error_node_with_span(
  message : String,
  start : Int,
  end : Int,
  counter : Ref[Int],
) -> ProjNode {
  ProjNode::new(Error(message), start, end, next_proj_node_id(counter), [])
}

///|
fn error_node_for_syntax(
  message : String,
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode {
  error_node_with_span(message, node.start(), node.end(), counter)
}

///|
fn app_node(left : ProjNode, right : ProjNode, counter : Ref[Int]) -> ProjNode {
  ProjNode::new(
    App(left.kind, right.kind),
    min_int(left.start, right.start),
    max_int(left.end, right.end),
    next_proj_node_id(counter),
    [left, right],
  )
}

///|
fn bop_node(
  op : @ast.Bop,
  left : ProjNode,
  right : ProjNode,
  counter : Ref[Int],
) -> ProjNode {
  ProjNode::new(
    Bop(op, left.kind, right.kind),
    min_int(left.start, right.start),
    max_int(left.end, right.end),
    next_proj_node_id(counter),
    [left, right],
  )
}

///|
fn syntax_to_proj_node(node : @seam.SyntaxNode, counter : Ref[Int]) -> ProjNode {
  if @parser.IntLiteralView::cast(node) is Some(v) {
    ProjNode::new(
      Int(v.value().unwrap_or(0)),
      node.start(),
      node.end(),
      next_proj_node_id(counter),
      [],
    )
  } else if @parser.VarRefView::cast(node) is Some(v) {
    ProjNode::new(
      Var(v.name()),
      node.start(),
      node.end(),
      next_proj_node_id(counter),
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
      next_proj_node_id(counter),
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
      next_proj_node_id(counter),
      [cond, then_, else_],
    )
  } else if @parser.LetExprView::cast(node) is Some(v) {
    let init = match v.init() {
      Some(n) => syntax_to_proj_node(n, counter)
      None => error_node_for_syntax("missing let binding value", node, counter)
    }
    let body = match v.body() {
      Some(n) => syntax_to_proj_node(n, counter)
      None => error_node_for_syntax("missing let body", node, counter)
    }
    ProjNode::new(
      Let(v.name(), init.kind, body.kind),
      node.start(),
      node.end(),
      next_proj_node_id(counter),
      [init, body],
    )
  } else if @parser.ParenExprView::cast(node) is Some(v) {
    match v.inner() {
      Some(inner) => syntax_to_proj_node(inner, counter)
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
fn is_term_expression_node(node : @seam.SyntaxNode) -> Bool {
  @parser.IntLiteralView::cast(node) is Some(_) ||
  @parser.VarRefView::cast(node) is Some(_) ||
  @parser.LambdaExprView::cast(node) is Some(_) ||
  @parser.AppExprView::cast(node) is Some(_) ||
  @parser.BinaryExprView::cast(node) is Some(_) ||
  @parser.IfExprView::cast(node) is Some(_) ||
  @parser.LetExprView::cast(node) is Some(_) ||
  @parser.ParenExprView::cast(node) is Some(_)
}

///|
fn unwrap_expression_root(node : @seam.SyntaxNode) -> @seam.SyntaxNode {
  if is_term_expression_node(node) {
    node
  } else {
    match node.nth_child(0) {
      Some(child) => child
      None => node
    }
  }
}

///|
/// Rebuild a composite Term's embedded sub-terms from reconciled ProjNode children.
/// `shape` provides the constructor tag and scalar metadata (param name, op, let name).
/// `children` provides the updated sub-terms.
/// Leaf terms (Int, Var, Unit, Error) are returned unchanged.
fn rebuild_kind(shape : @ast.Term, children : Array[ProjNode]) -> @ast.Term {
  match shape {
    Lam(param, _) =>
      if children.length() > 0 {
        Lam(param, children[0].kind)
      } else {
        shape
      }
    App(_, _) =>
      if children.length() >= 2 {
        App(children[0].kind, children[1].kind)
      } else {
        shape
      }
    Bop(op, _, _) =>
      if children.length() >= 2 {
        Bop(op, children[0].kind, children[1].kind)
      } else {
        shape
      }
    If(_, _, _) =>
      if children.length() >= 3 {
        If(children[0].kind, children[1].kind, children[2].kind)
      } else {
        shape
      }
    Let(name, _, _) =>
      if children.length() >= 2 {
        Let(name, children[0].kind, children[1].kind)
      } else {
        shape
      }
    _ => shape
  }
}

///|
/// Check if two Term values have the same constructor tag.
/// Used for LCS-based matching in children reconciliation.
fn same_kind_tag(a : @ast.Term, b : @ast.Term) -> Bool {
  match (a, b) {
    (Int(_), Int(_)) => true
    (Var(_), Var(_)) => true
    (Lam(_, _), Lam(_, _)) => true
    (App(_, _), App(_, _)) => true
    (Bop(_, _, _), Bop(_, _, _)) => true
    (If(_, _, _), If(_, _, _)) => true
    (Let(_, _, _), Let(_, _, _)) => true
    (Unit, Unit) => true
    (Error(_), Error(_)) => true
    _ => false
  }
}

///|
/// Parse text and return a ProjNode tree (replaces @parser.parse_with_error_recovery).
/// Uses ImperativeParser internally and preserves node-specific source ranges.
pub fn parse_to_proj_node(text : String) -> (ProjNode, Array[String]) {
  let ip = @loom.new_imperative_parser(text, @parser.lambda_grammar)
  let syntax_node : @seam.SyntaxNode = ip.parse()
  let errors = ip.diagnostics()
  let root = syntax_to_proj_node(
    unwrap_expression_root(syntax_node),
    Ref::new(0),
  )
  (root, errors)
}
