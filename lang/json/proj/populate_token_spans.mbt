// JSON-specific token span extraction.
// Walks SyntaxNode and ProjNode trees in parallel to populate SourceMap token spans.

///|
using @core {type SourceMap}

///|
/// Token span role for object member keys. Convention: "key:0", "key:1", etc.
pub fn key_role(index : Int) -> String {
  "key:" + index.to_string()
}

///|
/// Token span role for full object members (key + colon + value).
/// Convention: "member:0", "member:1", etc.
/// Used by Delete to remove the complete member text.
pub fn member_role(index : Int) -> String {
  "member:" + index.to_string()
}

///|
/// Populate token-level spans by walking a SyntaxNode tree in parallel
/// with a ProjNode tree. Handles RootNode unwrapping.
pub fn populate_token_spans(
  source_map : SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : ProjNode[@json.JsonValue],
) -> Unit {
  // Unwrap RootNode to get the actual value node
  let syntax_node = if syntax_root.kind() == @json.RootNode.to_raw() {
    match syntax_root.first_child() {
      Some(child) => child
      None => return
    }
  } else {
    syntax_root
  }
  collect_token_spans(source_map, syntax_node, proj_root)
}

///|
/// Walk a syntax node alongside its ProjNode counterpart.
/// Extracts token spans for object keys and recurses into children.
fn collect_token_spans(
  source_map : SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_node : ProjNode[@json.JsonValue],
) -> Unit {
  match @json.SyntaxKind::from_raw(syntax_node.kind()) {
    ObjectNode => {
      // For ObjectNode, iterate MemberNode children.
      // Each ProjNode child corresponds to a MemberNode.
      // Key spans and member spans are stored on the Object ProjNode (parent),
      // since RenameKey and Delete operate by object_id + index.
      let member_nodes = syntax_node.children()
      let mut proj_idx = 0
      for member_syn in member_nodes {
        if @json.SyntaxKind::from_raw(member_syn.kind()) == @json.MemberNode &&
          proj_idx < proj_node.children.length() {
          let child_proj = proj_node.children[proj_idx]
          // Record the full member span on the Object node
          source_map.set_token_span(
            proj_node.id(),
            member_role(proj_idx),
            @loomcore.Range::new(member_syn.start(), member_syn.end()),
          )
          // Find the StringToken key and record its span on the Object node
          for elem in member_syn.all_children() {
            match elem {
              @seam.SyntaxElement::Token(t) =>
                if t.kind() == @json.StringToken.to_raw() {
                  source_map.set_token_span(
                    proj_node.id(),
                    key_role(proj_idx),
                    @loomcore.Range::new(t.start(), t.end()),
                  )
                  break
                }
              _ => ()
            }
          }
          // Recurse into the value (first node child of MemberNode)
          match member_syn.nth_child(0) {
            Some(value_syn) =>
              // The ProjNode child may itself have children (nested object/array)
              collect_token_spans(source_map, value_syn, child_proj)
            None => ()
          }
          proj_idx = proj_idx + 1
        }
      }
    }
    ArrayNode => {
      // For ArrayNode, iterate node children in parallel with ProjNode children.
      let element_nodes = syntax_node.children()
      let mut proj_idx = 0
      for elem_syn in element_nodes {
        if proj_idx < proj_node.children.length() {
          collect_token_spans(
            source_map,
            elem_syn,
            proj_node.children[proj_idx],
          )
          proj_idx = proj_idx + 1
        }
      }
    }
    // Leaf nodes: no token spans to extract
    _ => ()
  }
}
