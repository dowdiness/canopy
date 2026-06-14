///|
/// Normalize Loom Lambda CstFold terms to Canopy's current projection kind
/// semantics for block expressions.
///
/// Loom keeps expression blocks explicit in its raw CstFold term shape:
/// `{ 1 }` folds to `Module([], Int(1))`, and `{}` folds to
/// `Error("empty block")`. The Lambda editor already treats a block with no
/// definitions like grouping syntax and treats an empty block as `Unit`.
/// Keep that compatibility boundary explicit until the projection pipeline is
/// fully CstFold-backed.
fn cstfold_projection_compatible_term(term : @ast.Term) -> @ast.Term {
  match term {
    Error("empty block") => Unit
    Module([], body) => cstfold_projection_compatible_term(body)
    _ =>
      match term.children() {
        [] => term
        children =>
          @ast.rebuild_from(
            term,
            children.map(fn(child) { cstfold_projection_compatible_term(child) }),
          )
      }
  }
}

///|
/// Candidate existing APIs checked: `@parser.syntax_node_to_term` already
/// converts a CST syntax node through Loom Lambda's CstFold path, but it returns
/// raw CstFold block semantics. `cstfold_projection_compatible_term` already
/// normalizes those terms to Canopy projection semantics, but it starts from a
/// folded `Term` rather than a CST node. This helper's responsibility boundary
/// is exactly their composition: convert a CST node to a projection-compatible
/// `Term` by folding with `@parser.syntax_node_to_term`, then applying
/// `cstfold_projection_compatible_term`.
fn cstfold_projection_compatible_kind(node : @seam.SyntaxNode) -> @ast.Term {
  cstfold_projection_compatible_term(@parser.syntax_node_to_term(node))
}

///|
/// Apply only the top-level block compatibility rules needed by shallow parent
/// shapes. Do not recurse into `term.children()`: flat AppExpr/BinaryExpr parent
/// shapes are left-nested, and recursive normalization would reintroduce one
/// call frame per argument/operator before projection can build its iterative
/// spine.
fn cstfold_projection_compatible_shallow_term(term : @ast.Term) -> @ast.Term {
  match term {
    Error("empty block") => Unit
    Module([], body) => body
    _ => term
  }
}

///|
/// Candidate existing APIs checked: `@parser.lambda_fold_node` already exposes
/// Loom Lambda's per-node CstFold algebra with caller-controlled recursion.
/// `cstfold_projection_compatible_term` already applies full Canopy block
/// compatibility normalization to recursive folds, but shallow composite parent
/// shapes must avoid recursively walking generated left spines. This helper's
/// responsibility boundary is parent-shape extraction for composite `ProjNode`
/// builders: fold exactly the requested CST node with placeholder children,
/// normalize only that shallow top-level shape, and leave descendant terms to
/// the already-projected children.
fn cstfold_projection_compatible_shallow_kind(
  node : @seam.SyntaxNode,
) -> @ast.Term {
  cstfold_projection_compatible_shallow_term(
    @parser.lambda_fold_node(node, fn(_child) { Unit }),
  )
}
