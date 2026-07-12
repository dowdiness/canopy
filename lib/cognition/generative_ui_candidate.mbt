///|
/// Functional-core input: untrusted structured data with no execution
/// semantics. Validation consumes this value and host capabilities, then
/// returns either a declarative candidate or replayable diagnostics. It does
/// not read the replay cursor, lifecycle, renderer, or external services.
pub(all) enum GenerativeUiRawNode {
  Component(
    name~ : String,
    attributes~ : Array[GenerativeUiRawAttribute],
    children~ : Array[GenerativeUiRawNode]
  )
  Text(value~ : String)
  RawHtml(value~ : String)
  Expression(value~ : String)
} derive(Debug, Eq)

///|
const GENERATIVE_UI_MAX_DEPTH = 32

///|
const GENERATIVE_UI_MAX_NODES = 1024

///|
const GENERATIVE_UI_MAX_ATTRIBUTES = 32

///|
const GENERATIVE_UI_MAX_STRING_LENGTH = 8192

///|
/// Untrusted string attribute attached to a raw component.
pub struct GenerativeUiRawAttribute {
  priv name : String
  priv value : String
} derive(Debug, Eq)

///|
pub fn GenerativeUiRawAttribute::GenerativeUiRawAttribute(
  name~ : String,
  value~ : String,
) -> GenerativeUiRawAttribute {
  { name, value }
}

///|
/// Host-owned data binding referenced by a validated candidate.
pub struct GenerativeUiDataBinding(String) derive(Debug, Eq, Hash, Compare)

///|
pub fn GenerativeUiDataBinding::to_string(
  self : GenerativeUiDataBinding,
) -> String {
  let GenerativeUiDataBinding(value) = self
  value
}

///|
/// Host-owned field referenced by a validated candidate.
pub struct GenerativeUiField(String) derive(Debug, Eq, Hash, Compare)

///|
pub fn GenerativeUiField::to_string(self : GenerativeUiField) -> String {
  let GenerativeUiField(value) = self
  value
}

///|
/// Host-owned selection key referenced by a validated table.
pub struct GenerativeUiSelectionKey(String) derive(Debug, Eq, Hash, Compare)

///|
pub fn GenerativeUiSelectionKey::to_string(
  self : GenerativeUiSelectionKey,
) -> String {
  let GenerativeUiSelectionKey(value) = self
  value
}

///|
pub(all) enum GenerativeUiFilterOperator {
  Equal
  NotEqual
  Contains
  GreaterThan
  LessThan
} derive(Debug, Eq, Hash, Compare)

///|
fn GenerativeUiFilterOperator::from_string(
  value : String,
) -> GenerativeUiFilterOperator? {
  match value {
    "eq" => Some(Equal)
    "neq" => Some(NotEqual)
    "contains" => Some(Contains)
    "gt" => Some(GreaterThan)
    "lt" => Some(LessThan)
    _ => None
  }
}

///|
pub(all) enum GenerativeUiAggregation {
  Count
  Sum
  Average
  Minimum
  Maximum
} derive(Debug, Eq, Hash, Compare)

///|
fn GenerativeUiAggregation::from_string(
  value : String,
) -> GenerativeUiAggregation? {
  match value {
    "count" => Some(Count)
    "sum" => Some(Sum)
    "average" => Some(Average)
    "min" => Some(Minimum)
    "max" => Some(Maximum)
    _ => None
  }
}

///|
/// Capabilities scoped to one host-owned data binding. Fields and selection
/// keys cannot accidentally be combined with a different binding.
pub struct GenerativeUiBindingCapabilities {
  priv name : String
  priv fields : Array[String]
  priv selection_keys : Array[String]
} derive(Debug, Eq)

///|
pub fn GenerativeUiBindingCapabilities::GenerativeUiBindingCapabilities(
  name~ : String,
  fields~ : Array[String],
  selection_keys~ : Array[String],
) -> GenerativeUiBindingCapabilities {
  { name, fields: fields.copy(), selection_keys: selection_keys.copy() }
}

///|
fn GenerativeUiBindingCapabilities::has_field(
  self : GenerativeUiBindingCapabilities,
  field : String,
) -> Bool {
  self.fields.contains(field)
}

///|
fn GenerativeUiBindingCapabilities::has_selection_key(
  self : GenerativeUiBindingCapabilities,
  selection_key : String,
) -> Bool {
  self.selection_keys.contains(selection_key)
}

///|
/// Host-owned capabilities used to validate opaque references in a raw
/// candidate. Empty allowlists intentionally mean "not available".
pub struct GenerativeUiHostCapabilities {
  priv bindings : Array[GenerativeUiBindingCapabilities]
  priv filter_operators : Array[GenerativeUiFilterOperator]
  priv aggregations : Array[GenerativeUiAggregation]
} derive(Debug, Eq)

///|
pub fn GenerativeUiHostCapabilities::GenerativeUiHostCapabilities(
  bindings~ : Array[GenerativeUiBindingCapabilities],
  filter_operators~ : Array[GenerativeUiFilterOperator],
  aggregations~ : Array[GenerativeUiAggregation],
) -> GenerativeUiHostCapabilities {
  {
    bindings: bindings.copy(),
    filter_operators: filter_operators.copy(),
    aggregations: aggregations.copy(),
  }
}

///|
fn GenerativeUiHostCapabilities::binding(
  self : GenerativeUiHostCapabilities,
  name : String,
) -> GenerativeUiBindingCapabilities? {
  self.bindings.iter().find_first(binding => binding.name == name)
}

///|
/// Validated declarative UI program. These variants carry no executable
/// expressions, URLs, actions, or candidate-owned interaction state.
pub(all) enum GenerativeUiCandidateNode {
  Stack(children~ : Array[GenerativeUiCandidateNode])
  Panel(children~ : Array[GenerativeUiCandidateNode])
  Table(
    binding~ : GenerativeUiDataBinding,
    selection_key~ : GenerativeUiSelectionKey?,
    children~ : Array[GenerativeUiCandidateNode]
  )
  Column(field~ : GenerativeUiField, label~ : String?)
  Filter(field~ : GenerativeUiField, operator~ : GenerativeUiFilterOperator)
  Text(value~ : String)
  Summary(field~ : GenerativeUiField, aggregation~ : GenerativeUiAggregation)
} derive(Debug, Eq)

///|
enum GenerativeUiCandidateContext {
  Container
  Table
} derive(Eq)

///|
/// Opaque validated candidate passed to the later renderer adapter.
pub struct GenerativeUiCandidate {
  priv root : GenerativeUiCandidateNode
}

///|
fn GenerativeUiCandidate::GenerativeUiCandidate(
  root : GenerativeUiCandidateNode,
) -> GenerativeUiCandidate {
  { root, }
}

///|
/// Return an isolated view for a renderer adapter. The candidate keeps its
/// validated tree private so shell-side mutation cannot invalidate it.
pub fn GenerativeUiCandidate::root(
  self : GenerativeUiCandidate,
) -> GenerativeUiCandidateNode {
  self.root.copy()
}

///|
pub(all) enum GenerativeUiDiagnosticKind {
  UnknownComponent
  UnknownAttribute
  MissingAttribute
  InvalidAttributeValue
  DisallowedBinding
  DisallowedSelectionKey
  DisallowedFilterOperator
  DisallowedAggregation
  RawHtml
  ArbitraryExpression
  InvalidChild
  UnexpectedChildren
  LimitExceeded
} derive(Debug, Eq, Hash, Compare)

///|
/// Replayable structured diagnostic emitted by candidate validation.
pub struct GenerativeUiDiagnostic {
  priv path : String
  priv kind : GenerativeUiDiagnosticKind
  priv detail : String
} derive(Debug, Eq)

///|
pub fn GenerativeUiDiagnostic::path(self : GenerativeUiDiagnostic) -> String {
  self.path
}

///|
pub fn GenerativeUiDiagnostic::kind(
  self : GenerativeUiDiagnostic,
) -> GenerativeUiDiagnosticKind {
  self.kind
}

///|
pub fn GenerativeUiDiagnostic::detail(self : GenerativeUiDiagnostic) -> String {
  self.detail
}

///|
/// Validate an untrusted raw candidate against host-owned allowlists.
pub fn GenerativeUiCandidate::validate(
  raw~ : GenerativeUiRawNode,
  capabilities~ : GenerativeUiHostCapabilities,
) -> Result[GenerativeUiCandidate, Array[GenerativeUiDiagnostic]] {
  match validate_candidate_limits(raw) {
    Err(diagnostic) => Err([diagnostic])
    Ok(_) =>
      match
        validate_candidate_node(raw, "root", capabilities, Container, None) {
        Ok(root) => Ok(GenerativeUiCandidate(root))
        Err(diagnostics) => Err(diagnostics)
      }
  }
}

///|
fn diagnostic(
  path : String,
  kind : GenerativeUiDiagnosticKind,
  detail : String,
) -> GenerativeUiDiagnostic {
  { path, kind, detail }
}

///|
fn validate_candidate_limits(
  raw : GenerativeUiRawNode,
) -> Result[Unit, GenerativeUiDiagnostic] {
  match validate_candidate_limits_node(raw, "root", 0, 0) {
    Ok(_) => Ok(())
    Err(diagnostic) => Err(diagnostic)
  }
}

///|
fn validate_candidate_limits_node(
  node : GenerativeUiRawNode,
  path : String,
  depth : Int,
  nodes : Int,
) -> Result[Int, GenerativeUiDiagnostic] {
  if depth > GENERATIVE_UI_MAX_DEPTH {
    return Err(
      diagnostic(
        path,
        LimitExceeded,
        "candidate nesting exceeds the validation limit",
      ),
    )
  }
  let next_nodes = nodes + 1
  if next_nodes > GENERATIVE_UI_MAX_NODES {
    return Err(
      diagnostic(
        path,
        LimitExceeded,
        "candidate node count exceeds the validation limit",
      ),
    )
  }
  match node {
    Text(value~) =>
      match validate_candidate_string_limit(value, path) {
        Ok(_) => Ok(next_nodes)
        Err(error) => Err(error)
      }
    RawHtml(value~) =>
      match validate_candidate_string_limit(value, path) {
        Ok(_) => Ok(next_nodes)
        Err(error) => Err(error)
      }
    Expression(value~) =>
      match validate_candidate_string_limit(value, path) {
        Ok(_) => Ok(next_nodes)
        Err(error) => Err(error)
      }
    Component(name~, attributes~, children~) => {
      match validate_candidate_string_limit(name, path) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      if attributes.length() > GENERATIVE_UI_MAX_ATTRIBUTES {
        return Err(
          diagnostic(
            path,
            LimitExceeded,
            "component attribute count exceeds the validation limit",
          ),
        )
      }
      for index, attribute in attributes {
        match
          validate_candidate_string_limit(
            attribute.name,
            "\{path}.attributes[\{index}].name",
          ) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        match
          validate_candidate_string_limit(
            attribute.value,
            "\{path}.attributes[\{index}].value",
          ) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
      }
      let initial_state : (Int, GenerativeUiDiagnostic?) = (next_nodes, None)
      let (node_count, failure) = for
        index, child in children
        state = initial_state
        state = advance_candidate_limit(child, path, depth, index, state) {
        match state {
          (_, Some(_)) => break state
          (_, None) => ()
        }
      } nobreak {
        state
      }
      match failure {
        Some(error) => Err(error)
        None => Ok(node_count)
      }
    }
  }
}

///|
/// The pair carries local traversal state; no mutation escapes the core.
fn advance_candidate_limit(
  child : GenerativeUiRawNode,
  path : String,
  depth : Int,
  index : Int,
  state : (Int, GenerativeUiDiagnostic?),
) -> (Int, GenerativeUiDiagnostic?) {
  let (node_count, failure) = state
  match failure {
    Some(_) => state
    None =>
      match
        validate_candidate_limits_node(
          child,
          child_path(path, index),
          depth + 1,
          node_count,
        ) {
        Ok(updated_count) => (updated_count, None)
        Err(error) => (node_count, Some(error))
      }
  }
}

///|
fn validate_candidate_string_limit(
  value : String,
  path : String,
) -> Result[Unit, GenerativeUiDiagnostic] {
  if value.length() > GENERATIVE_UI_MAX_STRING_LENGTH {
    return Err(
      diagnostic(
        path,
        LimitExceeded,
        "candidate string length exceeds the validation limit",
      ),
    )
  }
  Ok(())
}

///|
fn GenerativeUiCandidateNode::copy(
  self : GenerativeUiCandidateNode,
) -> GenerativeUiCandidateNode {
  match self {
    Stack(children~) => Stack(children=children.map(child => child.copy()))
    Panel(children~) => Panel(children=children.map(child => child.copy()))
    Table(binding~, selection_key~, children~) =>
      Table(
        binding~,
        selection_key~,
        children=children.map(child => child.copy()),
      )
    Column(field~, label~) => Column(field~, label~)
    Filter(field~, operator~) => Filter(field~, operator~)
    Text(value~) => Text(value~)
    Summary(field~, aggregation~) => Summary(field~, aggregation~)
  }
}

///|
fn validate_candidate_node(
  node : GenerativeUiRawNode,
  path : String,
  capabilities : GenerativeUiHostCapabilities,
  context : GenerativeUiCandidateContext,
  binding_context : GenerativeUiBindingCapabilities?,
) -> Result[GenerativeUiCandidateNode, Array[GenerativeUiDiagnostic]] {
  match node {
    Text(value~) =>
      match context {
        Container => Ok(Text(value~))
        Table =>
          Err([
            diagnostic(
              path,
              InvalidChild,
              "table accepts only column, filter, and summary",
            ),
          ])
      }
    RawHtml(_) => Err([diagnostic(path, RawHtml, "raw HTML is not allowed")])
    Expression(_) =>
      Err([diagnostic(path, ArbitraryExpression, "expressions are not allowed")])
    Component(name~, attributes~, children~) =>
      validate_component(
        name, attributes, children, path, capabilities, context, binding_context,
      )
  }
}

///|
fn validate_component(
  name : String,
  attributes : Array[GenerativeUiRawAttribute],
  children : Array[GenerativeUiRawNode],
  path : String,
  capabilities : GenerativeUiHostCapabilities,
  context : GenerativeUiCandidateContext,
  binding_context : GenerativeUiBindingCapabilities?,
) -> Result[GenerativeUiCandidateNode, Array[GenerativeUiDiagnostic]] {
  let invalid_context = match context {
    Container =>
      match name {
        "column" | "filter" | "summary" => true
        _ => false
      }
    Table =>
      match name {
        "column" | "filter" | "summary" => false
        "stack" | "panel" | "table" | "text" => true
        _ => false
      }
  }
  if invalid_context {
    return Err([
      diagnostic(
        path,
        InvalidChild,
        "table accepts only column, filter, and summary",
      ),
    ])
  }
  match name {
    "stack" => {
      let diagnostics = attribute_diagnostics(attributes, [], path)
      let (validated_children, child_diagnostics) = validate_children(
        children,
        path,
        capabilities,
        Container,
        None,
      )
      diagnostics.append(child_diagnostics)
      if diagnostics.is_empty() {
        Ok(Stack(children=validated_children))
      } else {
        Err(diagnostics)
      }
    }
    "panel" => {
      let diagnostics = attribute_diagnostics(attributes, [], path)
      let (validated_children, child_diagnostics) = validate_children(
        children,
        path,
        capabilities,
        Container,
        None,
      )
      diagnostics.append(child_diagnostics)
      if diagnostics.is_empty() {
        Ok(Panel(children=validated_children))
      } else {
        Err(diagnostics)
      }
    }
    "table" => validate_table(attributes, children, path, capabilities)
    "column" => validate_column(attributes, children, path, binding_context)
    "filter" =>
      validate_filter(attributes, children, path, capabilities, binding_context)
    "text" => validate_text(attributes, children, path)
    "summary" =>
      validate_summary(
        attributes, children, path, capabilities, binding_context,
      )
    _ =>
      Err([
        diagnostic(
          path,
          UnknownComponent,
          "component is not in the Generative UI allowlist",
        ),
      ])
  }
}

///|
fn validate_table(
  attributes : Array[GenerativeUiRawAttribute],
  children : Array[GenerativeUiRawNode],
  path : String,
  capabilities : GenerativeUiHostCapabilities,
) -> Result[GenerativeUiCandidateNode, Array[GenerativeUiDiagnostic]] {
  let diagnostics = attribute_diagnostics(
    attributes,
    ["data", "selection"],
    path,
  )
  let (binding, binding_context) = match attribute_value(attributes, "data") {
    Some(value) =>
      match capabilities.binding(value) {
        Some(context) => (Some(GenerativeUiDataBinding(value)), Some(context))
        None => {
          diagnostics.push(
            diagnostic(path, DisallowedBinding, "data binding is not available"),
          )
          (None, None)
        }
      }
    None => {
      diagnostics.push(
        diagnostic(path, MissingAttribute, "table requires data"),
      )
      (None, None)
    }
  }
  let selection_key = match attribute_value(attributes, "selection") {
    Some(value) =>
      match binding_context {
        Some(context) if context.has_selection_key(value) =>
          Some(GenerativeUiSelectionKey(value))
        _ => {
          diagnostics.push(
            diagnostic(
              path,
              DisallowedSelectionKey,
              "selection key is not available for this data binding",
            ),
          )
          None
        }
      }
    None => None
  }
  let (validated_children, child_diagnostics) = validate_children(
    children,
    path,
    capabilities,
    Table,
    binding_context,
  )
  diagnostics.append(child_diagnostics)
  if diagnostics.is_empty() {
    Ok(
      Table(
        binding=binding.unwrap(),
        selection_key~,
        children=validated_children,
      ),
    )
  } else {
    Err(diagnostics)
  }
}

///|
fn validate_column(
  attributes : Array[GenerativeUiRawAttribute],
  children : Array[GenerativeUiRawNode],
  path : String,
  binding_context : GenerativeUiBindingCapabilities?,
) -> Result[GenerativeUiCandidateNode, Array[GenerativeUiDiagnostic]] {
  let diagnostics = attribute_diagnostics(attributes, ["field", "label"], path)
  if !children.is_empty() {
    diagnostics.push(
      diagnostic(path, UnexpectedChildren, "column cannot have children"),
    )
  }
  let field = match attribute_value(attributes, "field") {
    Some(value) => {
      let field_allowed = match binding_context {
        Some(context) => context.has_field(value)
        None => false
      }
      if !field_allowed {
        diagnostics.push(
          diagnostic(path, DisallowedBinding, "field is not available"),
        )
      }
      Some(GenerativeUiField(value))
    }
    None => {
      diagnostics.push(
        diagnostic(path, MissingAttribute, "column requires field"),
      )
      None
    }
  }
  let label = attribute_value(attributes, "label")
  if diagnostics.is_empty() {
    Ok(Column(field=field.unwrap(), label~))
  } else {
    Err(diagnostics)
  }
}

///|
fn validate_filter(
  attributes : Array[GenerativeUiRawAttribute],
  children : Array[GenerativeUiRawNode],
  path : String,
  capabilities : GenerativeUiHostCapabilities,
  binding_context : GenerativeUiBindingCapabilities?,
) -> Result[GenerativeUiCandidateNode, Array[GenerativeUiDiagnostic]] {
  let diagnostics = attribute_diagnostics(
    attributes,
    ["field", "operator"],
    path,
  )
  if !children.is_empty() {
    diagnostics.push(
      diagnostic(path, UnexpectedChildren, "filter cannot have children"),
    )
  }
  let field = match attribute_value(attributes, "field") {
    Some(value) => {
      let field_allowed = match binding_context {
        Some(context) => context.has_field(value)
        None => false
      }
      if !field_allowed {
        diagnostics.push(
          diagnostic(path, DisallowedBinding, "field is not available"),
        )
      }
      Some(GenerativeUiField(value))
    }
    None => {
      diagnostics.push(
        diagnostic(path, MissingAttribute, "filter requires field"),
      )
      None
    }
  }
  let operator = match attribute_value(attributes, "operator") {
    Some(value) =>
      match GenerativeUiFilterOperator::from_string(value) {
        Some(value) if capabilities.filter_operators.contains(value) =>
          Some(value)
        Some(_) => {
          diagnostics.push(
            diagnostic(
              path,
              DisallowedFilterOperator,
              "filter operator is not available",
            ),
          )
          None
        }
        None => {
          diagnostics.push(
            diagnostic(path, InvalidAttributeValue, "unknown filter operator"),
          )
          None
        }
      }
    None => {
      diagnostics.push(
        diagnostic(path, MissingAttribute, "filter requires operator"),
      )
      None
    }
  }
  if diagnostics.is_empty() {
    Ok(Filter(field=field.unwrap(), operator=operator.unwrap()))
  } else {
    Err(diagnostics)
  }
}

///|
fn validate_text(
  attributes : Array[GenerativeUiRawAttribute],
  children : Array[GenerativeUiRawNode],
  path : String,
) -> Result[GenerativeUiCandidateNode, Array[GenerativeUiDiagnostic]] {
  let diagnostics = attribute_diagnostics(attributes, ["value"], path)
  if !children.is_empty() {
    diagnostics.push(
      diagnostic(path, UnexpectedChildren, "text cannot have children"),
    )
  }
  match attribute_value(attributes, "value") {
    Some(value) =>
      if diagnostics.is_empty() {
        Ok(Text(value~))
      } else {
        Err(diagnostics)
      }
    None => {
      diagnostics.push(
        diagnostic(path, MissingAttribute, "text requires value"),
      )
      Err(diagnostics)
    }
  }
}

///|
fn validate_summary(
  attributes : Array[GenerativeUiRawAttribute],
  children : Array[GenerativeUiRawNode],
  path : String,
  capabilities : GenerativeUiHostCapabilities,
  binding_context : GenerativeUiBindingCapabilities?,
) -> Result[GenerativeUiCandidateNode, Array[GenerativeUiDiagnostic]] {
  let diagnostics = attribute_diagnostics(
    attributes,
    ["field", "aggregation"],
    path,
  )
  if !children.is_empty() {
    diagnostics.push(
      diagnostic(path, UnexpectedChildren, "summary cannot have children"),
    )
  }
  let field = match attribute_value(attributes, "field") {
    Some(value) => {
      let field_allowed = match binding_context {
        Some(context) => context.has_field(value)
        None => false
      }
      if !field_allowed {
        diagnostics.push(
          diagnostic(path, DisallowedBinding, "field is not available"),
        )
      }
      Some(GenerativeUiField(value))
    }
    None => {
      diagnostics.push(
        diagnostic(path, MissingAttribute, "summary requires field"),
      )
      None
    }
  }
  let aggregation = match attribute_value(attributes, "aggregation") {
    Some(value) =>
      match GenerativeUiAggregation::from_string(value) {
        Some(value) if capabilities.aggregations.contains(value) => Some(value)
        Some(_) => {
          diagnostics.push(
            diagnostic(
              path,
              DisallowedAggregation,
              "summary aggregation is not available",
            ),
          )
          None
        }
        None => {
          diagnostics.push(
            diagnostic(
              path,
              InvalidAttributeValue,
              "unknown summary aggregation",
            ),
          )
          None
        }
      }
    None => {
      diagnostics.push(
        diagnostic(path, MissingAttribute, "summary requires aggregation"),
      )
      None
    }
  }
  if diagnostics.is_empty() {
    Ok(Summary(field=field.unwrap(), aggregation=aggregation.unwrap()))
  } else {
    Err(diagnostics)
  }
}

///|
fn validate_children(
  children : Array[GenerativeUiRawNode],
  path : String,
  capabilities : GenerativeUiHostCapabilities,
  context : GenerativeUiCandidateContext,
  binding_context : GenerativeUiBindingCapabilities?,
) -> (Array[GenerativeUiCandidateNode], Array[GenerativeUiDiagnostic]) {
  let validated : Array[GenerativeUiCandidateNode] = []
  let diagnostics : Array[GenerativeUiDiagnostic] = []
  for index, child in children {
    match
      validate_candidate_node(
        child,
        child_path(path, index),
        capabilities,
        context,
        binding_context,
      ) {
      Ok(node) => validated.push(node)
      Err(child_diagnostics) => diagnostics.append(child_diagnostics)
    }
  }
  (validated, diagnostics)
}

///|
fn attribute_diagnostics(
  attributes : Array[GenerativeUiRawAttribute],
  allowed : Array[String],
  path : String,
) -> Array[GenerativeUiDiagnostic] {
  attributes.filter_map(attr => {
    if allowed.contains(attr.name) {
      None
    } else {
      Some(
        diagnostic(
          path,
          UnknownAttribute,
          "attribute is not allowed: \{attr.name}",
        ),
      )
    }
  })
}

///|
fn attribute_value(
  attributes : Array[GenerativeUiRawAttribute],
  name : String,
) -> String? {
  match attributes.iter().find_first(attr => attr.name == name) {
    Some(attribute) => Some(attribute.value)
    None => None
  }
}

///|
fn child_path(path : String, index : Int) -> String {
  "\{path}.children[\{index}]"
}
