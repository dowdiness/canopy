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
fn operation_result_applied(json_text : String) -> Bool {
  let json = @json.parse(json_text) catch {
    _ => abort("expected operation result JSON")
  }
  match json {
    Json::Object(fields) =>
      match fields.get("applied") {
        Some(Json::True) => true
        Some(Json::False) => false
        _ => abort("expected operation result applied flag")
      }
    _ => abort("expected operation result object")
  }
}

///|
fn ok_operation_log(json_text : String) -> Array[GraphOperation] {
  let json = @json.parse(json_text) catch {
    _ => abort("expected operation log JSON")
  }
  @json.from_json(json) catch {
    _ => abort("expected GraphOperation array")
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
fn required_canvas_id_for_binding(
  doc : @graph_dsl.GraphDoc,
  binding : String,
) -> NodeId {
  match canvas_id_for_binding(doc, binding) {
    Some(id) => id
    None => abort("missing graph binding: " + binding)
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
      @debug.assert_eq(
        edge.source,
        required_canvas_id_for_binding(connected, "osc"),
      )
      @debug.assert_eq(
        edge.target,
        required_canvas_id_for_binding(connected, "meter"),
      )
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
test "source-backed handle lowers GraphOperation through graph-dsl source" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)\nmeter = scope()")
  let connect = GraphOperation(
    ConnectPorts(NodeId(1), "out", NodeId(2), "input"),
  )
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, connect.to_json().stringify()),
    ),
    content="true",
  )
  inspect(
    get_source_graph_source(handle),
    content="osc = sine(freq: 440Hz)\nmeter = scope(input: osc)",
  )
  let added : CanvasNode = {
    id: NodeId(3),
    x: 0.0,
    y: 0.0,
    w: 250.0,
    h: 138.0,
    kind: Workflow(Custom("plate")),
    title: "reverb",
    subtitle: "plate",
    inputs: [],
    outputs: [],
    configured: true,
  }
  let insert = GraphOperation(AddNode(added))
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, insert.to_json().stringify()),
    ),
    content="true",
  )
  inspect(
    get_source_graph_source(handle),
    content="osc = sine(freq: 440Hz)\nmeter = scope(input: osc)\nreverb = plate()",
  )
  let operations = ok_operation_log(get_source_graph_action_log(handle))
  match operations {
    [_, added] =>
      match added.action() {
        AddNode(node) => @debug.assert_eq(node.id, NodeId(3))
        _ => abort("expected AddNode action")
      }
    _ => abort("expected two source-backed operations")
  }
  destroy_source_graph(handle)
}

///|
test "source-backed unique insert chooses a fresh graph-dsl binding" {
  let handle = create_source_graph("reverb = plate()")
  inspect(
    operation_result_applied(
      source_graph_insert_unique(handle, "reverb", "plate"),
    ),
    content="true",
  )
  inspect(
    get_source_graph_source(handle),
    content="reverb = plate()\nreverb2 = plate()",
  )
  let operations = ok_operation_log(get_source_graph_action_log(handle))
  match operations {
    [added] =>
      match added.action() {
        AddNode(node) => {
          inspect(node.title, content="reverb2")
          @debug.assert_eq(node.id, NodeId(2))
        }
        _ => abort("expected AddNode action")
      }
    _ => abort("expected one source-backed unique insert operation")
  }
  destroy_source_graph(handle)
}

///|
test "source-backed handle rejects local graph operations without mutating source" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let handle = create_source_graph(source)
  let viewport : Viewport = { x: 12.0, y: 24.0, scale: 2.0 }
  let local_operation = GraphOperation(SetViewport(viewport))
  inspect(
    operation_result_applied(
      apply_source_graph_operation(
        handle,
        local_operation.to_json().stringify(),
      ),
    ),
    content="false",
  )
  inspect(get_source_graph_source(handle), content=source)
  inspect(get_source_graph_action_log(handle), content="[]")
  destroy_source_graph(handle)
}

///|
test "source-backed handle reports invalid source apply status" {
  let source = "osc = sine(freq: 440Hz)\nmeter = scope()"
  let handle = create_source_graph(source)
  inspect(
    operation_result_applied(
      set_source_graph_source_result(handle, "osc = sine(freq: )"),
    ),
    content="false",
  )
  inspect(get_source_graph_source(handle), content="osc = sine(freq: )")
  inspect(
    operation_result_applied(
      set_source_graph_source_result(handle, "osc = sine(input: missing)"),
    ),
    content="false",
  )
  inspect(get_source_graph_source(handle), content="osc = sine(input: missing)")
  inspect(
    operation_result_applied(set_source_graph_source_result(handle, source)),
    content="true",
  )
  inspect(get_source_graph_source(handle), content=source)
  destroy_source_graph(handle)
}

///|
test "source-backed handle rejects graph operations while source is invalid" {
  let handle = create_source_graph("osc = sine(freq: 440Hz)\nmeter = scope()")
  set_source_graph_source(handle, "osc = sine(freq: )")
  let connect = GraphOperation(
    ConnectPorts(NodeId(1), "out", NodeId(2), "input"),
  )
  inspect(
    operation_result_applied(
      apply_source_graph_operation(handle, connect.to_json().stringify()),
    ),
    content="false",
  )
  inspect(get_source_graph_source(handle), content="osc = sine(freq: )")
  destroy_source_graph(handle)
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
