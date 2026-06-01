// JSON-specific projection builders.
// Converts CST SyntaxNodes to ProjNode[JsonValue].

///|
using @core {type ProjNode, type NodeId}

///|
/// Convert a SyntaxNode to a ProjNode[JsonValue].
/// Handles RootNode by unwrapping to the single child value.
pub fn syntax_to_proj_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@json.JsonValue] {
  match @json.SyntaxKind::from_raw(node.kind()) {
    RootNode =>
      match node.nth_child(0) {
        Some(child) => syntax_to_proj_node(child, counter)
        None => ProjNode::leaf(Error("empty document"), node, counter)
      }
    ObjectNode => build_object_node(node, counter)
    ArrayNode => build_array_node(node, counter)
    StringValue => {
      let text = node.token_text(@json.StringToken.to_raw())
      let value = if text.length() >= 2 {
        @json.JsonValue::String(parse_json_string(text))
      } else {
        @json.JsonValue::Error("malformed string")
      }
      ProjNode::leaf(value, node, counter)
    }
    NumberValue => {
      let text = node.token_text(@json.NumberToken.to_raw())
      let n = @string.parse_double(text) catch {
        _ =>
          return ProjNode::leaf(
            @json.JsonValue::Error("invalid number: " + text),
            node,
            counter,
          )
      }
      ProjNode::leaf(@json.JsonValue::Number(n), node, counter)
    }
    BoolValue => {
      let value = @json.JsonValue::Bool(
        node.find_token(@json.TrueKeyword.to_raw()) is Some(_),
      )
      ProjNode::leaf(value, node, counter)
    }
    NullValue => ProjNode::leaf(@json.JsonValue::Null, node, counter)
    ErrorNode =>
      ProjNode::leaf(@json.JsonValue::Error("parse error"), node, counter)
    _ =>
      ProjNode::leaf(
        @json.JsonValue::Error(
          "unknown node: " + @json.SyntaxKind::from_raw(node.kind()).to_string(),
        ),
        node,
        counter,
      )
  }
}

///|
/// Build a ProjNode for an ObjectNode.
/// Each child ProjNode uses the MemberNode's span (not just the value span)
/// so that delete operations can remove the full "key: value" text.
fn build_object_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@json.JsonValue] {
  let children : Array[ProjNode[@json.JsonValue]] = []
  let members : Array[(String, @json.JsonValue)] = []
  for child in node.children() {
    if @json.SyntaxKind::from_raw(child.kind()) is MemberNode {
      let (key, value_proj) = extract_member(child, counter)
      // Use value span for the child ProjNode (not member span).
      // The full member span (key + colon + value) is stored separately
      // as a "member:N" token span on the Object for delete operations.
      let member_proj = ProjNode::branch(
        value_proj.kind,
        value_proj.start,
        value_proj.end,
        value_proj.children,
        counter,
      )
      children.push(member_proj)
      members.push((key, value_proj.kind))
    }
  }
  ProjNode::branch(
    @json.JsonValue::Object(members),
    node.start(),
    node.end(),
    children,
    counter,
  )
}

///|
/// Build a ProjNode for an ArrayNode.
fn build_array_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@json.JsonValue] {
  let children : Array[ProjNode[@json.JsonValue]] = []
  let elements : Array[@json.JsonValue] = []
  for child in node.children() {
    let child_proj = syntax_to_proj_node(child, counter)
    children.push(child_proj)
    elements.push(child_proj.kind)
  }
  ProjNode::branch(
    @json.JsonValue::Array(elements),
    node.start(),
    node.end(),
    children,
    counter,
  )
}

///|
/// Extract key and value ProjNode from a MemberNode.
/// Key comes from the first StringToken in all_children(),
/// value comes from nth_child(0) (first node child).
fn extract_member(
  member_node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> (String, ProjNode[@json.JsonValue]) {
  // Extract key from the first StringToken (direct child only)
  let mut key_text = ""
  for elem in member_node.all_children() {
    if elem is @seam.SyntaxElement::Token(t) &&
      t.kind() == @json.StringToken.to_raw() {
      key_text = parse_json_string(t.text())
      break
    }
  }
  // Extract value from first node child
  let value_proj = match member_node.nth_child(0) {
    Some(v) => syntax_to_proj_node(v, counter)
    None =>
      ProjNode::leaf(
        @json.JsonValue::Error("missing member value"),
        member_node,
        counter,
      )
  }
  (key_text, value_proj)
}

///|
/// Parse text and return a ProjNode tree with any diagnostic errors.
pub fn parse_to_proj_node(
  text : String,
) -> (ProjNode[@json.JsonValue], Array[String]) raise @loomcore.LexError {
  let (cst, diagnostics) = @json.parse_cst(text)
  let syntax_node = @seam.SyntaxNode::from_cst(cst)
  let errors = diagnostics.map(fn(d) { d.message })
  let root = syntax_to_proj_node(syntax_node, Ref(0))
  (root, errors)
}

///|
/// Memo builder for JSON projection pipeline.
/// Returns 3 memos (no FlatProj) for SyncEditor::new_generic.
pub fn build_json_projection_memos(
  parser : @loom.Parser[@json.JsonValue],
) -> (
  @incr.Derived[ProjNode[@json.JsonValue]?],
  @incr.Derived[Map[NodeId, ProjNode[@json.JsonValue]]],
  @incr.Derived[SourceMap],
) {
  @core.build_projection_memos(
    parser.runtime(),
    parser.syntax_tree(),
    syntax_to_proj_node,
    populate_token_spans,
    label="json",
  )
}
