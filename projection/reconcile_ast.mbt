// Backward-compat alias: delegates to generic reconcile in framework/core/.

///|
pub using @core {reconcile}

///|
/// Backward-compat alias: delegates to generic reconcile.
pub fn reconcile_ast(
  old : ProjNode[@ast.Term],
  new : ProjNode[@ast.Term],
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  @core.reconcile(old, new, counter)
}
