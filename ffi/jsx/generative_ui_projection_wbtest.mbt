///|
fn special_texts() -> Array[String] {
  [
    "<tag>{value} &amp;lt; &amp;amp; \"quoted\" 'single' 世界", "< > { } & \" ' \u{1F642}",
  ]
}

///|
fn projection_test_capabilities() -> @cognition.GenerativeUiHostCapabilities {
  @cognition.GenerativeUiHostCapabilities::GenerativeUiHostCapabilities(
    bindings=[
      @cognition.GenerativeUiBindingCapabilities::GenerativeUiBindingCapabilities(
        name="orders",
        fields=["name", "amount"],
        selection_keys=["id"],
      ),
    ],
    filter_operators=[@cognition.GenerativeUiFilterOperator::Contains],
    aggregations=[@cognition.GenerativeUiAggregation::Count],
  )
}

///|
fn projection_test_candidate(
  raw : @cognition.GenerativeUiRawNode,
) -> @cognition.GenerativeUiCandidate {
  match
    @cognition.GenerativeUiCandidate::validate(
      raw~,
      capabilities=projection_test_capabilities(),
    ) {
    Ok(candidate) => candidate
    Err(_) => abort("projection fixture must validate")
  }
}

///|
fn special_text_candidate() -> @cognition.GenerativeUiCandidate {
  projection_test_candidate(
    @cognition.GenerativeUiRawNode::Component(
      name="stack",
      attributes=[],
      children=special_texts().map(value => {
        @cognition.GenerativeUiRawNode::Text(value~)
      }),
    ),
  )
}

///|
fn metadata_candidate() -> @cognition.GenerativeUiCandidate {
  projection_test_candidate(
    @cognition.GenerativeUiRawNode::Component(name="stack", attributes=[], children=[
      @cognition.GenerativeUiRawNode::Component(
        name="table",
        attributes=[
          @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
            name="data",
            value="orders",
          ),
          @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
            name="selection",
            value="id",
          ),
        ],
        children=[
          @cognition.GenerativeUiRawNode::Component(
            name="column",
            attributes=[
              @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
                name="field",
                value="name",
              ),
              @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
                name="label",
                value="&amp;lt; &amp;amp; \"世界\"",
              ),
            ],
            children=[],
          ),
          @cognition.GenerativeUiRawNode::Component(
            name="filter",
            attributes=[
              @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
                name="field",
                value="name",
              ),
              @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
                name="operator",
                value="contains",
              ),
            ],
            children=[],
          ),
          @cognition.GenerativeUiRawNode::Component(
            name="summary",
            attributes=[
              @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
                name="field",
                value="amount",
              ),
              @cognition.GenerativeUiRawAttribute::GenerativeUiRawAttribute(
                name="aggregation",
                value="count",
              ),
            ],
            children=[],
          ),
        ],
      ),
    ]),
  )
}

///|
fn projection_ids(node : @canopy_core.ProjNode[@jsx_ast.JsxNode]) -> Array[Int] {
  [node.node_id, ..node.children.map(projection_ids).flatten()]
}

///|
fn projection_texts(
  node : @canopy_core.ProjNode[@jsx_ast.JsxNode],
) -> Array[String] {
  let own_texts = match node.kind {
    @jsx_ast.JsxNode::Text(value) => [value]
    _ => []
  }
  [..own_texts, ..node.children.map(projection_texts).flatten()]
}

///|
fn projection_string_attributes(
  node : @canopy_core.ProjNode[@jsx_ast.JsxNode],
) -> Array[(String, String)] {
  let own_attributes = match node.kind {
    @jsx_ast.JsxNode::Element(attrs~, ..) =>
      attrs.map(attr => {
        match attr.value {
          @jsx_ast.JsxAttrValue::StringLit(value) => (attr.name, value)
          _ => abort("candidate projection must only contain string attributes")
        }
      })
    _ => []
  }
  [
    ..own_attributes,
    ..node.children.map(projection_string_attributes).flatten(),
  ]
}

///|
fn projection_ids_are_valid(
  node : @canopy_core.ProjNode[@jsx_ast.JsxNode],
) -> Bool {
  let ids = projection_ids(node)
  node.node_id == 0 &&
  ids.count(0) == 1 &&
  !ids.contains(-1) &&
  ids.all(id => id == 0 || (id >= -1025 && id <= -2)) &&
  ids.all(id => ids.count(id) == 1)
}

///|
fn raw_texts(node : @cognition.GenerativeUiRawNode) -> Array[String] {
  match node {
    @cognition.GenerativeUiRawNode::Component(children~, ..) =>
      node_children_texts(children)
    @cognition.GenerativeUiRawNode::Text(value~) => [value]
    @cognition.GenerativeUiRawNode::RawHtml(..)
    | @cognition.GenerativeUiRawNode::Expression(..) => []
  }
}

///|
fn node_children_texts(
  children : Array[@cognition.GenerativeUiRawNode],
) -> Array[String] {
  children.map(raw_texts).flatten()
}

///|
struct ProjectionCandidateCase {
  raw : @cognition.GenerativeUiRawNode
} derive(Debug)

///|
impl @quickcheck.Arbitrary for ProjectionCandidateCase with fn arbitrary(
  size,
  rs,
) {
  let depth = if size < 1 { 1 } else if size > 4 { 4 } else { size }
  { raw: generate_projection_raw_node(rs, depth) }
}

///|
impl @qc.Shrink for ProjectionCandidateCase

///|
fn generate_projection_raw_node(
  rs : @splitmix.RandomState,
  depth : Int,
) -> @cognition.GenerativeUiRawNode {
  let token = rs.split().next_positive_int() % special_texts().length()
  let text = special_texts()[token]
  if depth <= 1 || rs.split().next_positive_int() % 3 == 0 {
    @cognition.GenerativeUiRawNode::Text(value=text)
  } else {
    let child_count = rs.split().next_positive_int() % 4
    let children : Array[@cognition.GenerativeUiRawNode] = [
      for _ in 0..<child_count => {
        generate_projection_raw_node(rs.split(), depth - 1)
      }
    ]
    @cognition.GenerativeUiRawNode::Component(
      name=if token % 2 == 0 { "stack" } else { "panel" },
      attributes=[],
      children~,
    )
  }
}

///|
fn prop_candidate_projection_preserves_validated_text(
  case : ProjectionCandidateCase,
) -> Bool {
  let expected_texts = raw_texts(case.raw)
  let candidate = projection_test_candidate(case.raw)
  let projection = candidate_to_projection(candidate)
  projection_texts(projection) == expected_texts &&
  projection_ids_are_valid(projection)
}

///|
test "candidate projection preserves JSX-significant text exactly" {
  let projection = candidate_to_projection(special_text_candidate())
  assert_true(projection_texts(projection) == special_texts())
  assert_true(projection_ids_are_valid(projection))
}

///|
test "candidate projection keeps metadata in one-pass escaped transport" {
  let projection = candidate_to_projection(metadata_candidate())
  let attributes = projection_string_attributes(projection)
  assert_true(
    attributes.contains(
      ("data-genui-label", "&amp;amp;lt; &amp;amp;amp; &quot;世界&quot;"),
    ),
  )
  assert_true(attributes.contains(("data-genui-kind", "table")))
  assert_true(attributes.contains(("data-genui-operator", "contains")))
  assert_true(attributes.contains(("data-genui-aggregation", "count")))
}

///|
test "property: candidate projection preserves text and reserves synthetic IDs" {
  @qc.quick_check_fn(prop_candidate_projection_preserves_validated_text)
}
