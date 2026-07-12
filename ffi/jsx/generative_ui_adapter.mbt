///|
/// Candidate-to-JSX adapter for the first Generative UI vertical slice.
///
/// This is a deliberately narrow lowering. Candidate-owned values become
/// escaped data attributes, while host-owned data and interaction references
/// remain declarative metadata. No generated value becomes an event handler,
/// URL, expression span, or DOM operation.
fn lower_generative_ui_candidate(
  candidate : @cognition.GenerativeUiCandidate,
) -> Result[String, String] {
  lower_candidate_node(candidate.root())
}

///|
fn lower_candidate_node(
  node : @cognition.GenerativeUiCandidateNode,
) -> Result[String, String] {
  match node {
    Stack(children~) =>
      lower_container("div", [("data-genui-kind", "stack")], children)
    Panel(children~) =>
      lower_container("section", [("data-genui-kind", "panel")], children)
    Table(binding~, selection_key~, children~) => {
      let attrs = [
        ("data-genui-kind", "table"),
        ("data-genui-binding", binding.to_string()),
      ]
      let table_attrs = match selection_key {
        Some(key) => attrs + [("data-genui-selection", key.to_string())]
        None => attrs
      }
      lower_container("div", table_attrs, children)
    }
    Column(field~, label~) => {
      let attrs = [
        ("data-genui-kind", "column"),
        ("data-genui-field", field.to_string()),
      ]
      let column_attrs = match label {
        Some(value) => attrs + [("data-genui-label", value)]
        None => attrs
      }
      lower_leaf("div", column_attrs)
    }
    Filter(field~, operator~) =>
      lower_leaf("div", [
        ("data-genui-kind", "filter"),
        ("data-genui-field", field.to_string()),
        ("data-genui-operator", filter_operator_name(operator)),
      ])
    Summary(field~, aggregation~) =>
      lower_leaf("div", [
        ("data-genui-kind", "summary"),
        ("data-genui-field", field.to_string()),
        ("data-genui-aggregation", aggregation_name(aggregation)),
      ])
    Text(value~) => lower_text(value)
  }
}

///|
fn lower_container(
  tag : String,
  attrs : Array[(String, String)],
  children : Array[@cognition.GenerativeUiCandidateNode],
) -> Result[String, String] {
  match lower_children(children) {
    Ok(content) => Ok(open_tag(tag, attrs) + content + close_tag(tag))
    Err(message) => Err(message)
  }
}

///|
fn lower_leaf(
  tag : String,
  attrs : Array[(String, String)],
) -> Result[String, String] {
  Ok(open_tag(tag, attrs) + close_tag(tag))
}

///|
fn lower_children(
  children : Array[@cognition.GenerativeUiCandidateNode],
) -> Result[String, String] {
  let lowered : Array[String] = []
  for child in children {
    match lower_candidate_node(child) {
      Ok(value) => lowered.push(value)
      Err(message) => return Err(message)
    }
  }
  Ok(lowered.join(""))
}

///|
fn lower_text(value : String) -> Result[String, String] {
  if value.contains_char('<') ||
    value.contains_char('>') ||
    value.contains_char('{') ||
    value.contains_char('}') {
    return Err("candidate text contains JSX syntax characters")
  }
  Ok(value)
}

///|
fn open_tag(tag : String, attrs : Array[(String, String)]) -> String {
  "<" +
  tag +
  attrs
  .map(fn(pair) {
    let (name, value) = pair
    " " + name + "=\"" + escape_attribute(value) + "\""
  })
  .join("") +
  ">"
}

///|
fn close_tag(tag : String) -> String {
  "</" + tag + ">"
}

///|
fn escape_attribute(value : String) -> String {
  value
  .replace_all(old="&", new="&amp;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
}

///|
fn filter_operator_name(
  operator : @cognition.GenerativeUiFilterOperator,
) -> String {
  match operator {
    Equal => "eq"
    NotEqual => "neq"
    Contains => "contains"
    GreaterThan => "gt"
    LessThan => "lt"
  }
}

///|
fn aggregation_name(aggregation : @cognition.GenerativeUiAggregation) -> String {
  match aggregation {
    Count => "count"
    Sum => "sum"
    Average => "average"
    Minimum => "min"
    Maximum => "max"
  }
}
