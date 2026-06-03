///|
fn horizontal_space(code_unit : UInt16) -> Bool {
  code_unit == ' ' || code_unit == '\t'
}

///|
fn param_start_after_lparen_space(source : String, start : Int) -> Int {
  let mut cursor = start
  while cursor > 0 && horizontal_space(source[cursor - 1]) {
    cursor -= 1
  }
  if cursor > 0 && source[cursor - 1] == '(' {
    cursor
  } else {
    start
  }
}

///|
fn param_end_before_rparen_space(source : String, end : Int) -> Int {
  let mut cursor = end
  while cursor < source.length() && horizontal_space(source[cursor]) {
    cursor += 1
  }
  if cursor < source.length() && source[cursor] == ')' {
    cursor
  } else {
    end
  }
}

///|
fn graph_param_text_end(param : @graph_dsl.GraphParam) -> Int? {
  let value_tokens = param.value_tokens()
  if value_tokens.length() == 0 {
    return None
  }
  let mut end = param.name_token().end()
  for token in value_tokens {
    if token.end() > end {
      end = token.end()
    }
  }
  Some(end)
}

///|
fn graph_param_matches_edge(
  param : @graph_dsl.GraphParam,
  target_port : String,
  source_binding : String,
) -> Bool {
  param.name() == target_port &&
  graph_input_reference(param) == Some(source_binding)
}

///|
fn disconnect_param_index(
  params : Array[@graph_dsl.GraphParam],
  target_port : String,
  source_binding : String,
) -> Int? {
  for index, param in params {
    if graph_param_matches_edge(param, target_port, source_binding) {
      return Some(index)
    }
  }
  None
}

///|
fn removal_span_for_graph_param(
  source : String,
  params : Array[@graph_dsl.GraphParam],
  index : Int,
) -> SourceDeletionSpan? {
  if index < 0 || index >= params.length() {
    return None
  }
  let param = params[index]
  let start = if index == 0 {
    param_start_after_lparen_space(source, param.name_token().start())
  } else {
    param.name_token().start()
  }
  let end = match graph_param_text_end(param) {
    Some(end) =>
      if index + 1 < params.length() {
        end
      } else {
        param_end_before_rparen_space(source, end)
      }
    None => return None
  }
  if index + 1 < params.length() {
    Some({ start, end: params[index + 1].name_token().start() })
  } else if index > 0 {
    match graph_param_text_end(params[index - 1]) {
      Some(previous_end) => Some({ start: previous_end, end })
      None => None
    }
  } else {
    Some({ start, end })
  }
}

///|
fn lower_disconnect_ports(
  doc : @graph_dsl.GraphDoc,
  source : NodeId,
  source_port : String,
  target : NodeId,
  target_port : String,
) -> Result[SourceOperationEdit, String] {
  if source_port != "out" {
    return Err("graph-dsl source disconnections must use port 'out'")
  }
  let source_node = match graph_node_for_canvas_id(doc, source) {
    Some(node) => node
    None => return Err("cannot lower DisconnectPorts: missing source node")
  }
  let target_node = match graph_node_for_canvas_id(doc, target) {
    Some(node) => node
    None => return Err("cannot lower DisconnectPorts: missing target node")
  }
  let params = target_node.params()
  let index = match
    disconnect_param_index(params, target_port, source_node.binding()) {
    Some(index) => index
    None => return Err("cannot lower DisconnectPorts: missing edge")
  }
  let span = match removal_span_for_graph_param(doc.source(), params, index) {
    Some(span) => span
    None => return Err("cannot lower DisconnectPorts into source")
  }
  match apply_deletion_spans(doc.source(), [span]) {
    Some(new_source) => Ok(WholeSourceReplacement(new_source))
    None => Err("cannot lower DisconnectPorts into source")
  }
}
