// Re-exports so @proj.FlatProj and @proj.to_flat_proj continue to work.

///|
pub using @lambda_proj {
  type FlatProj,
  to_flat_proj,
  to_flat_proj_incremental,
  reconcile_flat_proj,
  print_flat_proj,
}
