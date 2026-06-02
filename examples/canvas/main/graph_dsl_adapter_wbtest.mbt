///|
using @graph_model {empty_interaction, port}

///|
const GRAPH_DSL_SAMPLE = "osc = sine(freq: 440Hz, wave: \"saw\") -> audio\nfilter = lowpass(input: osc, cutoff: 1200Hz, mode: warm)"

///|
fn ok_graph_doc(
  result : Result[@graph_dsl.GraphDoc, Array[String]],
) -> @graph_dsl.GraphDoc {
  match result {
    Ok(doc) => doc
    Err(messages) =>
      abort("expected graph-dsl projection, got: " + messages.join("; "))
  }
}

///|
fn ok_current_graph_doc(
  result : Result[@graph_dsl.GraphDoc, String],
) -> @graph_dsl.GraphDoc {
  match result {
    Ok(doc) => doc
    Err(message) => abort("expected current graph-dsl projection: " + message)
  }
}

///|
fn ok_last_good(doc : @graph_dsl.GraphDoc?) -> @graph_dsl.GraphDoc {
  match doc {
    Some(doc) => doc
    None => abort("expected last-good graph-dsl projection")
  }
}

///|
fn ok_lowered(
  edit : @graph_dsl.LoweredGraphEdit?,
) -> @graph_dsl.LoweredGraphEdit {
  match edit {
    Some(edit) => edit
    None => abort("expected lowered graph edit")
  }
}

///|
fn graph_node_id(doc : @graph_dsl.GraphDoc, binding : String) -> String {
  match doc.find_node(binding) {
    Some(node) => node.id()
    None => abort("missing graph node: " + binding)
  }
}

///|
fn canvas_id_for_binding(doc : @graph_dsl.GraphDoc, binding : String) -> NodeId {
  for i, node in doc.nodes() {
    if node.binding() == binding {
      return NodeId(i + 1)
    }
  }
  abort("missing graph binding: " + binding)
}

///|
fn graph_input_reference(param : @graph_dsl.GraphParam) -> String? {
  for token in param.value_tokens() {
    if token.role() == @graph_dsl.InputReference {
      return Some(token.text())
    }
  }
  None
}

///|
fn canvas_node_from_graph_node(
  index : Int,
  graph_node : @graph_dsl.GraphNode,
) -> CanvasNode {
  {
    id: NodeId(index + 1),
    x: index.to_double() * 300.0,
    y: 0.0,
    w: 250.0,
    h: 138.0,
    kind: Workflow(Custom(graph_node.constructor_name())),
    title: graph_node.binding(),
    subtitle: graph_node.constructor_name(),
    inputs: [port("input", "input", Any)],
    outputs: [port("out", "out", Any)],
    configured: true,
  }
}

///|
fn canvas_from_graph_doc(doc : @graph_dsl.GraphDoc) -> CanvasState {
  let nodes : Array[CanvasNode] = []
  for i, graph_node in doc.nodes() {
    nodes.push(canvas_node_from_graph_node(i, graph_node))
  }
  let edges : Array[Edge] = []
  for target_index, graph_node in doc.nodes() {
    for param in graph_node.params() {
      match graph_input_reference(param) {
        None => ()
        Some(source_binding) =>
          edges.push({
            id: EdgeId(edges.length() + 1),
            source: canvas_id_for_binding(doc, source_binding),
            source_port: "out",
            target: NodeId(target_index + 1),
            target_port: param.name(),
          })
      }
    }
  }
  {
    viewport: { x: 0.0, y: 0.0, scale: 1.0 },
    nodes,
    edges,
    next_node_id: nodes.length() + 1,
    next_edge_id: edges.length() + 1,
    interaction: empty_interaction(),
    action_log: [],
  }
}

///|
test "graph-dsl projection maps into the canvas graph view model" {
  let doc = ok_graph_doc(@graph_dsl.project_graph_source(GRAPH_DSL_SAMPLE))
  let canvas = canvas_from_graph_doc(doc)
  match canvas.nodes {
    [osc, filter] => {
      inspect(osc.title, content="osc")
      inspect(osc.subtitle, content="sine")
      inspect(filter.title, content="filter")
      inspect(filter.subtitle, content="lowpass")
      match canvas.edges {
        [edge] => {
          @debug.assert_eq(edge.source, osc.id)
          @debug.assert_eq(edge.target, filter.id)
          inspect(edge.target_port, content="input")
        }
        _ => abort("expected exactly one canvas edge")
      }
    }
    _ => abort("expected exactly two canvas nodes")
  }
}

///|
test "SetParam lowers to an exact source edit and preserves graph ids" {
  let attachment = @graph_dsl.GraphAttachment::GraphAttachment(GRAPH_DSL_SAMPLE)
  let before = ok_current_graph_doc(attachment.current_result())
  let osc_id = graph_node_id(before, "osc")
  let filter_id = graph_node_id(before, "filter")
  let lowered = ok_lowered(before.lower_set_numeric("osc", "freq", "880"))
  match lowered.incremental_edit() {
    Some(edit) => attachment.apply_edit(edit, lowered.new_source())
    None => abort("expected one exact incremental edit")
  }
  inspect(attachment.state(), content="Current")
  let after = ok_current_graph_doc(attachment.current_result())
  match after.tokens_for_role(@graph_dsl.NumericParameter) {
    [number, ..] => inspect(number.text(), content="880")
    [] => abort("expected a numeric parameter token")
  }
  inspect(
    after.source(),
    content="osc = sine(freq: 880Hz, wave: \"saw\") -> audio\nfilter = lowpass(input: osc, cutoff: 1200Hz, mode: warm)",
  )
  @debug.assert_eq(graph_node_id(after, "osc"), osc_id)
  @debug.assert_eq(graph_node_id(after, "filter"), filter_id)
  let canvas = canvas_from_graph_doc(after)
  @debug.assert_eq(canvas.edges.length(), 1)
  attachment.dispose()
}

///|
test "ConnectPorts and AddNode lower through source and reparse to canvas graph" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let doc = ok_graph_doc(@graph_dsl.project_graph_source(source))
  let connect = ok_lowered(doc.lower_add_connection("meter", "osc"))
  inspect(
    connect.new_source(),
    content="osc = sine(freq: 440Hz)\nmeter = scope(input: osc)",
  )
  let connected = ok_graph_doc(
    @graph_dsl.project_graph_source(connect.new_source()),
  )
  let connected_canvas = canvas_from_graph_doc(connected)
  match connected_canvas.edges {
    [edge] => {
      @debug.assert_eq(edge.source, canvas_id_for_binding(connected, "osc"))
      @debug.assert_eq(edge.target, canvas_id_for_binding(connected, "meter"))
    }
    _ => abort("expected exactly one canvas edge")
  }

  let insert = ok_lowered(
    connected.lower_insert_node_binding("reverb", "plate"),
  )
  inspect(
    insert.new_source(),
    content="osc = sine(freq: 440Hz)\nmeter = scope(input: osc)\nreverb = plate()",
  )
  let inserted = ok_graph_doc(
    @graph_dsl.project_graph_source(insert.new_source()),
  )
  let inserted_canvas = canvas_from_graph_doc(inserted)
  match inserted_canvas.nodes {
    [_, _, reverb] => {
      inspect(reverb.title, content="reverb")
      inspect(reverb.subtitle, content="plate")
    }
    _ => abort("expected three canvas nodes after AddNode")
  }
}

///|
test "invalid source keeps last-good canvas graph available" {
  let attachment = @graph_dsl.GraphAttachment::GraphAttachment(GRAPH_DSL_SAMPLE)
  let good = ok_current_graph_doc(attachment.current_result())
  let good_canvas = canvas_from_graph_doc(good)

  attachment.set_source("osc = sine(freq: )")
  inspect(attachment.state(), content="ParserBlocked")
  let parser_blocked = ok_last_good(attachment.last_good())
  @debug.assert_eq(parser_blocked, good)
  @debug.assert_eq(
    canvas_from_graph_doc(parser_blocked).nodes.length(),
    good_canvas.nodes.length(),
  )

  attachment.set_source("osc = sine(input: missing)")
  inspect(attachment.state(), content="ProjectionBlocked")
  let projection_blocked = ok_last_good(attachment.last_good())
  @debug.assert_eq(projection_blocked, good)
  @debug.assert_eq(
    canvas_from_graph_doc(projection_blocked).edges.length(),
    good_canvas.edges.length(),
  )
  attachment.dispose()
}
