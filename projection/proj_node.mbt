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
/// Recursively build a ProjNode tree from an @ast.Term value.
/// Each Term node gets a unique node_id from the counter.
/// children mirrors the Term structure so that tree operations (insert,
/// delete, reconcile) can navigate and mutate the tree.
fn term_to_proj_node(
  term : @ast.Term,
  counter : Ref[Int],
  start : Int,
  end : Int,
) -> ProjNode {
  let id = counter.val
  counter.val = counter.val + 1
  let children : Array[ProjNode] = match term {
    Lam(_, body) => [term_to_proj_node(body, counter, start, end)]
    App(f, a) =>
      [
        term_to_proj_node(f, counter, start, end),
        term_to_proj_node(a, counter, start, end),
      ]
    Bop(_, l, r) =>
      [
        term_to_proj_node(l, counter, start, end),
        term_to_proj_node(r, counter, start, end),
      ]
    If(c, t, e) =>
      [
        term_to_proj_node(c, counter, start, end),
        term_to_proj_node(t, counter, start, end),
        term_to_proj_node(e, counter, start, end),
      ]
    Let(_, v, body) =>
      [
        term_to_proj_node(v, counter, start, end),
        term_to_proj_node(body, counter, start, end),
      ]
    _ => []
  }
  { node_id: id, kind: term, children, start, end }
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
/// Uses ImperativeParser internally. Positions are approximate (full text range).
pub fn parse_to_proj_node(text : String) -> (ProjNode, Array[String]) {
  let ip = @loom.new_imperative_parser(text, @parser.lambda_grammar)
  let syntax_node = ip.parse()
  let term = @parser.syntax_node_to_term(syntax_node)
  let errors = ip.diagnostics()
  let root = term_to_proj_node(term, Ref::new(0), 0, text.length())
  (root, errors)
}
