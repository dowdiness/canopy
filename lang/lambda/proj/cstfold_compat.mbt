///|
/// Normalize Loom Lambda CstFold terms to Canopy's current projection kind
/// semantics for block expressions.
///
/// Loom keeps expression blocks explicit in its raw CstFold term shape:
/// `{ 1 }` folds to `Module([], Int(1))`, and `{}` folds to
/// `Error("empty block")`. The Lambda editor already treats a block with no
/// definitions like grouping syntax and treats an empty block as `Unit`.
/// Keep that compatibility boundary explicit until the projection pipeline is
/// fully CstFold-backed. It is private until the production projection path
/// starts consuming CstFold terms directly; wbtests exercise it meanwhile.
#warnings("-unused_value")
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
