// Re-exports so @proj.ProjNode and @proj.syntax_to_proj_node continue to work.

///|
pub using @core {type ProjNode, collect_registry}

///|
pub using @lambda_proj {
  syntax_to_proj_node,
  to_proj_node,
  parse_to_proj_node,
  rebuild_kind,
}
