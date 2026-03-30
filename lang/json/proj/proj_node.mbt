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
        None =>
          ProjNode::new(
            Error("empty document"),
            node.start(),
            node.end(),
            @core.next_proj_node_id(counter),
            [],
          )
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
      ProjNode::new(
        value,
        node.start(),
        node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
    }
    NumberValue => {
      let text = node.token_text(@json.NumberToken.to_raw())
      let n = @string.parse_double(text) catch {
        _ => {
          let value = @json.JsonValue::Error("invalid number: " + text)
          return ProjNode::new(
            value,
            node.start(),
            node.end(),
            @core.next_proj_node_id(counter),
            [],
          )
        }
      }
      ProjNode::new(
        @json.JsonValue::Number(n),
        node.start(),
        node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
    }
    BoolValue => {
      let value = match node.find_token(@json.TrueKeyword.to_raw()) {
        Some(_) => @json.JsonValue::Bool(true)
        None => @json.JsonValue::Bool(false)
      }
      ProjNode::new(
        value,
        node.start(),
        node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
    }
    NullValue =>
      ProjNode::new(
        @json.JsonValue::Null,
        node.start(),
        node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
    ErrorNode =>
      ProjNode::new(
        @json.JsonValue::Error("parse error"),
        node.start(),
        node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
    _ =>
      ProjNode::new(
        @json.JsonValue::Error(
          "unknown node: " + @json.SyntaxKind::from_raw(node.kind()).to_string(),
        ),
        node.start(),
        node.end(),
        @core.next_proj_node_id(counter),
        [],
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
    match @json.SyntaxKind::from_raw(child.kind()) {
      MemberNode => {
        let (key, value_proj) = extract_member(child, counter)
        // Use value span for the child ProjNode (not member span).
        // The full member span (key + colon + value) is stored separately
        // as a "member:N" token span on the Object for delete operations.
        let member_proj = ProjNode::new(
          value_proj.kind,
          value_proj.start,
          value_proj.end,
          @core.next_proj_node_id(counter),
          value_proj.children,
        )
        children.push(member_proj)
        members.push((key, value_proj.kind))
      }
      _ => ()
    }
  }
  ProjNode::new(
    @json.JsonValue::Object(members),
    node.start(),
    node.end(),
    @core.next_proj_node_id(counter),
    children,
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
  ProjNode::new(
    @json.JsonValue::Array(elements),
    node.start(),
    node.end(),
    @core.next_proj_node_id(counter),
    children,
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
    match elem {
      @seam.SyntaxElement::Token(t) =>
        if t.kind() == @json.StringToken.to_raw() {
          key_text = parse_json_string(t.text())
          break
        }
      _ => ()
    }
  }
  // Extract value from first node child
  let value_proj = match member_node.nth_child(0) {
    Some(v) => syntax_to_proj_node(v, counter)
    None =>
      ProjNode::new(
        @json.JsonValue::Error("missing member value"),
        member_node.start(),
        member_node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
  }
  (key_text, value_proj)
}

///|
/// Parse text and return a ProjNode tree with any diagnostic errors.
pub fn parse_to_proj_node(
  text : String,
) -> (ProjNode[@json.JsonValue], Array[String]) {
  let (cst, diagnostics) = @json.parse_cst(text) catch {
    _ => abort("parse failed")
  }
  let syntax_node = @seam.SyntaxNode::from_cst(cst)
  let errors = diagnostics.map(fn(d) { d.message })
  let root = syntax_to_proj_node(syntax_node, Ref::new(0))
  (root, errors)
}
