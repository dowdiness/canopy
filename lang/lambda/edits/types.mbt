// Types for lambda edit operations.

///|
using @core {type NodeId}

///|
using @core {type ProjNode}

///|
using @core {type SourceMap}

///|
using @lambda_proj {
  type FlatProj,
  rebuild_kind,
  to_proj_node,
  parse_to_proj_node,
  populate_token_spans,
}

///|
using @loomcore {trait Renderable}

///|

///|
pub using @core {type DropPosition, type FocusHint}
