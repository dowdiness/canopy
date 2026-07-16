///|
fn candidate_test_attribute(
  name : String,
  value : String,
) -> GenerativeUiRawAttribute {
  GenerativeUiRawAttribute::GenerativeUiRawAttribute(name~, value~)
}

///|
fn candidate_test_capabilities() -> GenerativeUiHostCapabilities {
  GenerativeUiHostCapabilities::GenerativeUiHostCapabilities(
    bindings=[
      GenerativeUiBindingCapabilities::GenerativeUiBindingCapabilities(
        name="orders",
        fields=["status", "amount"],
        selection_keys=["order_id"],
      ),
    ],
    filter_operators=[
      GenerativeUiFilterOperator::Equal,
      GenerativeUiFilterOperator::Contains,
    ],
    aggregations=[GenerativeUiAggregation::Count, GenerativeUiAggregation::Sum],
  )
}

///|
fn candidate_test_scoped_capabilities() -> GenerativeUiHostCapabilities {
  GenerativeUiHostCapabilities::GenerativeUiHostCapabilities(
    bindings=[
      GenerativeUiBindingCapabilities::GenerativeUiBindingCapabilities(
        name="orders",
        fields=["status", "amount"],
        selection_keys=["order_id"],
      ),
      GenerativeUiBindingCapabilities::GenerativeUiBindingCapabilities(
        name="users",
        fields=["name"],
        selection_keys=["user_id"],
      ),
    ],
    filter_operators=[
      GenerativeUiFilterOperator::Equal,
      GenerativeUiFilterOperator::Contains,
    ],
    aggregations=[GenerativeUiAggregation::Count, GenerativeUiAggregation::Sum],
  )
}

///|
fn candidate_diagnostics_contain(
  diagnostics : Array[GenerativeUiDiagnostic],
  expected : GenerativeUiDiagnosticKind,
) -> Bool {
  diagnostics.iter().any(fn(diagnostic) { diagnostic.kind() == expected })
}

///|
test "candidate validation builds an allowlisted declarative tree" {
  let raw = GenerativeUiRawNode::Component(
    name="table",
    attributes=[
      candidate_test_attribute("data", "orders"),
      candidate_test_attribute("selection", "order_id"),
    ],
    children=[
      GenerativeUiRawNode::Component(
        name="column",
        attributes=[
          candidate_test_attribute("field", "status"),
          candidate_test_attribute("label", "Status"),
        ],
        children=[],
      ),
      GenerativeUiRawNode::Component(
        name="filter",
        attributes=[
          candidate_test_attribute("field", "status"),
          candidate_test_attribute("operator", "contains"),
        ],
        children=[],
      ),
      GenerativeUiRawNode::Component(
        name="summary",
        attributes=[
          candidate_test_attribute("field", "amount"),
          candidate_test_attribute("aggregation", "sum"),
        ],
        children=[],
      ),
    ],
  )
  match
    GenerativeUiCandidate::validate(
      raw~,
      capabilities=candidate_test_capabilities(),
    ) {
    Ok(candidate) => {
      match candidate.root() {
        GenerativeUiCandidateNode::Table(binding~, selection_key~, children~) => {
          inspect(binding.to_string(), content="orders")
          match selection_key {
            Some(key) => inspect(key.to_string(), content="order_id")
            None => fail("expected selection key")
          }
          inspect(children.length(), content="3")
        }
        _ => fail("expected table candidate")
      }
      let exposed = candidate.root()
      match exposed {
        GenerativeUiCandidateNode::Table(binding~, selection_key~, children~) => {
          let _ = binding
          let _ = selection_key
          children.push(GenerativeUiCandidateNode::Text(value="mutated"))
        }
        _ => fail("expected table candidate copy")
      }
      match candidate.root() {
        GenerativeUiCandidateNode::Table(binding~, selection_key~, children~) => {
          let _ = binding
          let _ = selection_key
          inspect(children.length(), content="3")
        }
        _ => fail("expected stable table candidate")
      }
    }
    Err(_) => fail("expected candidate validation to succeed")
  }
}

///|
test "candidate validation rejects raw html and arbitrary expressions" {
  let capabilities = candidate_test_capabilities()
  match
    GenerativeUiCandidate::validate(
      raw=GenerativeUiRawNode::RawHtml(value="<script>alert(1)</script>"),
      capabilities~,
    ) {
    Ok(_) => fail("raw HTML must be rejected")
    Err(diagnostics) =>
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::RawHtml,
        ),
        content="true",
      )
  }
  match
    GenerativeUiCandidate::validate(
      raw=GenerativeUiRawNode::Expression(value="host.runAction()"),
      capabilities~,
    ) {
    Ok(_) => fail("arbitrary expressions must be rejected")
    Err(diagnostics) =>
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::ArbitraryExpression,
        ),
        content="true",
      )
  }
}

///|
test "candidate validation enforces component and capability allowlists" {
  let capabilities = candidate_test_capabilities()
  match
    GenerativeUiCandidate::validate(
      raw=GenerativeUiRawNode::Component(name="script", attributes=[], children=[]),
      capabilities~,
    ) {
    Ok(_) => fail("unknown component must be rejected")
    Err(diagnostics) =>
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::UnknownComponent,
        ),
        content="true",
      )
  }

  let disallowed = GenerativeUiRawNode::Component(
    name="table",
    attributes=[
      candidate_test_attribute("data", "users"),
      candidate_test_attribute("selection", "user_id"),
    ],
    children=[
      GenerativeUiRawNode::Component(
        name="filter",
        attributes=[
          candidate_test_attribute("field", "status"),
          candidate_test_attribute("operator", "gt"),
        ],
        children=[],
      ),
      GenerativeUiRawNode::Component(
        name="summary",
        attributes=[
          candidate_test_attribute("field", "amount"),
          candidate_test_attribute("aggregation", "average"),
        ],
        children=[],
      ),
    ],
  )
  match GenerativeUiCandidate::validate(raw=disallowed, capabilities~) {
    Ok(_) => fail("disallowed host capabilities must be rejected")
    Err(diagnostics) => {
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::DisallowedBinding,
        ),
        content="true",
      )
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::DisallowedSelectionKey,
        ),
        content="true",
      )
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::DisallowedFilterOperator,
        ),
        content="true",
      )
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::DisallowedAggregation,
        ),
        content="true",
      )
    }
  }
}

///|
test "candidate validation scopes fields and selection keys to a binding" {
  let raw = GenerativeUiRawNode::Component(
    name="table",
    attributes=[
      candidate_test_attribute("data", "orders"),
      candidate_test_attribute("selection", "user_id"),
    ],
    children=[
      GenerativeUiRawNode::Component(
        name="column",
        attributes=[candidate_test_attribute("field", "name")],
        children=[],
      ),
    ],
  )
  match
    GenerativeUiCandidate::validate(
      raw~,
      capabilities=candidate_test_scoped_capabilities(),
    ) {
    Ok(_) => fail("fields and selection keys must stay binding-scoped")
    Err(diagnostics) => {
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::DisallowedBinding,
        ),
        content="true",
      )
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::DisallowedSelectionKey,
        ),
        content="true",
      )
    }
  }
}

///|
test "candidate validation rejects unknown attributes and invalid shapes" {
  let capabilities = candidate_test_capabilities()
  let text_with_unknown_attribute = GenerativeUiRawNode::Component(
    name="text",
    attributes=[
      candidate_test_attribute("value", "hello"),
      candidate_test_attribute("href", "https://example.com"),
    ],
    children=[],
  )
  match
    GenerativeUiCandidate::validate(
      raw=text_with_unknown_attribute,
      capabilities~,
    ) {
    Ok(_) => fail("unknown attributes must be rejected")
    Err(diagnostics) =>
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::UnknownAttribute,
        ),
        content="true",
      )
  }

  match
    GenerativeUiCandidate::validate(
      raw=GenerativeUiRawNode::Component(name="text", attributes=[], children=[]),
      capabilities~,
    ) {
    Ok(_) => fail("missing attributes must be rejected")
    Err(diagnostics) =>
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::MissingAttribute,
        ),
        content="true",
      )
  }

  let orphan_column = GenerativeUiRawNode::Component(
    name="column",
    attributes=[candidate_test_attribute("field", "status")],
    children=[],
  )
  match GenerativeUiCandidate::validate(raw=orphan_column, capabilities~) {
    Ok(_) => fail("column must require a table parent")
    Err(diagnostics) =>
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::InvalidChild,
        ),
        content="true",
      )
  }

  let nested_orphan_column = GenerativeUiRawNode::Component(
    name="stack",
    attributes=[],
    children=[orphan_column],
  )
  match
    GenerativeUiCandidate::validate(raw=nested_orphan_column, capabilities~) {
    Ok(_) => fail("column must not be accepted by a stack")
    Err(diagnostics) =>
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::InvalidChild,
        ),
        content="true",
      )
  }

  let invalid_child = GenerativeUiRawNode::Component(
    name="table",
    attributes=[candidate_test_attribute("data", "orders")],
    children=[GenerativeUiRawNode::Text(value="not a table child")],
  )
  match GenerativeUiCandidate::validate(raw=invalid_child, capabilities~) {
    Ok(_) => fail("invalid table children must be rejected")
    Err(diagnostics) =>
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::InvalidChild,
        ),
        content="true",
      )
  }
}

///|
test "candidate validation rejects duplicate attributes before lookup" {
  let capabilities = candidate_test_capabilities()
  let cases : Array[(String, String, GenerativeUiRawNode)] = [
    (
      "data",
      "root",
      GenerativeUiRawNode::Component(
        name="table",
        attributes=[
          candidate_test_attribute("data", "orders"),
          candidate_test_attribute("data", "orders"),
        ],
        children=[],
      ),
    ),
    (
      "selection",
      "root",
      GenerativeUiRawNode::Component(
        name="table",
        attributes=[
          candidate_test_attribute("data", "orders"),
          candidate_test_attribute("selection", "order_id"),
          candidate_test_attribute("selection", "order_id"),
        ],
        children=[],
      ),
    ),
    (
      "field",
      "root.children[0]",
      GenerativeUiRawNode::Component(
        name="table",
        attributes=[candidate_test_attribute("data", "orders")],
        children=[
          GenerativeUiRawNode::Component(
            name="column",
            attributes=[
              candidate_test_attribute("field", "status"),
              candidate_test_attribute("field", "status"),
            ],
            children=[],
          ),
        ],
      ),
    ),
    (
      "operator",
      "root.children[0]",
      GenerativeUiRawNode::Component(
        name="table",
        attributes=[candidate_test_attribute("data", "orders")],
        children=[
          GenerativeUiRawNode::Component(
            name="filter",
            attributes=[
              candidate_test_attribute("field", "status"),
              candidate_test_attribute("operator", "contains"),
              candidate_test_attribute("operator", "contains"),
            ],
            children=[],
          ),
        ],
      ),
    ),
    (
      "aggregation",
      "root.children[0]",
      GenerativeUiRawNode::Component(
        name="table",
        attributes=[candidate_test_attribute("data", "orders")],
        children=[
          GenerativeUiRawNode::Component(
            name="summary",
            attributes=[
              candidate_test_attribute("field", "amount"),
              candidate_test_attribute("aggregation", "sum"),
              candidate_test_attribute("aggregation", "sum"),
            ],
            children=[],
          ),
        ],
      ),
    ),
    (
      "label",
      "root.children[0]",
      GenerativeUiRawNode::Component(
        name="table",
        attributes=[candidate_test_attribute("data", "orders")],
        children=[
          GenerativeUiRawNode::Component(
            name="column",
            attributes=[
              candidate_test_attribute("field", "status"),
              candidate_test_attribute("label", "Status"),
              candidate_test_attribute("label", "Status"),
            ],
            children=[],
          ),
        ],
      ),
    ),
    (
      "value",
      "root",
      GenerativeUiRawNode::Component(
        name="text",
        attributes=[
          candidate_test_attribute("value", "hello"),
          candidate_test_attribute("value", "hello"),
        ],
        children=[],
      ),
    ),
  ]
  for case in cases {
    let (name, path, raw) = case
    match GenerativeUiCandidate::validate(raw~, capabilities~) {
      Ok(_) => fail("duplicate \{name} must be rejected")
      Err(diagnostics) => {
        guard diagnostics
          .iter()
          .any(diagnostic => {
            diagnostic.kind() ==
            GenerativeUiDiagnosticKind::InvalidAttributeValue &&
            diagnostic.path() == path &&
            diagnostic.detail() == "attribute appears more than once: \{name}"
          }) else {
          fail("duplicate \{name} must report InvalidAttributeValue at \{path}")
        }
      }
    }
  }
}

///|
test "candidate validation enforces resource limits" {
  let capabilities = candidate_test_capabilities()
  let mut too_deep = GenerativeUiRawNode::Text(value="leaf")
  for _ in 0..<40 {
    too_deep = GenerativeUiRawNode::Component(name="stack", attributes=[], children=[
      too_deep,
    ])
  }
  match GenerativeUiCandidate::validate(raw=too_deep, capabilities~) {
    Ok(_) => fail("deep candidates must be rejected")
    Err(diagnostics) =>
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::LimitExceeded,
        ),
        content="true",
      )
  }

  let too_many_attributes : Array[GenerativeUiRawAttribute] = Array::make(
    33,
    candidate_test_attribute("x", "y"),
  )
  let wide_component = GenerativeUiRawNode::Component(
    name="stack",
    attributes=too_many_attributes,
    children=[],
  )
  match GenerativeUiCandidate::validate(raw=wide_component, capabilities~) {
    Ok(_) => fail("wide components must be rejected")
    Err(diagnostics) =>
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::LimitExceeded,
        ),
        content="true",
      )
  }

  let too_many_children : Array[GenerativeUiRawNode] = Array::make(
    1025,
    GenerativeUiRawNode::Text(value="x"),
  )
  let wide_candidate = GenerativeUiRawNode::Component(
    name="stack",
    attributes=[],
    children=too_many_children,
  )
  match GenerativeUiCandidate::validate(raw=wide_candidate, capabilities~) {
    Ok(_) => fail("wide candidates must be rejected")
    Err(diagnostics) =>
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::LimitExceeded,
        ),
        content="true",
      )
  }

  let long_text = GenerativeUiRawNode::Text(value=String::repeat("x", 8193))
  match GenerativeUiCandidate::validate(raw=long_text, capabilities~) {
    Ok(_) => fail("long candidate strings must be rejected")
    Err(diagnostics) =>
      inspect(
        candidate_diagnostics_contain(
          diagnostics,
          GenerativeUiDiagnosticKind::LimitExceeded,
        ),
        content="true",
      )
  }
}
